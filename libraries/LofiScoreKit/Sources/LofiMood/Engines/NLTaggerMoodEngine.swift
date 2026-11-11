#if canImport(NaturalLanguage)
import Foundation
import LofiScoreCore
import LofiText
import NaturalLanguage

/// The NLTagger baseline: Apple's built-in sentiment score for valence, plus the
/// lexicon's cue words and rhythm for the bucket and arousal.
///
/// Runs on every iOS version the app supports, offline, in milliseconds. It has
/// no plot knowledge and no guardrails, and little nuance.
public struct NLTaggerMoodEngine: MoodEngine {
    /// A sentence this many sentences before the current one counts half as much.
    public let halfLifeSentences: Double

    public init(halfLifeSentences: Double = 6) {
        self.halfLifeSentences = halfLifeSentences
    }

    public var id: String { "nltagger/1" }

    public func reading(for window: CausalWindow) async throws -> MoodReading {
        guard window.wordCount > 0 else { throw MoodEngineError.emptyWindow }
        let valence = sentiment(of: window)
        let features = LexicalAnalyzer.features(of: window.text)
        return MoodScoring.reading(from: features, externalValence: valence, engineID: id)
    }

    /// Recency-weighted NLTagger sentiment over the window's sentences, -1 ... 1.
    /// Nil when the tagger scores nothing (unsupported language, empty text).
    func sentiment(of window: CausalWindow) -> Double? {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        let lines = window.lines
        var weighted = 0.0
        var total = 0.0
        for (k, line) in lines.enumerated() where !line.text.isEmpty {
            tagger.string = line.text
            let (tag, _) = tagger.tag(at: line.text.startIndex, unit: .paragraph, scheme: .sentimentScore)
            guard let raw = tag?.rawValue, let score = Double(raw) else { continue }
            let age = Double(lines.count - 1 - k)
            let w = max(0.15, pow(0.5, age / max(1, halfLifeSentences)))
            weighted += w * score
            total += w
        }
        return total > 0 ? weighted / total : nil
    }
}
#endif
