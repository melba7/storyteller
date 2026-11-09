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
public struct MoodTrackBuilder: Sendable {
    public struct Plan: Sendable, Hashable {
        /// About 100 seconds of narration at 150 words a minute. The director
        /// changes music at most every few minutes, so this is plenty.
        public var wordsBetweenEntries: Int
        /// 1-based sentence of each chapter that always gets an entry; matches
        /// `ReadingCadence.Configuration.sentencesIntoNewChapter`.
        public var sentencesIntoNewChapter: Int

        public init(wordsBetweenEntries: Int = 250, sentencesIntoNewChapter: Int = 3) {
            self.wordsBetweenEntries = max(20, wordsBetweenEntries)
            self.sentencesIntoNewChapter = max(1, sentencesIntoNewChapter)
        }
    }

    public struct Report: Sendable, Hashable {
        public var planned = 0
        public var alreadyScored = 0
        public var scored = 0
        public var failed = 0
        public var failures: [String] = []
    }

    public let spoilerGuard: SpoilerGuard
    public let plan: Plan

    public init(spoilerGuard: SpoilerGuard, plan: Plan = Plan()) {
        self.spoilerGuard = spoilerGuard
        self.plan = plan
    }

    /// The positions a track for this book holds, in order.
    public func scoringPositions(chapters: ClosedRange<Int>? = nil) throws -> [SentencePosition] {
        var points: [SentencePosition] = []
        var wordsSince = 0
        var previous: SentencePosition?
        var current = try spoilerGuard.firstPosition()
        while let position = current {
            if let chapters, position.chapterOrdinal > chapters.upperBound { break }
            let sentence = try spoilerGuard.window(at: position).lines.last?.text ?? ""
            let words = TextNormalizer.wordCount(sentence)
            current = try spoilerGuard.position(after: position)
            if let chapters, !chapters.contains(position.chapterOrdinal) { continue }

            wordsSince += words
            let chapterChanged = previous.map { $0.chapterOrdinal != position.chapterOrdinal } ?? true
            if chapterChanged { wordsSince = words }
            previous = position

            let chapterStartPoint = position.sentenceIndex == plan.sentencesIntoNewChapter - 1
            // A chapter shorter than the chapter-start point still gets one entry.
            let lastOfShortChapter = position.sentenceIndex < plan.sentencesIntoNewChapter - 1
                && (current.map { $0.chapterOrdinal != position.chapterOrdinal } ?? true)
            if chapterStartPoint || lastOfShortChapter || (position.sentenceIndex >= plan.sentencesIntoNewChapter && wordsSince >= plan.wordsBetweenEntries) {
                points.append(position)
                wordsSince = 0
            }
        }
        return points
    }

    /// Scores every planned position the store does not have yet, `concurrency`
    /// at a time, adding each entry to the store as soon as it arrives.
    /// Failures are counted and skipped; run again to retry them.
    public func build(
        into store: MoodTrackStore,
        engine: any MoodEngine,
        chapters: ClosedRange<Int>? = nil,
        concurrency: Int = 4,
        onEntry: (@Sendable (MoodTrack.Entry, Int) -> Void)? = nil
    ) async throws -> Report {
        let positions = try scoringPositions(chapters: chapters)
        var report = Report()
        report.planned = positions.count
        let todo = positions.filter { !store.contains($0) }
        report.alreadyScored = positions.count - todo.count

        let width = max(1, concurrency)
        let spoilerGuard = self.spoilerGuard
        try await withThrowingTaskGroup(of: (SentencePosition, Result<MoodTrack.Entry, any Error>).self) { group in
            var next = 0
            func launch() {
                guard next < todo.count else { return }
                let position = todo[next]
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
                    report.scored += 1
                    onEntry?(entry, report.scored)
                case .failure(let error):
                    report.failed += 1
                    if report.failures.count < 20 { report.failures.append("\(position): \(error)") }
                }
                launch()
            }
        }
        return report
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

    public init(store: MoodTrackStore, fallback: any MoodEngine, maxLagSentences: Int = 60) {
        self.store = store
        self.fallback = fallback
        self.maxLagSentences = max(0, maxLagSentences)
    }

    public var id: String { "track[\(store.engineID)]>\(fallback.id)" }

    public func reading(for window: CausalWindow) async throws -> MoodReading {
        if let reading = trackReading(for: window) { return reading }
        return try await fallback.reading(for: window)
    }

    /// The track's reading for this window, or nil when the track does not apply.
    public func trackReading(for window: CausalWindow) -> MoodReading? {
        let position = window.position
        guard let entry = store.entry(atOrBefore: position),
              position.globalIndex - entry.globalIndex <= maxLagSentences
        else { return nil }
        // The entry's own sentence must be in this window, unchanged; otherwise
        // the track was made for a different alignment of the book.
        guard let line = window.lines.last(where: {
            $0.chapterOrdinal == entry.chapterOrdinal && $0.sentenceIndex == entry.sentenceIndex
        }), TextDigest.fnv1a64(line.text) == entry.sentenceDigest
        else { return nil }
        return entry.reading
    }
}
