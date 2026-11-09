import Foundation
import LofiScoreCore
import LofiText

/// Counts of mood cues in a window, weighted toward the most recent words.
struct LexicalFeatures: Sendable, Equatable {
    /// Weighted cue hits per 100 weighted words, per bucket.
    var cueDensity: [MoodBucket: Double]
    /// -1 ... 1, from positive and negative word counts.
    var lexicalValence: Double
    /// 0 ... 1, from energetic words, exclamation marks and short sentences.
    var energy: Double
    /// Sum of recency weights over all words (a measure of how much text there was).
    var weightedWords: Double
}

enum LexicalAnalyzer {
    private static let buckets = MoodBucket.allCases
    private static let cueMatcher = CueMatcher(buckets.map { MoodLexicon.cues[$0] ?? [] })
    private static let toneMatcher = CueMatcher([MoodLexicon.positive, MoodLexicon.negative, MoodLexicon.energetic])

    /// Features at two scales: the last `recentWords` words (what the listener
    /// is hearing now) and the whole window with recency decay (the scene).
    /// The recent scale gets `recentShare` of the weight, so a sudden turn in
    /// the story shows up within a sentence or two.
    static func features(
        of text: String,
        recentWords: Int = 60,
        recentShare: Double = 0.7,
        halfLifeWords: Double = 120
    ) -> LexicalFeatures {
        let words = tokenize(text)
        let recent = scale(Array(words.suffix(recentWords)), halfLifeWords: .infinity)
        let scene = scale(words, halfLifeWords: halfLifeWords)

        var density: [MoodBucket: Double] = [:]
        for bucket in buckets {
            density[bucket] = recentShare * (recent.density[bucket] ?? 0) + (1 - recentShare) * (scene.density[bucket] ?? 0)
        }

        // Punctuation and rhythm over the recent sentences.
        let recentText = TextNormalizer.suffix(text, maxWords: max(recentWords, 1))
        let sentences = recentText.split(whereSeparator: { ".!?\u{2026}".contains($0) })
        let exclamations = Double(recentText.filter { $0 == "!" }.count)
        let sentenceCount = Double(max(1, sentences.count))
        let meanSentenceWords = Double(min(words.count, recentWords)) / sentenceCount
        let shortSentenceBoost = meanSentenceWords < 9 ? 0.15 : (meanSentenceWords < 14 ? 0.07 : 0)
        let energeticDensity = recentShare * recent.energetic + (1 - recentShare) * scene.energetic

        let energy = min(1, max(0,
            0.2 + 0.12 * energeticDensity + 0.25 * min(1, exclamations / sentenceCount * 2) + shortSentenceBoost
        ))
        let valence = recentShare * recent.valence + (1 - recentShare) * scene.valence
        return LexicalFeatures(cueDensity: density, lexicalValence: valence, energy: energy, weightedWords: scene.total)
    }

    private struct Scale {
        var density: [MoodBucket: Double] = [:]
        var valence = 0.0
        var energetic = 0.0  // per 100 weighted words
        var total = 0.0
    }

    /// Weighted cue densities over `words`. An infinite half-life weighs all words equally.
    private static func scale(_ words: [String], halfLifeWords: Double) -> Scale {
        let n = words.count
        var cue = [Double](repeating: 0, count: buckets.count)
        var positive = 0.0, negative = 0.0, energetic = 0.0, total = 0.0
        let decay = halfLifeWords.isFinite ? log(2) / max(1, halfLifeWords) : 0

        for (k, word) in words.enumerated() {
            let w = max(0.15, exp(-Double(n - 1 - k) * decay))
            total += w
            for category in cueMatcher.categories(of: word) { cue[category] += w }
            for category in toneMatcher.categories(of: word) {
                switch category {
                case 0: positive += w
                case 1: negative += w
                default: energetic += w
                }
            }
        }
        var result = Scale()
        let per100 = total > 0 ? 100 / total : 0
        for (i, bucket) in buckets.enumerated() { result.density[bucket] = cue[i] * per100 }
        result.valence = (positive - negative) / (positive + negative + 2)
        result.energetic = energetic * per100
        result.total = total
        return result
    }

    static func tokenize(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        for scalar in text.lowercased().unicodeScalars {
            if scalar.properties.isAlphabetic || scalar == "'" || scalar == "\u{2019}" {
                current.unicodeScalars.append(scalar == "\u{2019}" ? "'" : scalar)
            } else if !current.isEmpty {
                words.append(trimPossessive(current))
                current = ""
            }
        }
        if !current.isEmpty { words.append(trimPossessive(current)) }
        return words.filter { !$0.isEmpty }
    }

    private static func trimPossessive(_ word: String) -> String {
        var w = word
        if w.hasSuffix("'s") { w.removeLast(2) }
        return w.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
    }
}

/// Turns lexical features (plus, optionally, a better valence estimate from
/// elsewhere, such as NLTagger) into a reading.
enum MoodScoring {
    struct Weights: Sendable {
        var cue = 1.2
        var calmPrior = 1.0
        var valencePull = 1.5
        var lexicalValencePull = 0.8
        var energyPull = 1.2
        var temperature = 0.7
    }

    static func reading(
        from features: LexicalFeatures,
        externalValence: Double?,
        engineID: String,
        weights: Weights = Weights()
    ) -> MoodReading {
        let valenceEstimate = externalValence ?? features.lexicalValence
        let valencePull = externalValence == nil ? weights.lexicalValencePull : weights.valencePull

        var logits: [MoodBucket: Double] = [:]
        for bucket in MoodBucket.allCases {
            let anchor = bucket.anchor
            // log1p keeps one cue-dense stretch from swamping everything else.
            var logit = weights.cue * log1p(features.cueDensity[bucket] ?? 0)
            if bucket == .neutral { logit += weights.calmPrior }
            logit -= valencePull * pow(valenceEstimate - anchor.valence, 2)
            logit -= weights.energyPull * pow(features.energy - anchor.arousal, 2)
            logits[bucket] = logit
        }

        let maxLogit = logits.values.max() ?? 0
        var probabilities: [MoodBucket: Double] = [:]
        var sum = 0.0
        for (bucket, logit) in logits {
            let e = exp((logit - maxLogit) / weights.temperature)
            probabilities[bucket] = e
            sum += e
        }
        for bucket in MoodBucket.allCases { probabilities[bucket] = (probabilities[bucket] ?? 0) / sum }

        let best = MoodBucket.allCases.max { (probabilities[$0] ?? 0) < (probabilities[$1] ?? 0) } ?? .neutral
        let expectedArousal = MoodBucket.allCases.reduce(0) { $0 + (probabilities[$1] ?? 0) * $1.anchor.arousal }
        let expectedValence = MoodBucket.allCases.reduce(0) { $0 + (probabilities[$1] ?? 0) * $1.anchor.valence }

        // Little text means little evidence.
        let evidence = min(1, features.weightedWords / 40)
        return MoodReading(
            bucket: best,
            valence: 0.6 * valenceEstimate + 0.4 * expectedValence,
            arousal: 0.5 * features.energy + 0.5 * expectedArousal,
            confidence: min(0.9, (probabilities[best] ?? 0) * evidence),
            scores: probabilities,
            engineID: engineID
        )
    }
}

/// The floor every other engine must beat: hand-written cue words, recency
/// weighting and punctuation. Pure Swift, deterministic, runs anywhere.
public struct LexiconMoodEngine: MoodEngine {
    public init() {}

    public var id: String { "lexicon/1" }

    public func reading(for window: CausalWindow) async throws -> MoodReading {
        guard window.wordCount > 0 else { throw MoodEngineError.emptyWindow }
        let features = LexicalAnalyzer.features(of: window.text)
        return MoodScoring.reading(from: features, externalValence: nil, engineID: id)
    }
}
