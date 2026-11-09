import Foundation
import LofiScoreCore
import LofiText

/// Something that can judge the mood of narrated text.
///
/// Engines take only a `CausalWindow`, which only `SpoilerGuard` can create,
/// so an engine cannot see text that has not been narrated yet.
public protocol MoodEngine: Sendable {
    /// Stable identifier with a version, such as "lexicon/1" or "fm.general/1".
    /// It is part of every cache key, so bump the version when behaviour changes.
    var id: String { get }

    /// Judges the mood of the window. The last line is being narrated right now.
    func reading(for window: CausalWindow) async throws -> MoodReading
}

public enum MoodEngineError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The engine cannot run on this device (no Apple Intelligence, missing model).
    case unavailable(String)
    /// The window has no text.
    case emptyWindow
    /// The model answered, but not in the expected one-line format. Refusals land here.
    case unparseable(String)
    /// The model call itself failed (guardrails, context size, assets, rate limits).
    case generationFailed(String)

    public var description: String {
        switch self {
        case .unavailable(let why): "engine unavailable: \(why)"
        case .emptyWindow: "window is empty"
        case .unparseable(let text): "could not parse the model's answer: \(text.prefix(120))"
        case .generationFailed(let why): "generation failed: \(why)"
        }
    }
}

/// Uses `primary`, and `fallback` whenever `primary` throws.
///
/// The plan's on-device engine falls back to the Fast engine on a refusal or a
/// parse failure; this is that wiring. The reading keeps the engine id of
/// whichever engine produced it, so the debug overlay shows which one ran.
public struct FallbackMoodEngine: MoodEngine {
    public let primary: any MoodEngine
    public let fallback: any MoodEngine
    private let onFallback: (@Sendable (any Error) -> Void)?

    public init(
        primary: any MoodEngine,
        fallback: any MoodEngine,
        onFallback: (@Sendable (any Error) -> Void)? = nil
    ) {
        self.primary = primary
        self.fallback = fallback
        self.onFallback = onFallback
    }

    public var id: String { "\(primary.id)>\(fallback.id)" }

    public func reading(for window: CausalWindow) async throws -> MoodReading {
        do {
            return try await primary.reading(for: window)
        } catch {
            onFallback?(error)
            return try await fallback.reading(for: window)
        }
    }
}
