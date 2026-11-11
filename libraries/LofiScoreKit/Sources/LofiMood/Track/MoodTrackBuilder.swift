import Foundation
import LofiScoreCore
import LofiText

/// Scores a whole book once, ahead of playback, into a `MoodTrack`.
///
/// It picks a scoring point every `wordsBetweenEntries` narrated words, plus one
/// a few sentences into every chapter (where the live cadence takes its
/// chapter-start reading), and asks the engine about `SpoilerGuard.window(at:)`
/// for each point. Points already in the store are skipped, so an interrupted
/// build resumes where it stopped.
///
/// Then, with `Plan.refinement` on, it pins each mood change to the sentence
/// where it starts. Between two neighbouring entries whose moods differ it
/// scores the sentence halfway between, then halfway again on whichever side
/// the change fell, until the change is known to within a few sentences.
/// Without this, playback could switch up to `wordsBetweenEntries` words (about
/// 100 seconds) after the text turned; with it, within a few sentences. With
/// `Plan.settling` (the default) the moods compared are the settled ones, the
/// scene-length moods playback uses, so the probes go to the changes the
/// listener hears.
///
/// Spoiler safety: every probe is an ordinary entry, judged only from
/// `SpoilerGuard.window(at:)` for its own sentence, and playback still uses the
/// newest entry at or before the narrated sentence. So the music never changes
/// before the narrated text itself reads as the new mood. What does depend on
/// later text is where probes are spent: only between entries that disagree.
/// A brief mood that has passed again by the next entry is not looked for, so
/// a change heard during playback is, slightly more often than chance, one
/// that lasts. That is the accepted cost of not scoring every sentence.
public struct MoodTrackBuilder: Sendable {
    public struct Plan: Sendable, Hashable {
        /// About 100 seconds of narration at 150 words a minute.
        public var wordsBetweenEntries: Int
        /// 1-based sentence of each chapter that always gets an entry; matches
        /// `ReadingCadence.Configuration.sentencesIntoNewChapter`.
        public var sentencesIntoNewChapter: Int
        /// Narrowing mood changes down between entries; nil turns it off.
        public var refinement: Refinement?
        /// How playback will settle the track into scenes. Refinement then
        /// pins down the changes between scenes, the ones the listener
        /// hears, and spends nothing on turns that settling leaves out. nil
        /// pins down every turn between neighbouring entries.
        public var settling: MoodSettling?

        public init(
            wordsBetweenEntries: Int = 250, sentencesIntoNewChapter: Int = 3,
            refinement: Refinement? = Refinement(), settling: MoodSettling? = .standard
        ) {
            self.wordsBetweenEntries = max(20, wordsBetweenEntries)
            self.sentencesIntoNewChapter = max(1, sentencesIntoNewChapter)
            self.refinement = refinement
            self.settling = settling
        }
    }

    public struct Refinement: Sendable, Hashable {
        /// Stop narrowing once a change is pinned to this many sentences
        /// (about 15 seconds of narration at the default of 3).
        public var resolutionSentences: Int
        /// Extra readings allowed per book, as a share of the planned
        /// entries; 0.6 means at most 60% more readings (and cost) than the
        /// track alone. Probes go best first: the change with the biggest
        /// jump in mood (distance between bucket anchors) times the number
        /// of sentences it could still be late by. So a calm-to-tense turn
        /// is pinned down fully before a calm-to-cozy drift is looked at.
        public var probeBudget: Double

        public init(resolutionSentences: Int = 3, probeBudget: Double = 0.6) {
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
        /// Refinement readings made in this run.
        public var probes = 0
        /// Refinement readings already in the store from earlier runs.
        public var earlierProbes = 0
        /// Probes the budget allowed in total, earlier runs included.
        public var probeBudget = 0
        /// Neighbouring entries that still disagree and are further apart
        /// than the resolution, because the budget ran out or probes failed.
        public var unrefinedChanges = 0
        public var failed = 0
        public var failures: [String] = []
        /// `continueIf` said stop before everything was scored.
        public var stoppedEarly = false
    }

    public let spoilerGuard: SpoilerGuard
    public let plan: Plan

    public init(spoilerGuard: SpoilerGuard, plan: Plan = Plan()) {
        self.spoilerGuard = spoilerGuard
        self.plan = plan
    }

    /// Every narrated sentence in `chapters` (the whole book when nil), in order.
    public func narratedPositions(chapters: ClosedRange<Int>? = nil) throws -> [SentencePosition] {
        var all: [SentencePosition] = []
        var current = try spoilerGuard.firstPosition()
        while let position = current {
            if let chapters, position.chapterOrdinal > chapters.upperBound { break }
            if chapters?.contains(position.chapterOrdinal) ?? true { all.append(position) }
            current = try spoilerGuard.position(after: position)
        }
        return all
    }

    /// The positions a track for this book holds before refinement, in order.
    public func scoringPositions(chapters: ClosedRange<Int>? = nil) throws -> [SentencePosition] {
        let all = try narratedPositions(chapters: chapters)
        var points: [SentencePosition] = []
        var wordsSince = 0
        for (i, position) in all.enumerated() {
            let sentence = try spoilerGuard.window(at: position).lines.last?.text ?? ""
            let words = TextNormalizer.wordCount(sentence)
            let next = i + 1 < all.count ? all[i + 1] : nil
            let chapterChanged = i == 0 || all[i - 1].chapterOrdinal != position.chapterOrdinal
            wordsSince = chapterChanged ? words : wordsSince + words

            let chapterStartPoint = position.sentenceIndex == plan.sentencesIntoNewChapter - 1
            // A chapter shorter than the chapter-start point still gets one entry.
            let lastOfShortChapter = position.sentenceIndex < plan.sentencesIntoNewChapter - 1
                && (next.map { $0.chapterOrdinal != position.chapterOrdinal } ?? true)
            if chapterStartPoint || lastOfShortChapter || (position.sentenceIndex >= plan.sentencesIntoNewChapter && wordsSince >= plan.wordsBetweenEntries) {
                points.append(position)
                wordsSince = 0
            }
        }
        return points
    }

    /// Scores every planned position the store does not have yet, `concurrency`
    /// at a time, adding each entry to the store as soon as it arrives; then
    /// refines mood changes if the plan asks for it. Failures are counted and
    /// skipped; run again to retry them.
    ///
    /// `onEntry` gets each new entry and the number added so far in this run.
    /// `continueIf` is asked before each new reading starts (a spending cap,
    /// say); once it says no, readings in flight finish and nothing new starts.
    public func build(
        into store: MoodTrackStore,
        engine: any MoodEngine,
        chapters: ClosedRange<Int>? = nil,
        concurrency: Int = 4,
        continueIf: (@Sendable () -> Bool)? = nil,
        onEntry: (@Sendable (MoodTrack.Entry, Int) -> Void)? = nil
    ) async throws -> Report {
        let positions = try scoringPositions(chapters: chapters)
        var report = Report()
        report.planned = positions.count
        let todo = positions.filter { !store.contains($0) }
        report.alreadyScored = positions.count - todo.count

        var added = 0
        let first = try await score(todo, into: store, engine: engine, concurrency: concurrency, continueIf: continueIf) { entry in
            added += 1
            onEntry?(entry, added)
        }
        report.stoppedEarly = first.stopped
        report.scored = first.scored
        report.failed += first.failed.count
        report.failures += first.failed.prefix(20).map { "\($0.position): \($0.error)" }

        if let refinement = plan.refinement, !report.stoppedEarly {
            try await refine(
                into: store, engine: engine, planned: positions, refinement: refinement,
                chapters: chapters, concurrency: concurrency, continueIf: continueIf, report: &report
            ) { entry in
                added += 1
                onEntry?(entry, added)
            }
        }
        return report
    }

    // MARK: - Refinement

    private func refine(
        into store: MoodTrackStore,
        engine: any MoodEngine,
        planned: [SentencePosition],
        refinement: Refinement,
        chapters: ClosedRange<Int>?,
        concurrency: Int,
        continueIf: (@Sendable () -> Bool)?,
        report: inout Report,
        onEntry: (MoodTrack.Entry) -> Void
    ) async throws {
        let all = try narratedPositions(chapters: chapters)
        let plannedKeys = Set(planned.map(SentenceKey.init))
        let inRange = { (entry: MoodTrack.Entry) in chapters?.contains(entry.chapterOrdinal) ?? true }
        report.earlierProbes = store.snapshot.entries.filter { inRange($0) && !plannedKeys.contains($0.key) }.count
        report.probeBudget = refinement.maxProbes(planned: planned.count)
        var budget = max(0, report.probeBudget - report.earlierProbes)
        var failedProbes = Set<Int>()

        // Best first, a few probes at a time: each round re-ranks what is
        // left, so a big change keeps being narrowed while small ones wait.
        let roundSize = max(4, concurrency * 2)
        while true {
            let candidates = Self.refinableChanges(
                in: store.snapshot.entries.filter(inRange), narrated: all,
                resolution: refinement.resolutionSentences, excluding: failedProbes, settling: plan.settling
            )
            report.unrefinedChanges = candidates.count
            guard budget > 0, !candidates.isEmpty else { break }
            let round = Array(candidates.prefix(min(budget, roundSize)))
            budget -= round.count
            let result = try await score(round, into: store, engine: engine, concurrency: concurrency, continueIf: continueIf, onEntry: onEntry)
            report.probes += result.scored
            if result.stopped {
                report.stoppedEarly = true
                break
            }
            report.failed += result.failed.count
            for failure in result.failed {
                failedProbes.insert(failure.position.globalIndex)
                if report.failures.count < 20 { report.failures.append("probe \(failure.position): \(failure.error)") }
            }
        }
    }

    /// The sentence halfway between each pair of neighbouring entries that
    /// disagree and are more than `resolution` sentences apart, most useful
    /// first: mood jump times the sentences the change could be late by.
    /// With `settling`, the moods compared are the settled ones, so only the
    /// changes between scenes are narrowed.
    static func refinableChanges(
        in entries: [MoodTrack.Entry],
        narrated: [SentencePosition],
        resolution: Int,
        excluding failed: Set<Int>,
        settling: MoodSettling? = nil
    ) -> [SentencePosition] {
        let moods = settling?.moods(for: entries) ?? entries.map(\.reading.bucket)
        var found: [(value: Double, probe: SentencePosition)] = []
        for i in entries.indices.dropLast() where moods[i] != moods[i + 1] {
            let (a, b) = (entries[i], entries[i + 1])
            guard b.globalIndex - a.globalIndex > resolution else { continue }
            let target = a.globalIndex + (b.globalIndex - a.globalIndex) / 2
            guard let probe = position(atOrAfter: target, in: narrated),
                  probe.globalIndex > a.globalIndex, probe.globalIndex < b.globalIndex,
                  !failed.contains(probe.globalIndex)
            else { continue }
            let jump = moods[i].anchor.distance(to: moods[i + 1].anchor)
            found.append((jump * Double(b.globalIndex - a.globalIndex), probe))
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

    private struct Failure {
        let position: SentencePosition
        let error: any Error
    }

    /// Scores `positions`, `concurrency` at a time, inserting each entry as it arrives.
    private func score(
        _ positions: [SentencePosition],
        into store: MoodTrackStore,
        engine: any MoodEngine,
        concurrency: Int,
        continueIf: (@Sendable () -> Bool)? = nil,
        onEntry: (MoodTrack.Entry) -> Void
    ) async throws -> (scored: Int, failed: [Failure], stopped: Bool) {
        var scored = 0
        var failed: [Failure] = []
        var stopped = false
        let width = max(1, concurrency)
        let spoilerGuard = self.spoilerGuard
        try await withThrowingTaskGroup(of: (SentencePosition, Result<MoodTrack.Entry, any Error>).self) { group in
            var next = 0
            func launch() {
                guard next < positions.count, !stopped else { return }
                if let continueIf, !continueIf() {
                    stopped = true
                    return
                }
                let position = positions[next]
                next += 1
                group.addTask {
                    do {
                        let window = try spoilerGuard.window(at: position)
                        let reading = try await engine.reading(for: window)
                        return (position, .success(MoodTrack.Entry(position: position, sentence: window.lines.last?.text ?? "", reading: reading)))
                    } catch {
                        return (position, .failure(error))
                    }
                }
            }
            for _ in 0..<width { launch() }
            while let finished = try await group.next() {
                let (position, result) = finished
                switch result {
                case .success(let entry):
                    store.insert(entry)
                    scored += 1
                    onEntry(entry)
                case .failure(let error):
                    failed.append(Failure(position: position, error: error))
                }
                launch()
            }
        }
        return (scored, failed, stopped)
    }
}

/// Plays a saved `MoodTrack` back during narration, with a live engine (the
/// Fast engine in the app) for every place the track does not cover: before
/// its first entry, past the part scored so far, or when the book's text no
/// longer matches the track.
public struct TrackedMoodEngine: MoodEngine {
    public let store: MoodTrackStore
    public let fallback: any MoodEngine
    /// An entry further back than this many sentences is too old to use.
    public let maxLagSentences: Int
    /// Settles the track's readings into scene-length moods (see
    /// `MoodSettling`); nil plays every reading as it is.
    public let settling: MoodSettling?
    private let settled = SettledMoods()

    public init(
        store: MoodTrackStore, fallback: any MoodEngine, maxLagSentences: Int = 60,
        settling: MoodSettling? = .standard
    ) {
        self.store = store
        self.fallback = fallback
        self.maxLagSentences = max(0, maxLagSentences)
        self.settling = settling
    }

    public var id: String { "track[\(store.engineID)]>\(fallback.id)" }

    public func reading(for window: CausalWindow) async throws -> MoodReading {
        if let reading = trackReading(for: window) { return reading }
        return try await fallback.reading(for: window)
    }

    /// The track's reading for this window, or nil when the track does not apply.
    public func trackReading(for window: CausalWindow) -> MoodReading? {
        let position = window.position
        let view = settled.view(of: store, settling: settling)
        guard let index = view.track.index(atOrBefore: position) else { return nil }
        let entry = view.track.entries[index]
        guard position.globalIndex - entry.globalIndex <= maxLagSentences else { return nil }
        // The entry's own sentence must be in this window, unchanged; otherwise
        // the track was made for a different alignment of the book.
        guard let line = window.lines.last(where: {
            $0.chapterOrdinal == entry.chapterOrdinal && $0.sentenceIndex == entry.sentenceIndex
        }), TextDigest.fnv1a64(line.text) == entry.sentenceDigest
        else { return nil }
        guard let moods = view.moods, moods[index] != entry.reading.bucket else { return entry.reading }
        // The scene's mood, at that mood's own place on the map and without
        // scores: the entry's point and scores describe its own mood, and a
        // reading that named one mood and pointed at another would pull the
        // director two ways.
        let mood = moods[index]
        return MoodReading(
            bucket: mood, valence: mood.anchor.valence, arousal: mood.anchor.arousal,
            confidence: entry.reading.confidence, engineID: entry.reading.engineID
        )
    }
}

/// A track's settled moods, worked out once per version of the track.
final class SettledMoods: @unchecked Sendable {
    struct View {
        let track: MoodTrack
        /// One mood per entry, or nil when settling is off.
        let moods: [MoodBucket]?
        let version: Int
    }

    private let lock = NSLock()
    private var current: View?

    func view(of store: MoodTrackStore, settling: MoodSettling?) -> View {
        lock.lock()
        defer { lock.unlock() }
        if let current, current.version == store.version { return current }
        let (track, version) = store.versioned
        let view = View(track: track, moods: settling?.moods(for: track.entries), version: version)
        current = view
        return view
    }
}
