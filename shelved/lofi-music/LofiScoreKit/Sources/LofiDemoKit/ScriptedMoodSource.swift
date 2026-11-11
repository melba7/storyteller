import Foundation
import LofiDirector
import LofiScoreCore

/// Stands in for the text side's mood engine in the demo.
///
/// In ``Mode/live`` it reads the story's hand-written labels over a window that ends at the
/// sentence being narrated (never later), and adds the kind of noise a real engine has: a
/// wrong but nearby bucket now and then, and some jitter in valence and arousal.
///
/// In ``Mode/track`` it plays the part of a book's mood track, scored ahead of time: each
/// turn of mood is marked at the sentence where it happens (or ``trackLag`` sentences
/// later), and the reading for a sentence is the mark at or before it.
public struct ScriptedMoodSource: Sendable {
    public enum Mode: String, Sendable, Hashable, CaseIterable {
        /// A live engine reading the last few sentences.
        case live
        /// A book's mood track.
        case track
    }

    public var mode: Mode
    /// How many sentences the window covers, ending at the current one.
    public var windowSentences: Int
    /// Chance that a reading names a neighbouring mood instead of the right one.
    public var noise: Double
    /// For ``Mode/track``: how many sentences after the real turn the track marks it.
    public var trackLag: Int
    /// For ``Mode/track``: how sure the track's readings are.
    public var trackConfidence = 0.8
    public var engineID = "demo.script/1"
    private var random: SplitMix64

    public init(mode: Mode = .live, windowSentences: Int = 5, noise: Double = 0.15, trackLag: Int = 0, seed: UInt64 = 1) {
        self.mode = mode
        self.windowSentences = max(1, windowSentences)
        self.noise = noise
        self.trackLag = max(0, trackLag)
        random = SplitMix64(seed: seed)
    }

    /// Sentences between regular readings: every sentence with a mood track (lookups are
    /// instant), every other sentence with a live engine.
    public var readingCadence: Int {
        mode == .track ? 1 : 2
    }

    /// The reading for the text up to and including sentence `index`.
    public mutating func observation(at index: Int, trigger: ReadingTrigger, in story: DemoStory) -> MoodObservation {
        if mode == .track {
            return trackObservation(at: index, trigger: trigger, in: story)
        }
        let sentence = story.sentences[index]
        var lower = max(0, index - windowSentences + 1)
        if trigger == .chapterStart {
            // A chapter-start reading only looks at the new chapter.
            lower = max(lower, story.chapters[sentence.chapter].firstIndex)
        }
        let window = story.sentences[lower...index]

        // Later sentences in the window count a little more.
        var weights: [MoodBucket: Double] = [:]
        var valence = 0.0
        var arousal = 0.0
        var total = 0.0
        for (offset, line) in window.enumerated() {
            let weight = 0.6 + 0.4 * Double(offset + 1) / Double(window.count)
            weights[line.mood, default: 0] += weight
            valence += line.mood.anchor.valence * weight
            arousal += line.mood.anchor.arousal * weight
            total += weight
        }
        let top = MoodBucket.allCases.max { (weights[$0] ?? 0) < (weights[$1] ?? 0) } ?? .neutral
        var bucket = top
        var confidence = 0.35 + 0.55 * (weights[top] ?? 0) / total
        var point = MoodPoint(valence: valence / total, arousal: arousal / total)

        if random.nextUnit() < noise {
            let neighbours = MoodBucket.allCases
                .filter { $0 != top }
                .sorted { $0.anchor.distance(to: top.anchor) < $1.anchor.distance(to: top.anchor) }
            bucket = neighbours[random.nextUnit() < 0.6 ? 0 : 1]
            confidence = 0.35 + 0.25 * random.nextUnit()
            point = MoodPoint(
                valence: (point.valence + bucket.anchor.valence) / 2,
                arousal: (point.arousal + bucket.anchor.arousal) / 2
            )
        }
        let reading = MoodReading(
            bucket: bucket,
            valence: point.valence + random.nextGaussian(deviation: 0.05),
            arousal: point.arousal + random.nextGaussian(deviation: 0.05),
            confidence: confidence,
            engineID: engineID
        )
        return MoodObservation(
            reading: reading,
            chapterOrdinal: sentence.chapter,
            sentenceIndex: sentence.indexInChapter,
            globalSentenceIndex: index,
            trigger: trigger
        )
    }

    /// The track's mark at or before sentence `index`: the mood of the sentence `trackLag`
    /// sentences back (never one ahead), within the same chapter.
    private func trackObservation(at index: Int, trigger: ReadingTrigger, in story: DemoStory) -> MoodObservation {
        let sentence = story.sentences[index]
        let chapterStart = story.chapters[sentence.chapter].firstIndex
        let marked = story.sentences[max(chapterStart, index - trackLag)].mood
        let reading = MoodReading(
            bucket: marked,
            valence: marked.anchor.valence,
            arousal: marked.anchor.arousal,
            confidence: trackConfidence,
            engineID: "demo.track/1"
        )
        return MoodObservation(
            reading: reading,
            chapterOrdinal: sentence.chapter,
            sentenceIndex: sentence.indexInChapter,
            globalSentenceIndex: index,
            trigger: trigger,
            source: .track
        )
    }
}

extension DirectorConfig {
    /// Shorter timings so the six-minute demo story shows several changes. The real
    /// defaults (60 s smoothing, 20 s to confirm, 60 s dwell, 45 s between track turns)
    /// suit books that run for hours.
    public static var demo: DirectorConfig {
        var config = DirectorConfig()
        config.evidenceTimeConstant = 12
        config.confirmationTime = 4
        config.minimumDwell = 20
        config.trackMinimumDwell = 15
        config.bigJumpMinimumDwell = 8
        config.seekReadingTimeout = 10
        return config
    }
}
