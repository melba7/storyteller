import Foundation
import LofiDirector

/// A silent backend for tests and for running the player without sound (Linux, previews).
///
/// It keeps time with the player's clock, so positions advance as a ``ManualScheduler``
/// advances, and it records every call. Decks do not end on their own: tests call
/// ``finish(_:)`` to say a track ran out.
public final class FakeAudioBackend: LofiAudioBackend, @unchecked Sendable {
    public enum Call: Hashable, Sendable {
        case startEngine
        case stopEngine
        case rebuild
        case load(file: String, deck: Deck)
        case play(Deck, from: TimeInterval)
        case stop(Deck)
    }

    public struct DeckState: Hashable, Sendable {
        public var file: String?
        public var duration: TimeInterval = 0
        public var isPlaying = false
        public var gain: Float = 0
        public var startedAt: TimeInterval = 0
        public var offset: TimeInterval = 0
    }

    public weak var delegate: LofiAudioBackendDelegate?
    public private(set) var isEngineRunning = false
    public var currentRoute: OutputRoute = .builtIn

    public private(set) var calls: [Call] = []
    public private(set) var decks: [DeckState] = [DeckState(), DeckState()]
    /// Every gain change, in order: time, deck, gain.
    public private(set) var gainLog: [(time: TimeInterval, deck: Deck, gain: Float)] = []

    /// Track lengths by file name (last path component). Unknown files last `defaultDuration`.
    public var durations: [String: TimeInterval] = [:]
    public var defaultDuration: TimeInterval = 120
    /// File names that fail to load.
    public var failingFiles: Set<String> = []
    /// While true, ``startEngine()`` throws (an ongoing phone call, say).
    public var engineStartFails = false

    private let clock: LofiClock

    public init(clock: LofiClock) {
        self.clock = clock
    }

    public func startEngine() throws {
        calls.append(.startEngine)
        if engineStartFails {
            throw LofiAudioError.engineNotRunning
        }
        isEngineRunning = true
    }

    public func stopEngine() {
        calls.append(.stopEngine)
        isEngineRunning = false
        for index in decks.indices {
            decks[index].isPlaying = false
        }
    }

    public func rebuild() {
        calls.append(.rebuild)
        isEngineRunning = false
        decks = [DeckState(), DeckState()]
    }

    public func load(_ url: URL, on deck: Deck) throws -> TimeInterval {
        let file = url.lastPathComponent
        calls.append(.load(file: file, deck: deck))
        decks[deck.rawValue].isPlaying = false
        if failingFiles.contains(file) {
            decks[deck.rawValue].file = nil
            throw LofiAudioError.loadFailed(trackID: file, reason: "test failure")
        }
        let duration = durations[file] ?? defaultDuration
        decks[deck.rawValue].file = file
        decks[deck.rawValue].duration = duration
        return duration
    }

    public func play(_ deck: Deck, from offset: TimeInterval) throws {
        calls.append(.play(deck, from: offset))
        guard isEngineRunning else { throw LofiAudioError.engineNotRunning }
        guard decks[deck.rawValue].file != nil else { throw LofiAudioError.nothingLoaded(deck) }
        decks[deck.rawValue].isPlaying = true
        decks[deck.rawValue].startedAt = clock.now
        decks[deck.rawValue].offset = offset
    }

    public func stop(_ deck: Deck) {
        calls.append(.stop(deck))
        decks[deck.rawValue].isPlaying = false
    }

    public func position(of deck: Deck) -> TimeInterval? {
        let state = decks[deck.rawValue]
        guard state.isPlaying else { return nil }
        return state.offset + (clock.now - state.startedAt)
    }

    public func setGain(_ gain: Float, for deck: Deck) {
        if decks[deck.rawValue].gain != gain {
            gainLog.append((clock.now, deck, gain))
        }
        decks[deck.rawValue].gain = gain
    }

    // MARK: - Test controls

    public func gain(of deck: Deck) -> Float {
        decks[deck.rawValue].gain
    }

    public func file(on deck: Deck) -> String? {
        decks[deck.rawValue].file
    }

    public func isPlaying(_ deck: Deck) -> Bool {
        decks[deck.rawValue].isPlaying
    }

    /// The deck's track ran out.
    public func finish(_ deck: Deck) {
        decks[deck.rawValue].isPlaying = false
        delegate?.audioBackend(self, deckDidFinish: deck)
    }

    /// The engine stopped itself (configuration change, interruption, reset).
    public func simulateRestartNeeded(_ reason: BackendRestartReason) {
        isEngineRunning = false
        for index in decks.indices {
            decks[index].isPlaying = false
        }
        if reason == .mediaServicesReset {
            decks = [DeckState(), DeckState()]
        }
        delegate?.audioBackend(self, needsRestart: reason)
    }

    public func simulateRouteChange(to route: OutputRoute, previousOutputLost: Bool) {
        currentRoute = route
        delegate?.audioBackend(self, routeDidChange: route, previousOutputLost: previousOutputLost)
    }

    public func clearLog() {
        calls.removeAll()
        gainLog.removeAll()
    }
}
