#if canImport(FoundationModels)
import Foundation
import FoundationModels
import LofiScoreCore
import LofiText

/// Apple's on-device language model (Apple Intelligence devices, iOS 26+).
///
/// Asks for one plain-text line (`bucket=...; valence=...; arousal=...;
/// confidence=...`) rather than a `@Generable` value, because the
/// `permissiveContentTransformations` guardrails only stop guardrail errors for
/// `String` responses, and the darkest passages are where mood matters most.
/// A refusal comes back as ordinary text, fails to parse, and throws, so wrap
/// this engine in `FallbackMoodEngine` with a fast engine behind it.
///
/// Each reading uses a fresh session, so readings never see earlier windows
/// and the transcript never grows.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
public struct FoundationModelsMoodEngine: MoodEngine {
    public enum Variant: String, Sendable, CaseIterable {
        /// The base model.
        case general
        /// Apple's content-tagging adapter, which is tuned for labelling text.
        case contentTagging
    }

    public let variant: Variant
    /// Most recent words of the window to send.
    public let maxWords: Int

    public init(variant: Variant = .general, maxWords: Int = 400) {
        self.variant = variant
        self.maxWords = maxWords
    }

    public var id: String { "fm.\(variant.rawValue)/p\(MoodPrompt.version)" }

    /// Whether the on-device model can be used right now, and if not, why.
    public static func availability() -> (isAvailable: Bool, reason: String) {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return (true, "available")
        case .unavailable(let reason):
            return (false, String(describing: reason))
        @unknown default:
            return (false, "unknown")
        }
    }

    public func reading(for window: CausalWindow) async throws -> MoodReading {
        guard window.wordCount > 0 else { throw MoodEngineError.emptyWindow }

        let model = SystemLanguageModel(
            useCase: variant == .general ? .general : .contentTagging,
            guardrails: .permissiveContentTransformations
        )
        guard model.isAvailable else {
            throw MoodEngineError.unavailable(String(describing: model.availability))
        }

        let session = LanguageModelSession(model: model, instructions: MoodPrompt.instructions)
        let prompt = MoodPrompt.prompt(for: window, maxWords: wordBudget(for: model))
        let options = GenerationOptions(sampling: .greedy, temperature: nil, maximumResponseTokens: 48)

        let answer: String
        do {
            answer = try await session.respond(to: prompt, options: options).content
        } catch {
            throw MoodEngineError.generationFailed(String(describing: error))
        }
        return try MoodLine.parse(answer, engineID: id)
    }

    /// Words of passage that fit comfortably in the model's context together
    /// with the instructions and the answer. Literary English runs about 1.3 to
    /// 1.5 tokens per word.
    private func wordBudget(for model: SystemLanguageModel) -> Int {
        #if compiler(>=6.3)
        // `contextSize` is in the iOS 26.4 / macOS 26.4 SDK and later (back-deployed).
        let context = model.contextSize
        #else
        let context = 4096
        #endif
        let reserved = 450 + 64  // instructions + answer
        let fit = Int(Double(max(0, context - reserved)) / 1.5)
        return max(60, min(maxWords, fit))
    }
}
#endif
