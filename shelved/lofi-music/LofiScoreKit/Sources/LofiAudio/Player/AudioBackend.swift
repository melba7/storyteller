import Foundation

public enum LofiAudioError: Error, Equatable, CustomStringConvertible {
    case nothingLoaded(Deck)
    case engineNotRunning
    case emptyLibrary
    case loadFailed(trackID: String, reason: String)

    public var description: String {
        switch self {
        case let .nothingLoaded(deck): return "Nothing is loaded on deck \(deck)"
        case .engineNotRunning: return "The audio engine is not running"
        case .emptyLibrary: return "The music library has no playable tracks"
        case let .loadFailed(id, reason): return "Could not load \(id): \(reason)"
        }
    }
}

/// Callbacks from the audio backend. They may arrive on any thread.
public protocol LofiAudioBackendDelegate: AnyObject {
    /// `deck` played to the end of its track on its own (not stopped by the player).
    func audioBackend(_ backend: LofiAudioBackend, deckDidFinish deck: Deck)
    /// The engine stopped or must be rebuilt; restart it if the music should be playing.
    func audioBackend(_ backend: LofiAudioBackend, needsRestart reason: BackendRestartReason)
    /// The output route changed. `previousOutputLost` is true when, say, headphones were unplugged.
    func audioBackend(_ backend: LofiAudioBackend, routeDidChange route: OutputRoute, previousOutputLost: Bool)
}

/// The sound-making half of the player: two decks that load, play, stop and take a gain.
///
/// ``LofiScorePlayer`` decides everything and calls these from its scheduler's context;
/// a backend never decides on its own. ``AVAudioEngineBackend`` is the real one;
/// ``FakeAudioBackend`` records calls for tests.
public protocol LofiAudioBackend: AnyObject {
    var delegate: LofiAudioBackendDelegate? { get set }
    var isEngineRunning: Bool { get }
    var currentRoute: OutputRoute { get }

    func startEngine() throws
    /// Stops the engine to save power. Decks stop too.
    func stopEngine()
    /// Throws away and rebuilds the audio graph (after a media services reset).
    func rebuild()

    /// Opens `url` on `deck`, replacing (and stopping) whatever was there.
    /// Returns the track's duration in seconds.
    func load(_ url: URL, on deck: Deck) throws -> TimeInterval
    /// Plays `deck` from `offset` seconds into its track. The engine must be running.
    func play(_ deck: Deck, from offset: TimeInterval) throws
    func stop(_ deck: Deck)
    /// Seconds into the track that `deck` is playing, if it is playing.
    func position(of deck: Deck) -> TimeInterval?
    func setGain(_ gain: Float, for deck: Deck)
}
