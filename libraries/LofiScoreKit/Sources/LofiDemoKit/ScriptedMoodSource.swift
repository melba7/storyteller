import Foundation
import LofiDirector
import LofiScoreCore

/// Stands in for the text side's mood engine in the demo.
///
/// It reads the story's hand-written labels over a window that ends at the sentence being
/// narrated (never later), and adds the kind of noise a real engine has: a wrong but nearby
/// bucket now and then, and some jitter in valence and arousal.
public struct ScriptedMoodSource: Sendable {
    /// How many sentences the window covers, ending at the current one.
    public var windowSentences: Int
    /// Chance that a reading names a neighbouring mood instead of the right one.
    public var noise: Double
    public var engineID = "demo.script/1"
    private var random: SplitMix64

    public init(windowSentences: Int = 5, noise: Double = 0.15, seed: UInt64 = 1) {
        self.windowSentences = max(1, windowSentences)
        self.noise = noise
        random = SplitMix64(seed: seed)
    }

    /// The reading for the text up to and including sentence `index`.
    public mutating func observation(at index: Int, trigger: ReadingTrigger, in story: DemoStory) -> MoodObservation {
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
}

extension DirectorConfig {
    /// Shorter timings so the five-minute demo story shows several changes. The real
    /// defaults (60 s smoothing, 90 s dwell) suit books that run for hours.
    public static var demo: DirectorConfig {
        var config = DirectorConfig()
        config.evidenceTimeConstant = 12
        config.minimumDwell = 20
        config.bigJumpMinimumDwell = 8
        config.seekReadingTimeout = 10
        return config
    }
}
