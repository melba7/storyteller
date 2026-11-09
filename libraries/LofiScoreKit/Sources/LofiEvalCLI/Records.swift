import Foundation
import LofiScoreCore
import LofiText

/// One causal window, as the eval and the labelling tools exchange it.
///
/// `chapters` holds the window's sentences grouped by chapter, oldest first,
/// exactly as `SpoilerGuard` produced them; `run` rebuilds the very same window
/// from them, so a labelled or name-masked record is scored on the text the
/// engines would see in the app.
struct WindowRecord: Codable, Sendable {
    var id: String
    var book: String
    var chapter: Int
    var sentence: Int
    var global: Int
    /// Position through the book, 0...1 (by sentence). Used to find early chapters for the drift eval.
    var bookFraction: Double
    /// "sample", or the reading trigger when the window came from a playback simulation.
    var trigger: String
    /// Simulated playback time in seconds from the start of the book.
    var seconds: Double?
    var words: Int
    var truncated: Bool
    var chapters: [[String]]
    var text: String

    init(book: String, window: CausalWindow, total: Int, trigger: String, seconds: Double?) {
        let p = window.position
        self.id = "\(book):\(p.chapterOrdinal):\(p.sentenceIndex)"
        self.book = book
        self.chapter = p.chapterOrdinal
        self.sentence = p.sentenceIndex
        self.global = p.globalIndex
        self.bookFraction = total > 1 ? Double(p.globalIndex) / Double(total - 1) : 0
        self.trigger = trigger
        self.seconds = seconds.map { ($0 * 10).rounded() / 10 }
        self.words = window.wordCount
        self.truncated = window.isTruncated
        var groups: [[String]] = []
        var lastChapter: Int?
        for line in window.lines {
            if line.chapterOrdinal != lastChapter {
                groups.append([])
                lastChapter = line.chapterOrdinal
            }
            groups[groups.count - 1].append(line.text)
        }
        self.chapters = groups
        self.text = window.text
    }
}

/// One engine reading of one window.
struct ReadingRecord: Codable, Sendable {
    var id: String
    var engine: String
    var bucket: String?
    var valence: Double?
    var arousal: Double?
    var confidence: Double?
    var scores: [String: Double]?
    var latencyMs: Double
    var error: String?

    init(id: String, engine: String, reading: MoodReading, latencyMs: Double) {
        self.id = id
        self.engine = reading.engineID.isEmpty ? engine : reading.engineID
        self.bucket = reading.bucket.rawValue
        self.valence = round3(reading.valence)
        self.arousal = round3(reading.arousal)
        self.confidence = round3(reading.confidence)
        self.scores = reading.scores.map { s in
            Dictionary(uniqueKeysWithValues: s.map { ($0.key.rawValue, round3($0.value)) })
        }
        self.latencyMs = (latencyMs * 10).rounded() / 10
    }

    init(id: String, engine: String, error: Error, latencyMs: Double) {
        self.id = id
        self.engine = engine
        self.latencyMs = (latencyMs * 10).rounded() / 10
        self.error = "\(error)"
    }
}

/// One observation from a playback simulation through `MoodTracker`.
struct ObservationRecord: Codable, Sendable {
    var book: String
    var chapter: Int
    var sentence: Int
    var global: Int
    var seconds: Double
    var trigger: String
    var bucket: String
    var valence: Double
    var arousal: Double
    var confidence: Double
    var engine: String
    var latencyMs: Double?
}

func round3(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }
