#if canImport(CoreML)
import CoreML
import Foundation
import LofiScoreCore
import LofiText

/// The Fast engine with a fine-tuned small transformer (for example
/// all-MiniLM-L6-v2, `Tools/mac/finetune.sh`) in place of a softmax head on
/// fixed embeddings: Core ML runs it on the Neural Engine in milliseconds,
/// offline and plot-blind like the other Fast models.
///
/// It loads from the settings file (`LofiMood-lm-*.json`), which names the
/// compiled model next to it (`.mlmodelc`; an `.mlpackage` is compiled on
/// first load) and holds the word pieces for `WordPieceTokenizer`. The window
/// is read like the embedding engine reads it: the newest `chunkWords` words,
/// mixed with the reading of the words before them at `earlierWeight`.
public final class TransformerMoodEngine: MoodEngine, @unchecked Sendable {
    public let id: String
    public let config: TransformerMoodConfig
    private let tokenizer: WordPieceTokenizer
    private let model: MLModel
    private let moods: [MoodBucket?]
    private let lock = NSLock()

    public init(configURL: URL, version: String? = nil, computeUnits: MLComputeUnits = .all) throws {
        let config = try TransformerMoodConfig.load(from: configURL)
        guard config.kind == TransformerMoodConfig.kind else {
            throw MoodEngineError.unavailable("\(configURL.lastPathComponent) is not a transformer mood model")
        }
        let folder = configURL.deletingLastPathComponent()
        var modelURL = folder.appendingPathComponent(config.model)
        if !FileManager.default.fileExists(atPath: modelURL.path) {
            // Accept the uncompiled package too (compiling takes a few seconds).
            let package = modelURL.deletingPathExtension().appendingPathExtension("mlpackage")
            guard FileManager.default.fileExists(atPath: package.path) else {
                throw MoodEngineError.unavailable("no \(config.model) next to \(configURL.lastPathComponent)")
            }
            modelURL = try MLModel.compileModel(at: package)
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        self.model = try MLModel(contentsOf: modelURL, configuration: configuration)
        self.tokenizer = try config.tokenizer()
        self.config = config
        self.moods = config.moods.map { MoodBucket(lenient: $0) }
        self.id = "fast.lm/\(version ?? configURL.deletingPathExtension().lastPathComponent)"
    }

    public func reading(for window: CausalWindow) async throws -> MoodReading {
        guard window.wordCount > 0 else { throw MoodEngineError.emptyWindow }
        let recent = ClassifierInput.recentChunk(of: window.text, words: config.chunkWords)
        let earlier = ClassifierInput.earlierChunk(of: window.text, words: config.chunkWords)
        var p = try probabilities(recent)
        if config.earlierWeight > 0, ClassifierInput.wordCount(earlier) >= ClassifierInput.minimumEarlierWords {
            let older = try probabilities(earlier)
            p = zip(p, older).map { (1 - config.earlierWeight) * $0 + config.earlierWeight * $1 }
        }
        var scores: [MoodBucket: Double] = [:]
        for (mood, q) in zip(moods, p) {
            if let mood { scores[mood, default: 0] += q }
        }
        let total = scores.values.reduce(0, +)
        guard total > 0, let best = scores.max(by: { $0.value < $1.value }) else {
            throw MoodEngineError.generationFailed("transformer returned no scores")
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

    /// The model's mood probabilities for one chunk, in `config.moods` order.
    public func probabilities(_ text: String) throws -> [Double] {
        let length = config.maxTokens
        let (ids, mask) = tokenizer.encode(text, length: length)
        let shape: [NSNumber] = [1, NSNumber(value: length)]
        let idArray = try MLMultiArray(shape: shape, dataType: .int32)
        let maskArray = try MLMultiArray(shape: shape, dataType: .int32)
        for i in 0..<length {
            idArray[i] = NSNumber(value: ids[i])
            maskArray[i] = NSNumber(value: mask[i])
        }
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: idArray),
            "attention_mask": MLFeatureValue(multiArray: maskArray),
        ])
        lock.lock()
        defer { lock.unlock() }
        let output = try model.prediction(from: input)
        guard let probabilities = output.featureValue(for: "probabilities")?.multiArrayValue else {
            throw MoodEngineError.generationFailed("the model gave no probabilities")
        }
        return (0..<probabilities.count).map { probabilities[$0].doubleValue }
    }
}
#endif
