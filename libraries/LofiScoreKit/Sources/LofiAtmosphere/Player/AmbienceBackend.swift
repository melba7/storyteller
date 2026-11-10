import Foundation
import LofiAudio

/// How a slot's sound is shaped to stay out of the narrator's way.
public enum AmbienceFilter: String, Sendable, Hashable, Codable {
    /// The music's presence dip around 2.5 kHz and a soft high shelf.
    case standard
    /// For sounds made of voices (a crowd): the 1 to 4 kHz band, where words are made
    /// out, taken well down, and the top rolled off, so it reads as a murmur.
    case speechSafe

    public init(for sound: AmbientSound) {
        self = sound == .crowd ? .speechSafe : .standard
    }
}

public protocol AmbienceBackendDelegate: AnyObject {
    /// The engine stopped or must be rebuilt; restart it if the sounds should be playing.
    func ambienceBackend(_ backend: AmbienceBackend, needsRestart reason: BackendRestartReason)
    /// The output route changed. `previousOutputLost` is true when, say, headphones were unplugged.
    func ambienceBackend(_ backend: AmbienceBackend, routeDidChange route: OutputRoute, previousOutputLost: Bool)
}

/// The sound-making half of the atmosphere: a few slots, each looping one recording
/// gaplessly at a gain. ``AmbiencePlayer`` decides everything and calls these from its
/// scheduler; ``AVAmbienceBackend`` is the real one, ``FakeAmbienceBackend`` records calls.
public protocol AmbienceBackend: AnyObject {
    var delegate: AmbienceBackendDelegate? { get set }
    var isEngineRunning: Bool { get }
    var currentRoute: OutputRoute { get }
    /// How many recordings can play at once.
    var slotCount: Int { get }

    func startEngine() throws
    /// Stops the engine to save power. Slots stop too.
    func stopEngine()
    /// Throws away and rebuilds the audio graph (after a media services reset).
    func rebuild()

    /// Opens `url` on `slot`, replacing whatever was there. Returns its duration in seconds.
    func load(_ url: URL, slot: Int, filter: AmbienceFilter) throws -> TimeInterval
    /// Plays the slot's recording from `offset`, looping without a gap until stopped.
    func play(slot: Int, from offset: TimeInterval) throws
    func stop(slot: Int)
    func setGain(_ gain: Float, slot: Int)

    /// Plays a short recording once, at a gain, on a voice of its own beside the slots
    /// (a one-off sound). A one-off sound still playing is cut off.
    func playOnce(_ url: URL, gain: Float, filter: AmbienceFilter) throws
    /// Fades a one-off sound still playing out over `fade` seconds and stops it (the
    /// narrator paused, or the listener jumped). Nothing happens when none is playing.
    func stopOnce(fade: TimeInterval)
}

extension AmbienceBackend {
    /// Backends without a one-off voice play none.
    public func playOnce(_ url: URL, gain: Float, filter: AmbienceFilter) throws {
        throw LofiAudioError.loadFailed(trackID: url.lastPathComponent, reason: "this backend plays no one-off sounds")
    }

    public func stopOnce(fade: TimeInterval) {}
}

/// Records what the player asked for, for tests and the headless demo.
public final class FakeAmbienceBackend: AmbienceBackend {
    public weak var delegate: AmbienceBackendDelegate?
    public private(set) var isEngineRunning = false
    public var currentRoute: OutputRoute = .builtIn
    public let slotCount: Int
    public var failLoads: Set<String> = []
    public var duration: TimeInterval = 60

    public struct Slot: Equatable {
        public var url: URL?
        public var filter: AmbienceFilter = .standard
        public var playing = false
        public var gain: Float = 0
    }

    public private(set) var slots: [Slot]
    public private(set) var log: [String] = []
    /// One-off sounds played, with their gains, oldest first.
    public private(set) var oneShots: [(file: String, gain: Float)] = []

    public init(slotCount: Int = 8) {
        self.slotCount = slotCount
        slots = Array(repeating: Slot(), count: slotCount)
    }

    public func startEngine() throws {
        isEngineRunning = true
        log.append("start")
    }

    public func stopEngine() {
        isEngineRunning = false
        for index in slots.indices { slots[index].playing = false }
        log.append("stop")
    }

    public func rebuild() {
        isEngineRunning = false
        slots = Array(repeating: Slot(), count: slotCount)
        log.append("rebuild")
    }

    public func load(_ url: URL, slot: Int, filter: AmbienceFilter) throws -> TimeInterval {
        if failLoads.contains(url.lastPathComponent) {
            throw LofiAudioError.loadFailed(trackID: url.lastPathComponent, reason: "test")
        }
        slots[slot] = Slot(url: url, filter: filter, playing: false, gain: slots[slot].gain)
        log.append("load \(slot) \(url.lastPathComponent)")
        return duration
    }

    public func play(slot: Int, from offset: TimeInterval) throws {
        guard isEngineRunning else { throw LofiAudioError.engineNotRunning }
        slots[slot].playing = true
        log.append("play \(slot)")
    }

    public func stop(slot: Int) {
        slots[slot].playing = false
        log.append("stop \(slot)")
    }

    public func setGain(_ gain: Float, slot: Int) {
        slots[slot].gain = gain
    }

    public func playOnce(_ url: URL, gain: Float, filter: AmbienceFilter) throws {
        guard isEngineRunning else { throw LofiAudioError.engineNotRunning }
        if failLoads.contains(url.lastPathComponent) {
            throw LofiAudioError.loadFailed(trackID: url.lastPathComponent, reason: "test")
        }
        oneShots.append((url.lastPathComponent, gain))
        log.append("once \(url.lastPathComponent)")
        oneShotPlaying = url.lastPathComponent
    }

    /// The one-off sound playing, until it is stopped (the fake never finishes one by itself).
    public private(set) var oneShotPlaying: String?

    public func stopOnce(fade: TimeInterval) {
        guard oneShotPlaying != nil else { return }
        oneShotPlaying = nil
        log.append("stop once \(fade)")
    }

    /// The files playing now with their gains, by file name.
    public var audible: [String: Float] {
        var result: [String: Float] = [:]
        for slot in slots where slot.playing && slot.gain > 0.0001 {
            if let name = slot.url?.lastPathComponent { result[name] = slot.gain }
        }
        return result
    }

    public func simulateRestart(_ reason: BackendRestartReason) {
        isEngineRunning = false
        delegate?.ambienceBackend(self, needsRestart: reason)
    }

    public func simulateRoute(_ route: OutputRoute, previousOutputLost: Bool) {
        currentRoute = route
        delegate?.ambienceBackend(self, routeDidChange: route, previousOutputLost: previousOutputLost)
    }
}
