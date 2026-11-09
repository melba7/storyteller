import Foundation
import LofiScoreCore
import LofiText
import Testing

@testable import LofiMood

/// A mood that changes at fixed sentences of the book. It only looks at the
/// window's own position, and echoes it, so tests can check both what was
/// probed and that every probe was judged from its own causal window.
final class StepEngine: MoodEngine, @unchecked Sendable {
    let steps: [(from: Int, bucket: MoodBucket)]
    private let lock = NSLock()
    private var probed: [Int] = []

    init(_ steps: [(from: Int, bucket: MoodBucket)]) {
        self.steps = steps.sorted { $0.from < $1.from }
    }

    var id: String { "step/1" }

    var calls: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return probed
    }

    func bucket(at globalIndex: Int) -> MoodBucket {
        steps.last { $0.from <= globalIndex }?.bucket ?? .calm
    }

    func reading(for window: CausalWindow) async throws -> MoodReading {
        let p = window.position
        // The window must end on its own sentence: nothing later is visible.
        guard window.lines.last.map({ ($0.chapterOrdinal, $0.sentenceIndex) == (p.chapterOrdinal, p.sentenceIndex) }) == true else {
            throw MoodEngineError.emptyWindow
        }
        record(p.globalIndex)
        let b = bucket(at: p.globalIndex)
        return MoodReading(bucket: b, valence: b.anchor.valence, arousal: b.anchor.arousal, confidence: 0.9, engineID: "echo@\(p.chapterOrdinal):\(p.sentenceIndex)")
    }

    private func record(_ g: Int) {
        lock.lock()
        probed.append(g)
        lock.unlock()
    }
}

/// Stands in for Apple's on-device model engine, which only exists on Apple platforms.
struct FakeOnDeviceEngine: MoodEngine {
    var id: String { "fm.general/p2" }
    func reading(for window: CausalWindow) async throws -> MoodReading {
        .neutral(engineID: id)
    }
}

@Suite("Mood change refinement")
struct RefinementTests {
    /// 3 chapters of 30 twelve-word sentences; with 120 words between entries
    /// the planned entries are sentences 2, 12 and 22 of each chapter
    /// (global 2, 12, 22, 32, 42, 52, 62, 72, 82).
    static func setup(refinement: MoodTrackBuilder.Refinement?) throws -> (SpoilerGuard, MoodTrackBuilder, MoodTrackStore) {
        let guardian = try SpoilerGuard(chapters: sampleBook(chapters: 3, sentences: 30))
        let builder = MoodTrackBuilder(spoilerGuard: guardian, plan: .init(wordsBetweenEntries: 120, refinement: refinement))
        let store = MoodTrackStore(MoodTrack(engineID: "step/1", bookID: "sample", wordsBetweenEntries: 120))
        return (guardian, builder, store)
    }

    @Test func plannedEntriesAreWhereTheTestsAssume() throws {
        let (_, builder, _) = try Self.setup(refinement: nil)
        #expect(try builder.scoringPositions().map(\.globalIndex) == [2, 12, 22, 32, 42, 52, 62, 72, 82])
    }

    @Test func pinsAChangeToWithinTheResolutionAndNeverBeforeIt() async throws {
        let (_, builder, store) = try Self.setup(refinement: .init(resolutionSentences: 3, probeBudget: 1))
        let engine = StepEngine([(0, .calm), (49, .tense)])
        let report = try await builder.build(into: store, engine: engine)

        let entries = store.snapshot.entries
        let firstTense = try #require(entries.firstIndex { $0.reading.bucket == .tense })
        #expect(firstTense > 0)
        let change = entries[firstTense]
        let before = entries[firstTense - 1]
        #expect(change.globalIndex >= 49, "an entry never names a mood before its text does")
        #expect(change.globalIndex - before.globalIndex <= 3)
        #expect(before.reading.bucket == .calm)
        // 42..52 -> 47 (calm) -> 49 (tense), then 47..49 is within 3 sentences.
        #expect(report.probes == 2)
        #expect(Set(engine.calls).isSuperset(of: [47, 49]))
        #expect(report.unrefinedChanges == 0)

        // Every entry, probes included, was judged from its own window.
        for entry in entries {
            let echoed = try #require(echoedPosition(entry.reading))
            #expect(echoed == (entry.chapterOrdinal, entry.sentenceIndex))
        }
    }

    @Test func theBudgetGoesToTheBiggestJumpFirstAndResumes() async throws {
        // calm -> cozy at 15 (a small jump), cozy -> tense at 69 (a big one).
        let steps: [(from: Int, bucket: MoodBucket)] = [(0, .calm), (15, .cozy), (69, .tense)]
        // 9 planned entries x 0.1 = one probe.
        let (_, tight, store) = try Self.setup(refinement: .init(resolutionSentences: 3, probeBudget: 0.1))
        let first = try await tight.build(into: store, engine: StepEngine(steps))
        #expect(first.probeBudget == 1 && first.probes == 1)
        #expect(store.snapshot.entries.contains { $0.globalIndex == 67 }, "the cozy -> tense change is probed first")
        #expect(!store.snapshot.entries.contains { (13...21).contains($0.globalIndex) })
        #expect(first.unrefinedChanges == 2)

        // Running again with the same budget makes no new readings.
        let again = StepEngine(steps)
        let second = try await tight.build(into: store, engine: again)
        #expect(second.probes == 0 && second.earlierProbes == 1 && again.calls.isEmpty)

        // A bigger budget picks up where the last run stopped.
        let (_, roomy, _) = try Self.setup(refinement: .init(resolutionSentences: 3, probeBudget: 1))
        let third = try await roomy.build(into: store, engine: StepEngine(steps))
        #expect(third.probes > 0 && third.unrefinedChanges == 0)
        let entries = store.snapshot.entries
        for (a, b) in zip(entries, entries.dropFirst()) where a.reading.bucket != b.reading.bucket {
            #expect(b.globalIndex - a.globalIndex <= 3, "\(a.globalIndex) -> \(b.globalIndex)")
        }
    }

    @Test func noRefinementMeansOnlyThePlannedEntries() async throws {
        let (_, builder, store) = try Self.setup(refinement: nil)
        let report = try await builder.build(into: store, engine: StepEngine([(0, .calm), (49, .tense)]))
        #expect(report.probes == 0 && store.count == report.planned)
    }

    @Test func trackerTagsTrackReadingsAndReadsEverySentence() async throws {
        let (guardian, builder, store) = try Self.setup(refinement: .init())
        _ = try await builder.build(into: store, engine: StepEngine([(0, .calm), (49, .tense)]))
        let engine = MoodEngineCatalog.playbackEngine(track: store)
        let clock = ManualClock()
        let tracker = MoodTracker(spoilerGuard: guardian, engine: engine, clock: { clock.read() })

        var observations: [MoodObservation] = []
        var p = try guardian.firstPosition()
        while let position = p {
            if let o = await tracker.sentenceStarted(position) { observations.append(o) }
            clock.advance(5)
            p = try guardian.position(after: position)
        }
        // Every sentence, except the first two of chapters 1 and 2 (the
        // chapter-start reading waits for the third sentence).
        #expect(observations.count == 90 - 4)
        #expect(observations.prefix(2).allSatisfy { $0.source == .live }, "before the first entry")
        #expect(observations.dropFirst(2).allSatisfy { $0.source == .track })
        let firstTense = try #require(observations.first { $0.reading.bucket == .tense })
        #expect((49...52).contains(firstTense.globalSentenceIndex))
    }

    @Test func catalogCadenceKeepsTheSlowEngineOnThePlanCadence() {
        #expect(MoodEngineCatalog.cadence(for: LexiconMoodEngine()) == .everySentence)
        #expect(MoodEngineCatalog.cadence(for: FakeOnDeviceEngine()) == .default)
        let store = MoodTrackStore(MoodTrack(engineID: "step/1", bookID: "b", wordsBetweenEntries: 250))
        let onDevice = FallbackMoodEngine(primary: FakeOnDeviceEngine(), fallback: LexiconMoodEngine())
        #expect(MoodEngineCatalog.cadence(for: TrackedMoodEngine(store: store, fallback: onDevice)) == .default)
        #expect(MoodEngineCatalog.cadence(for: MoodEngineCatalog.playbackEngine(track: store)) == .everySentence)
    }

    @Test func observationsWithoutASourceDecodeAsLive() throws {
        let old = #"{"reading":{"bucket":"calm","valence":0.2,"arousal":0.1,"confidence":0.5,"engineID":"x"},"chapterOrdinal":0,"sentenceIndex":3,"globalSentenceIndex":3,"trigger":"cadence"}"#
        let decoded = try JSONDecoder().decode(MoodObservation.self, from: Data(old.utf8))
        #expect(decoded.source == .live)
        var tracked = decoded
        tracked.source = .track
        let roundTrip = try JSONDecoder().decode(MoodObservation.self, from: try JSONEncoder().encode(tracked))
        #expect(roundTrip == tracked)
    }
}
