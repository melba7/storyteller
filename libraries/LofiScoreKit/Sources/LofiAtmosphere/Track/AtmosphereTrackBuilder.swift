import Foundation
import LofiText

/// Scores a whole book once, ahead of playback, into an ``AtmosphereTrack``.
///
/// The first pass goes through the book in order, one scoring point every
/// `wordsBetweenEntries` narrated words plus one a few sentences into every chapter.
/// It has to go in order: each request carries the ``PlaceMemory`` of the entries
/// before it, so a return to a place is recognised and keeps its sounds.
///
/// Then, with refinement on, it pins each change of scene to within a few sentences,
/// the way ``MoodTrackBuilder`` pins mood changes: between two neighbouring entries
/// whose scenes differ it scores the sentence halfway, then halfway again on the side
/// the change fell, until the change is known to within `resolutionSentences`.
///
/// Spoiler safety: every entry, probes included, is judged from
/// `SpoilerGuard.window(at:)` for its own sentence and the memory of entries before it,
/// so it depends only on text up to its sentence. What does depend on later text is
/// where probes are spent (only between entries that disagree), the same accepted cost
/// as for mood tracks. Place ids are labels: a probe that finds the start of a place
/// first named by the next entry takes that entry's id, which changes nothing audible
/// before the text reaches the place.
public struct AtmosphereTrackBuilder: Sendable {
    public struct Plan: Sendable, Hashable {
        /// About 100 seconds of narration at 150 words a minute.
        public var wordsBetweenEntries: Int
        /// 1-based sentence of each chapter that always gets an entry.
        public var sentencesIntoNewChapter: Int
        public var refinement: Refinement?

        public init(wordsBetweenEntries: Int = 250, sentencesIntoNewChapter: Int = 3, refinement: Refinement? = Refinement()) {
            self.wordsBetweenEntries = max(20, wordsBetweenEntries)
            self.sentencesIntoNewChapter = max(1, sentencesIntoNewChapter)
            self.refinement = refinement
        }
    }

    public struct Refinement: Sendable, Hashable {
        /// Stop narrowing once a change is pinned to this many sentences.
        public var resolutionSentences: Int
        /// Extra requests allowed, as a share of the planned entries.
        public var probeBudget: Double

        public init(resolutionSentences: Int = 3, probeBudget: Double = 0.5) {
            self.resolutionSentences = max(1, resolutionSentences)
            self.probeBudget = max(0, probeBudget)
        }

        public func maxProbes(planned: Int) -> Int {
            Int((Double(planned) * probeBudget).rounded(.up))
        }
    }

    public struct Report: Sendable, Hashable {
        public var planned = 0
        public var alreadyScored = 0
        public var scored = 0
        public var probes = 0
        public var probeBudget = 0
        public var unrefinedChanges = 0
        public var failed = 0
        public var failures: [String] = []
        public var stoppedEarly = false
        public var places = 0
        /// More specific sounds the track uses, and how many of them it asked for itself.
        public var variants = 0
        public var newVariants = 0
    }

    public let spoilerGuard: SpoilerGuard
    public let plan: Plan
    /// More specific sounds the scorer may use anywhere in the book: the starter set and
    /// other books' variants (``SoundVariantCatalog/offered(toBook:)``), never this book's
    /// own from an earlier run. The book's own variants come from its track, each only
    /// after the entry that first asked for it.
    public let offeredVariants: [SoundVariant]

    public init(spoilerGuard: SpoilerGuard, plan: Plan = Plan(), offeredVariants: [SoundVariant] = []) {
        self.spoilerGuard = spoilerGuard
        self.plan = plan
        self.offeredVariants = offeredVariants
    }

    /// Every narrated sentence, in order.
    public func narratedPositions() throws -> [SentencePosition] {
        var all: [SentencePosition] = []
        var current = try spoilerGuard.firstPosition()
        while let position = current {
            all.append(position)
            current = try spoilerGuard.position(after: position)
        }
        return all
    }

    /// Global index of each chapter's first narrated sentence.
    public static func chapterStarts(_ narrated: [SentencePosition]) -> [Int] {
        var starts: [Int] = []
        var chapter: Int?
        for position in narrated where position.chapterOrdinal != chapter {
            starts.append(position.globalIndex)
            chapter = position.chapterOrdinal
        }
        return starts
    }

    /// The positions scored in the first pass, in order.
    public func scoringPositions(_ all: [SentencePosition]) throws -> [SentencePosition] {
        var points: [SentencePosition] = []
        var wordsSince = 0
        for (i, position) in all.enumerated() {
            let sentence = try spoilerGuard.window(at: position).lines.last?.text ?? ""
            let words = TextNormalizer.wordCount(sentence)
            let next = i + 1 < all.count ? all[i + 1] : nil
            let chapterChanged = i == 0 || all[i - 1].chapterOrdinal != position.chapterOrdinal
            wordsSince = chapterChanged ? words : wordsSince + words
            let chapterStartPoint = position.sentenceIndex == plan.sentencesIntoNewChapter - 1
            let lastOfShortChapter = position.sentenceIndex < plan.sentencesIntoNewChapter - 1
                && (next.map { $0.chapterOrdinal != position.chapterOrdinal } ?? true)
            if chapterStartPoint || lastOfShortChapter
                || (position.sentenceIndex >= plan.sentencesIntoNewChapter && wordsSince >= plan.wordsBetweenEntries) {
                points.append(position)
                wordsSince = 0
            }
        }
        return points
    }

    /// Scores what the store does not have yet: first the planned points in order, then
    /// probes at the changes of scene. Failures are counted and skipped; run again to
    /// retry them. `continueIf` is asked before each request (a spending cap).
    public func build(
        into store: AtmosphereTrackStore,
        engine: any SceneEngine,
        concurrency: Int = 4,
        continueIf: (@Sendable () -> Bool)? = nil,
        onEntry: (@Sendable (AtmosphereTrack.Entry, Int) -> Void)? = nil
    ) async throws -> Report {
        let all = try narratedPositions()
        store.update { $0.chapterStarts = Self.chapterStarts(all) }
        let positions = try scoringPositions(all)
        var report = Report()
        report.planned = positions.count
        let todo = positions.filter { !store.contains($0) }
        report.alreadyScored = positions.count - todo.count

        var added = 0
        // First pass: strictly in order, so each request knows every place before it.
        for position in todo {
            if let continueIf, !continueIf() {
                report.stoppedEarly = true
                break
            }
            do {
                let entry = try await score(position, into: store, engine: engine, nextEntry: nil)
                added += 1
                report.scored += 1
                onEntry?(entry, added)
            } catch {
                report.failed += 1
                if report.failures.count < 20 { report.failures.append("\(position): \(error)") }
            }
        }

        if let refinement = plan.refinement, !report.stoppedEarly {
            report.probeBudget = refinement.maxProbes(planned: positions.count)
            let planned = Set(positions.map(\.globalIndex))
            let earlier = store.snapshot.entries.filter { !planned.contains($0.globalIndex) }.count
            var budget = max(0, report.probeBudget - earlier)
            var failedProbes = Set<Int>()
            let roundSize = max(4, concurrency * 2)
            while true {
                let candidates = Self.refinableChanges(
                    in: store.snapshot.entries, narrated: all,
                    resolution: refinement.resolutionSentences, excluding: failedProbes
                )
                report.unrefinedChanges = candidates.count
                guard budget > 0, !candidates.isEmpty else { break }
                let round = Array(candidates.prefix(min(budget, roundSize)))
                budget -= round.count
                let result = await scoreProbes(round, into: store, engine: engine, concurrency: concurrency, continueIf: continueIf)
                for entry in result.entries {
                    added += 1
                    onEntry?(entry, added)
                }
                report.probes += result.entries.count
                report.failed += result.failed.count
                for (position, error) in result.failed {
                    failedProbes.insert(position.globalIndex)
                    if report.failures.count < 20 { report.failures.append("probe \(position): \(error)") }
                }
                if result.stopped {
                    report.stoppedEarly = true
                    break
                }
            }
        }
        let track = store.snapshot
        report.places = Set(track.entries.compactMap(\.scene.placeID)).count
        report.variants = track.variants.count
        let offered = Set(offeredVariants.map(\.id))
        report.newVariants = track.variants.filter { !offered.contains($0.id) }.count
        return report
    }

    /// Two scenes the listener would hear as different: another place, or other sounds
    /// (a variant counts as its own sound).
    static func differ(_ a: StoryScene, _ b: StoryScene) -> Bool {
        a.placeID != b.placeID || Set(a.layers.map(\.key)) != Set(b.layers.map(\.key))
    }

    /// The sentence halfway between each pair of neighbouring entries whose scenes differ
    /// and that are more than `resolution` sentences apart; a change of place first, then
    /// the widest gaps.
    static func refinableChanges(
        in entries: [AtmosphereTrack.Entry],
        narrated: [SentencePosition],
        resolution: Int,
        excluding failed: Set<Int>
    ) -> [SentencePosition] {
        var found: [(value: Int, probe: SentencePosition)] = []
        for (a, b) in zip(entries, entries.dropFirst()) where differ(a.scene, b.scene) {
            // A swell or hush pauses the narration right after its sentence, so it is
            // pinned to the sentence itself.
            let needed = b.scene.moment == nil ? resolution : 1
            guard b.globalIndex - a.globalIndex > needed else { continue }
            let target = a.globalIndex + (b.globalIndex - a.globalIndex) / 2
            guard let probe = position(atOrAfter: target, in: narrated),
                  probe.globalIndex > a.globalIndex, probe.globalIndex < b.globalIndex,
                  !failed.contains(probe.globalIndex)
            else { continue }
            let weight = a.scene.placeID != b.scene.placeID ? 2 : 1
            found.append((weight * (b.globalIndex - a.globalIndex), probe))
        }
        return found
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.probe.globalIndex < $1.probe.globalIndex }
            .map(\.probe)
    }

    private static func position(atOrAfter globalIndex: Int, in narrated: [SentencePosition]) -> SentencePosition? {
        var low = 0
        var high = narrated.count
        while low < high {
            let mid = (low + high) / 2
            if narrated[mid].globalIndex < globalIndex { low = mid + 1 } else { high = mid }
        }
        return low < narrated.count ? narrated[low] : nil
    }

    // MARK: - Scoring

    private func scoreProbes(
        _ positions: [SentencePosition],
        into store: AtmosphereTrackStore,
        engine: any SceneEngine,
        concurrency: Int,
        continueIf: (@Sendable () -> Bool)?
    ) async -> (entries: [AtmosphereTrack.Entry], failed: [(SentencePosition, String)], stopped: Bool) {
        var entries: [AtmosphereTrack.Entry] = []
        var failed: [(SentencePosition, String)] = []
        var stopped = false
        let width = max(1, concurrency)
        await withTaskGroup(of: (SentencePosition, Result<AtmosphereTrack.Entry, any Error>).self) { group in
            var next = 0
            func launch() {
                guard next < positions.count, !stopped else { return }
                if let continueIf, !continueIf() {
                    stopped = true
                    return
                }
                let position = positions[next]
                next += 1
                let following = store.snapshot.entries.first { $0.globalIndex > position.globalIndex }
                group.addTask {
                    do {
                        return (position, .success(try await self.score(position, into: store, engine: engine, nextEntry: following)))
                    } catch {
                        return (position, .failure(error))
                    }
                }
            }
            for _ in 0..<width { launch() }
            while let (position, result) = await group.next() {
                switch result {
                case let .success(entry): entries.append(entry)
                case let .failure(error): failed.append((position, "\(error)"))
                }
                launch()
            }
        }
        return (entries, failed, stopped)
    }

    /// Scores one position against the memory of the entries before it and stores it.
    /// `nextEntry` is the entry after a probe, so a new place found by the probe can take
    /// the id that entry already gave it.
    @discardableResult
    func score(
        _ position: SentencePosition,
        into store: AtmosphereTrackStore,
        engine: any SceneEngine,
        nextEntry: AtmosphereTrack.Entry?
    ) async throws -> AtmosphereTrack.Entry {
        let window = try spoilerGuard.window(at: position)
        let memory = PlaceMemory(track: store.snapshot, before: position.globalIndex, offered: offeredVariants)
        let answer = try await engine.scene(for: window, memory: memory)
        var entry: AtmosphereTrack.Entry!
        store.update { track in
            // Every variant the scene uses goes into the track, first used here at the
            // latest, so the track is complete on its own and the fetch knows what to find.
            let added = Dictionary(answer.newVariants.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for id in answer.scene.layers.compactMap(\.variant) {
                guard var variant = added[id] ?? memory.variant(id) else { continue }
                variant.firstIndex = position.globalIndex
                track.addVariant(variant)
            }
            var scene = answer.scene
            switch answer.place {
            case let .known(id):
                scene.placeID = id
            case .none:
                scene.placeID = nil
            case let .new(name):
                scene.placeID = Self.idForNewPlace(named: name, before: position.globalIndex, nextEntry: nextEntry, in: track)
                scene.placeName = name
            }
            entry = AtmosphereTrack.Entry(
                position: position,
                sentence: window.lines.last?.text ?? "",
                scene: scene,
                world: answer.world ?? memory.world
            )
            track.insert(entry)
        }
        return entry
    }

    /// A fresh id, unique in the whole track; or the id of the following entry's place
    /// when that place starts there (first named by that entry) under a matching name.
    static func idForNewPlace(named name: String, before globalIndex: Int, nextEntry: AtmosphereTrack.Entry?, in track: AtmosphereTrack) -> String {
        if let next = nextEntry, let id = next.scene.placeID,
           let nextName = next.scene.placeName, PlaceMemory.namesMatch(name, nextName),
           !track.entries(before: next.globalIndex).contains(where: { $0.scene.placeID == id && $0.globalIndex < globalIndex }) {
            return id
        }
        let highest = track.entries.compactMap { $0.scene.placeID.flatMap { Int($0.dropFirst()) } }.max() ?? 0
        return "p\(highest + 1)"
    }
}
