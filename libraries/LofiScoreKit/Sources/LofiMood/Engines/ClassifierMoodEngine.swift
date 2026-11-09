#if canImport(NaturalLanguage) && canImport(CoreML)
import CoreML
import Foundation
import LofiScoreCore
import LofiText
import NaturalLanguage

/// The Fast engine: a Create ML text classifier (trained by `lofi-train` on
/// Claude-labelled causal windows) loaded through Natural Language.
///
/// Deterministic, milliseconds per reading, works offline on every supported
/// iPhone, and knows nothing about any book's plot. A classifier trained with
/// the BERT feature extractor needs iOS 17 and Apple's contextual-embedding
/// assets on the device; call `prepareAssets()` once before first use.
///
/// The window is scored in two chunks: the most recent `chunkWords` words, and
/// the chunk before them at a lower weight, so the reading follows the newest
/// text without jumping on a single sentence.
public final class ClassifierMoodEngine: MoodEngine, @unchecked Sendable {
    public let id: String
    public let chunkWords: Int
    public let previousChunkWeight: Double

    private let model: NLModel
    private let lock = NSLock()

    /// - Parameters:
    ///   - modelURL: a compiled model (`.mlmodelc`) or a Create ML `.mlmodel`, which is compiled first.
    ///   - version: goes into the engine id and therefore into cache keys.
    public init(modelURL: URL, version: String = "1", chunkWords: Int = ClassifierInput.defaultChunkWords, previousChunkWeight: Double = 0.35) throws {
        var url = modelURL
        if url.pathExtension == "mlmodel" {
            url = try MLModel.compileModel(at: url)
        }
        self.model = try NLModel(contentsOf: url)
        self.id = "fast.coreml/\(version)"
        self.chunkWords = chunkWords
        self.previousChunkWeight = previousChunkWeight
    }

    public func reading(for window: CausalWindow) async throws -> MoodReading {
        guard window.wordCount > 0 else { throw MoodEngineError.emptyWindow }
        let recent = ClassifierInput.recentChunk(of: window.text, words: chunkWords)
        let earlier = ClassifierInput.earlierChunk(of: window.text, words: chunkWords)

        var scores = hypotheses(for: recent)
        if ClassifierInput.wordCount(earlier) >= ClassifierInput.minimumEarlierWords, previousChunkWeight > 0 {
            let older = hypotheses(for: earlier)
            for bucket in MoodBucket.allCases {
                scores[bucket] = (1 - previousChunkWeight) * (scores[bucket] ?? 0) + previousChunkWeight * (older[bucket] ?? 0)
            }
        }
        let total = scores.values.reduce(0, +)
        guard total > 0, let best = scores.max(by: { $0.value < $1.value }) else {
            throw MoodEngineError.generationFailed("classifier returned no labels")
        }
        let probabilities = scores.mapValues { $0 / total }
        let valence = probabilities.reduce(0) { $0 + $1.value * $1.key.anchor.valence }
        let arousal = probabilities.reduce(0) { $0 + $1.value * $1.key.anchor.arousal }
        return MoodReading(
            bucket: best.key,
            valence: valence,
            arousal: arousal,
            confidence: best.value / total,
            scores: probabilities,
            engineID: id
        )
    }

    private func hypotheses(for text: String) -> [MoodBucket: Double] {
        lock.lock()
        let raw = model.predictedLabelHypotheses(for: text, maximumCount: MoodBucket.allCases.count)
        lock.unlock()
        var out: [MoodBucket: Double] = [:]
        for (label, p) in raw {
            if let bucket = MoodBucket(lenient: label) { out[bucket, default: 0] += p }
        }
        return out
    }

    /// Downloads Apple's English contextual-embedding assets if they are missing.
    /// Returns true when they are on the device.
    @available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
    public static func prepareAssets() async -> Bool {
        guard let embedding = NLContextualEmbedding(language: .english) else { return false }
        if embedding.hasAvailableAssets { return true }
        do {
            return try await embedding.requestAssets() == .available
        } catch {
            return false
        }
    }
}
#endif
