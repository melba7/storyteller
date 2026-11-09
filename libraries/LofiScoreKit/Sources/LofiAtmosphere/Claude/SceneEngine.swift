import Foundation
import LofiText

/// What a scene engine answers for one passage.
public struct SceneAnswer: Sendable, Hashable {
    public enum Place: Sendable, Hashable {
        /// A place from the memory, by id.
        case known(String)
        /// A place not met before, with its name.
        case new(String)
        /// No particular place (a chapter heading, a jump not described yet, pure reflection).
        case none
    }

    public var place: Place
    /// The scene, without a place id yet (the builder assigns ids).
    public var scene: StoryScene
    public var world: String?
    /// More specific sounds asked for in this answer, not offered before (no first index
    /// yet: the builder gives them this entry's).
    public var newVariants: [SoundVariant]
    /// A one-off sound the passage says happens (a knock, a clap of thunder), if any. The
    /// builder finds its sentence and keeps it only if the text up to that sentence alone
    /// says so.
    public var oneShot: OneShotMention?

    public init(place: Place, scene: StoryScene, world: String?, newVariants: [SoundVariant] = [], oneShot: OneShotMention? = nil) {
        self.place = place
        self.scene = scene
        self.world = world
        self.newVariants = newVariants
        self.oneShot = oneShot
    }
}

/// Judges the scene of one causal window, given the places met so far.
///
/// Engines see only `SpoilerGuard` windows and a ``PlaceMemory`` made from earlier
/// entries (and variants first asked for before the window), so no engine can see text
/// that has not been narrated.
public protocol SceneEngine: Sendable {
    /// Engine and prompt version, e.g. "claude.opus-5-5/a1". Saved in the track.
    var id: String { get }
    func scene(for window: CausalWindow, memory: PlaceMemory) async throws -> SceneAnswer
}

public enum SceneEngineError: Error, Sendable, Equatable, CustomStringConvertible {
    case emptyWindow
    case unavailable(String)
    case generationFailed(String)
    case unparseable(String)

    public var description: String {
        switch self {
        case .emptyWindow: "the passage is empty"
        case let .unavailable(reason): "unavailable: \(reason)"
        case let .generationFailed(reason): "failed: \(reason)"
        case let .unparseable(text): "could not read the answer: \(text.prefix(200))"
        }
    }
}
