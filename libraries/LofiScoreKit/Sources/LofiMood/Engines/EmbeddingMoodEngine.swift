#if canImport(NaturalLanguage)
import Foundation
import LofiScoreCore
import LofiText
import NaturalLanguage

/// Which of Apple's on-device text embeddings feeds a `LinearMoodModel`.
public enum TextFeatureKind: String, CaseIterable, Sendable {
    /// `NLEmbedding.sentenceEmbedding`: one vector per sentence (iOS 14+).
    case sentence
    /// `NLEmbedding.wordEmbedding`: averaged word vectors (iOS 13+).
    case word
    /// `NLContextualEmbedding`: Apple's BERT-style model, mean-pooled (iOS 17+,
    /// needs its assets on the device).
    case contextual
}

/// Turns the newest words of a window into a fixed-length feature vector.
///
/// Every kind gives two halves: the mean over the whole chunk, and the mean
/// over its last part (the last two sentences, the last 40 words, or the last
/// 32 tokens), because the label describes the sentence being narrated now.
public final class TextFeaturizer: @unchecked Sendable {
    public let kind: TextFeatureKind
    /// Stored in the model, so a model is never fed the wrong features.
    public let id: String
    public let dimension: Int

    private let lock = NSLock()
    private let staticEmbedding: NLEmbedding?
    private let contextualEmbedding: AnyObject?
    private let maxContextualWords: Int

    public init(kind: TextFeatureKind) throws {
        self.kind = kind
        switch kind {
        case .sentence, .word:
            let embedding = kind == .sentence ? NLEmbedding.sentenceEmbedding(for: .english) : NLEmbedding.wordEmbedding(for: .english)
            guard let embedding else { throw MoodEngineError.unavailable("no English \(kind.rawValue) embedding on this device") }
            staticEmbedding = embedding
            contextualEmbedding = nil
            dimension = 2 * embedding.dimension
            maxContextualWords = 0
            id = "\(kind.rawValue).en/\(embedding.revision)"
        case .contextual:
            guard #available(iOS 17.0, macOS 14.0, visionOS 1.0, *) else {
                throw MoodEngineError.unavailable("NLContextualEmbedding needs iOS 17 or macOS 14")
            }
            guard let embedding = NLContextualEmbedding(language: .english) else {
                throw MoodEngineError.unavailable("no English contextual embedding")
            }
            guard embedding.hasAvailableAssets else {
                throw MoodEngineError.unavailable("the contextual embedding's assets are not downloaded (ClassifierMoodEngine.prepareAssets())")
            }
            try embedding.load()
            staticEmbedding = nil
            contextualEmbedding = embedding
            dimension = 2 * embedding.dimension
            // Keep the newest words within the model's sequence length (about
            // 1.5 tokens per word), so truncation never drops the end.
            maxContextualWords = max(32, Int(Double(embedding.maximumSequenceLength) / 1.6))
            id = "contextual.en/\(embedding.revision)"
        }
    }

    public func features(for text: String) throws -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        switch kind {
        case .sentence: return try sentenceFeatures(text)
        case .word: return try wordFeatures(text)
        case .contextual:
            guard #available(iOS 17.0, macOS 14.0, visionOS 1.0, *), let embedding = contextualEmbedding as? NLContextualEmbedding else {
                throw MoodEngineError.unavailable("contextual embedding not loaded")
            }
            return try contextualFeatures(text, embedding: embedding)
        }
    }

    private func sentenceFeatures(_ text: String) throws -> [Double] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        let sentences = tokenizer.tokens(for: text.startIndex..<text.endIndex).map { String(text[$0]) }
        let vectors = sentences.compactMap { staticEmbedding?.vector(for: $0) }
        guard !vectors.isEmpty else { throw MoodEngineError.emptyWindow }
        return Self.mean(vectors, dimension: dimension / 2) + Self.mean(Array(vectors.suffix(2)), dimension: dimension / 2)
    }

    private func wordFeatures(_ text: String) throws -> [Double] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        let words = tokenizer.tokens(for: text.startIndex..<text.endIndex).map { text[$0].lowercased() }
        let vectors = words.compactMap { staticEmbedding?.vector(for: $0) }
        guard !vectors.isEmpty else { throw MoodEngineError.emptyWindow }
        return Self.mean(vectors, dimension: dimension / 2) + Self.mean(Array(vectors.suffix(40)), dimension: dimension / 2)
    }

    @available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
    private func contextualFeatures(_ text: String, embedding: NLContextualEmbedding) throws -> [Double] {
        let words = text.split(whereSeparator: \.isWhitespace)
        let chunk = words.suffix(maxContextualWords).joined(separator: " ")
        let result = try embedding.embeddingResult(for: chunk, language: .english)
        var vectors: [[Double]] = []
        result.enumerateTokenVectors(in: chunk.startIndex..<chunk.endIndex) { vector, _ in
            vectors.append(vector)
            return true
        }
        guard !vectors.isEmpty else { throw MoodEngineError.emptyWindow }
        return Self.mean(vectors, dimension: dimension / 2) + Self.mean(Array(vectors.suffix(32)), dimension: dimension / 2)
    }

    static func mean(_ vectors: [[Double]], dimension: Int) -> [Double] {
        var out = [Double](repeating: 0, count: dimension)
        for v in vectors { for j in 0..<min(dimension, v.count) { out[j] += v[j] } }
        let n = Double(max(vectors.count, 1))
        return out.map { $0 / n }
    }
}

/// The Fast engine with Apple's on-device embeddings instead of a bag of
/// words: a `TextFeaturizer` feeding a `LinearMoodModel` trained by
/// `lofi-train embed`. Plot-blind and deterministic like the Create ML one.
public final class EmbeddingMoodEngine: MoodEngine, @unchecked Sendable {
    public let id: String
    public let chunkWords: Int
    public let previousChunkWeight: Double
    private let model: LinearMoodModel
    private let featurizer: TextFeaturizer

    public init(modelURL: URL, version: String = "1", chunkWords: Int = ClassifierInput.defaultChunkWords, previousChunkWeight: Double = 0.35) throws {
        let model = try LinearMoodModel.load(from: modelURL)
        guard let kindName = model.features.split(separator: ".").first, let kind = TextFeatureKind(rawValue: String(kindName)) else {
            throw MoodEngineError.unavailable("model features \(model.features) are not a known embedding")
        }
        let featurizer = try TextFeaturizer(kind: kind)
        guard featurizer.id == model.features, featurizer.dimension == model.dimension else {
            throw MoodEngineError.unavailable("model was trained on \(model.features), this device has \(featurizer.id)")
        }
        self.model = model
        self.featurizer = featurizer
        self.id = "fast.embed-\(kind.rawValue)/\(version)"
        self.chunkWords = chunkWords
        self.previousChunkWeight = previousChunkWeight
    }

    public func reading(for window: CausalWindow) async throws -> MoodReading {
        guard window.wordCount > 0 else { throw MoodEngineError.emptyWindow }
        let recent = ClassifierInput.recentChunk(of: window.text, words: chunkWords)
        let earlier = ClassifierInput.earlierChunk(of: window.text, words: chunkWords)
        var scores = model.scores(try featurizer.features(for: recent))
        if earlier.split(separator: " ").count >= 40, previousChunkWeight > 0, let older = try? model.scores(featurizer.features(for: earlier)) {
            for bucket in MoodBucket.allCases {
                scores[bucket] = (1 - previousChunkWeight) * (scores[bucket] ?? 0) + previousChunkWeight * (older[bucket] ?? 0)
            }
        }
        let total = scores.values.reduce(0, +)
        guard total > 0, let best = scores.max(by: { $0.value < $1.value }) else {
            throw MoodEngineError.generationFailed("embedding model returned no scores")
        }
        let probabilities = scores.mapValues { $0 / total }
        return MoodReading(
            bucket: best.key,
            valence: probabilities.reduce(0) { $0 + $1.value * $1.key.anchor.valence },
            arousal: probabilities.reduce(0) { $0 + $1.value * $1.key.anchor.arousal },
            confidence: best.value / total,
            scores: probabilities,
            engineID: id
        )
    }
}
#endif
