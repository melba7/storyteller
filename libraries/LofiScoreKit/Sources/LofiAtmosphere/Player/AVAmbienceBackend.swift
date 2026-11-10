#if canImport(AVFoundation)
import AVFoundation
import Foundation
import LofiAudioCore

/// The real atmosphere backend: its own `AVAudioEngine` with a few slots, each a player
/// node looping one recording gaplessly through an EQ that keeps it out of the voice's way.
///
/// It runs beside the music's engine, inside the narrator's audio session. What it never
/// does, by design (a test scans this file to keep it that way): change the audio session
/// (no category, mode, options or activation), touch Now Playing or the remote commands, or
/// touch the input node. It only reads the current route and listens for interruptions,
/// route changes and media services resets.
public final class AVAmbienceBackend: AmbienceBackend, @unchecked Sendable {
    public weak var delegate: AmbienceBackendDelegate?
    public let slotCount: Int
    /// Enough for a scene's ``StoryScene/maxLayers`` sounds and the old scene's fading out.
    public static let defaultSlotCount = 12

    private let notifications: NotificationCenter
    private var engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var filters: [AVAudioUnitEQ] = []
    private var mixer = AVAudioMixerNode()
    /// The one-off sounds' voice, on the mixer's bus after the slots.
    private var oncePlayer = AVAudioPlayerNode()
    private var onceFilter = AVAudioUnitEQ(numberOfBands: 3)
    private var onceFormat: AVAudioFormat?
    /// Bumped by every one-off sound, so an earlier fade-out never stops a later sound.
    private var onceGeneration = 0
    private var files: [AVAudioFile?]
    private var connectedFormats: [AVAudioFormat?]
    /// Bumped whenever a slot is stopped or replaced, so its loop stops rescheduling.
    /// Guarded by `lock`, which is never held across AVFoundation calls.
    private var generations: [Int]
    private let lock = NSLock()
    private var engineObserver: NSObjectProtocol?
    private var sessionObservers: [NSObjectProtocol] = []
    private var outputChanged = false

    /// Set for offline rendering (tools that write a mix to a file).
    private let offline: (format: AVAudioFormat, maximumFrameCount: AVAudioFrameCount)?
    private var offlineSetupError: Error?

    public init(slotCount: Int = AVAmbienceBackend.defaultSlotCount, notificationCenter: NotificationCenter = .default) {
        self.slotCount = slotCount
        notifications = notificationCenter
        offline = nil
        files = Array(repeating: nil, count: slotCount)
        connectedFormats = Array(repeating: nil, count: slotCount)
        generations = Array(repeating: 0, count: slotCount)
        buildGraph()
        observeSession()
    }

    /// A backend that renders on request instead of to the output. Nothing is played and
    /// the audio session is not observed. Pull audio with ``renderOffline(_:into:)``.
    public init(offlineFormat format: AVAudioFormat, maximumFrameCount: AVAudioFrameCount = 4096, slotCount: Int = AVAmbienceBackend.defaultSlotCount) throws {
        self.slotCount = slotCount
        notifications = NotificationCenter()
        offline = (format, maximumFrameCount)
        files = Array(repeating: nil, count: slotCount)
        connectedFormats = Array(repeating: nil, count: slotCount)
        generations = Array(repeating: 0, count: slotCount)
        buildGraph()
        if let offlineSetupError { throw offlineSetupError }
    }

    deinit {
        if let engineObserver { notifications.removeObserver(engineObserver) }
        for observer in sessionObservers { notifications.removeObserver(observer) }
        engine.stop()
    }

    @discardableResult
    public func renderOffline(_ frames: AVAudioFrameCount, into buffer: AVAudioPCMBuffer) throws -> Bool {
        guard offline != nil, engine.isRunning else {
            buffer.frameLength = min(frames, buffer.frameCapacity)
            if let channels = buffer.floatChannelData {
                for channel in 0..<Int(buffer.format.channelCount) {
                    channels[channel].update(repeating: 0, count: Int(buffer.frameLength))
                }
            }
            return false
        }
        let status = try engine.renderOffline(frames, to: buffer)
        guard status == .success else {
            throw AmbienceError.loadFailed(file: "offline render", reason: "render status \(status.rawValue)")
        }
        return true
    }

    // MARK: - AmbienceBackend

    public var isEngineRunning: Bool { engine.isRunning }

    public var currentRoute: OutputRoute {
        #if os(iOS) || os(tvOS) || os(visionOS)
        return Self.route(of: AVAudioSession.sharedInstance().currentRoute)
        #else
        return .builtIn
        #endif
    }

    public func startEngine() throws {
        guard !engine.isRunning else { return }
        let reconnect = withLock { () -> Bool in
            defer { outputChanged = false }
            return outputChanged
        }
        if reconnect { connectOutput() }
        engine.prepare()
        try engine.start()
    }

    public func stopEngine() {
        for slot in 0..<slotCount { stop(slot: slot) }
        oncePlayer.stop()
        engine.stop()
    }

    public func rebuild() {
        for slot in 0..<slotCount { bump(slot) }
        engine.stop()
        if let engineObserver {
            notifications.removeObserver(engineObserver)
            self.engineObserver = nil
        }
        engine = AVAudioEngine()
        files = Array(repeating: nil, count: slotCount)
        connectedFormats = Array(repeating: nil, count: slotCount)
        onceFormat = nil
        buildGraph()
    }

    public func load(_ url: URL, slot: Int, filter: AmbienceFilter) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: url)
        stop(slot: slot)
        let format = file.processingFormat
        if let connected = connectedFormats[slot],
           connected.sampleRate == format.sampleRate, connected.channelCount == format.channelCount {
            // Same shape as before: keep the connection.
        } else {
            engine.disconnectNodeOutput(players[slot])
            engine.connect(players[slot], to: filters[slot], format: format)
            connectedFormats[slot] = format
        }
        Self.configure(filters[slot], for: filter)
        files[slot] = file
        guard format.sampleRate > 0 else { return 0 }
        return Double(file.length) / format.sampleRate
    }

    public func play(slot: Int, from offset: TimeInterval) throws {
        guard engine.isRunning else { throw AmbienceError.engineNotRunning }
        guard let file = files[slot] else { throw AmbienceError.loadFailed(file: "slot \(slot)", reason: "nothing loaded") }
        let player = players[slot]
        let token = bump(slot)
        player.stop()
        let sampleRate = file.processingFormat.sampleRate
        var start = AVAudioFramePosition(max(0, offset) * sampleRate)
        if start >= file.length { start = 0 }
        let remaining = AVAudioFrameCount(clamping: file.length - start)
        if remaining > 0 {
            player.scheduleSegment(file, startingFrame: start, frameCount: remaining, at: nil)
        }
        // Queue the whole file behind it, and keep one more queued each time one is
        // used up: the player plays queued files back to back with no gap.
        scheduleLoop(slot, file: file, token: token)
        scheduleLoop(slot, file: file, token: token)
        player.play()
    }

    public func stop(slot: Int) {
        bump(slot)
        players[slot].stop()
    }

    public func setGain(_ gain: Float, slot: Int) {
        players[slot].volume = min(1, max(0, gain))
    }

    public func playOnce(_ url: URL, gain: Float, filter: AmbienceFilter) throws {
        guard engine.isRunning else { throw AmbienceError.engineNotRunning }
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        oncePlayer.stop()
        if let connected = onceFormat, connected.sampleRate == format.sampleRate, connected.channelCount == format.channelCount {
            // Same shape as before: keep the connection.
        } else {
            engine.disconnectNodeOutput(oncePlayer)
            engine.connect(oncePlayer, to: onceFilter, format: format)
            onceFormat = format
        }
        Self.configure(onceFilter, for: filter)
        withLock { onceGeneration += 1 }
        oncePlayer.volume = min(1, max(0, gain))
        oncePlayer.scheduleFile(file, at: nil, completionHandler: nil)
        oncePlayer.play()
    }

    public func stopOnce(fade: TimeInterval) {
        guard oncePlayer.isPlaying else { return }
        let token: Int = withLock {
            onceGeneration += 1
            return onceGeneration
        }
        let steps = max(1, Int((fade * 20).rounded(.up)))
        let start = oncePlayer.volume
        let interval = max(0.005, fade / Double(steps))
        func step(_ index: Int) {
            guard withLock({ onceGeneration == token }) else { return }
            if index >= steps {
                oncePlayer.stop()
                return
            }
            oncePlayer.volume = start * Float(steps - index) / Float(steps)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + interval) { [weak self] in
                guard self != nil else { return }
                step(index + 1)
            }
        }
        step(1)
    }

    // MARK: - Looping

    private func scheduleLoop(_ slot: Int, file: AVAudioFile, token: Int) {
        players[slot].scheduleFile(file, at: nil, completionCallbackType: .dataConsumed) { [weak self] _ in
            guard let self, self.withLock({ self.generations[slot] == token }) else { return }
            self.scheduleLoop(slot, file: file, token: token)
        }
    }

    @discardableResult
    private func bump(_ slot: Int) -> Int {
        withLock {
            generations[slot] += 1
            return generations[slot]
        }
    }

    // MARK: - Graph

    private func buildGraph() {
        if let offline {
            do {
                try engine.enableManualRenderingMode(.offline, format: offline.format, maximumFrameCount: offline.maximumFrameCount)
            } catch {
                offlineSetupError = error
            }
        }
        players = (0..<slotCount).map { _ in AVAudioPlayerNode() }
        filters = (0..<slotCount).map { _ in AVAudioUnitEQ(numberOfBands: 3) }
        mixer = AVAudioMixerNode()
        engine.attach(mixer)
        let standard = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)
        for slot in 0..<slotCount {
            engine.attach(players[slot])
            engine.attach(filters[slot])
            players[slot].volume = 0
            Self.configure(filters[slot], for: .standard)
            engine.connect(players[slot], to: filters[slot], format: standard)
            engine.connect(filters[slot], to: mixer, fromBus: 0, toBus: slot, format: standard)
            connectedFormats[slot] = standard
        }
        oncePlayer = AVAudioPlayerNode()
        onceFilter = AVAudioUnitEQ(numberOfBands: 3)
        engine.attach(oncePlayer)
        engine.attach(onceFilter)
        oncePlayer.volume = 0
        Self.configure(onceFilter, for: .standard)
        engine.connect(oncePlayer, to: onceFilter, format: standard)
        engine.connect(onceFilter, to: mixer, fromBus: 0, toBus: slotCount, format: standard)
        onceFormat = standard
        connectOutput()
        engineObserver = notifications.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.withLock {
                for slot in 0..<self.slotCount { self.generations[slot] += 1 }
                self.outputChanged = true
            }
            self.delegate?.ambienceBackend(self, needsRestart: .configurationChange)
        }
    }

    private func connectOutput() {
        let rate = offline != nil ? engine.manualRenderingFormat.sampleRate : engine.outputNode.outputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: rate > 0 ? rate : 44_100, channels: 2)
        engine.disconnectNodeOutput(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: format)
    }

    static func configure(_ eq: AVAudioUnitEQ, for filter: AmbienceFilter) {
        eq.globalGain = 0
        let presence = eq.bands[0]
        presence.filterType = .parametric
        presence.bypass = false
        let shelf = eq.bands[1]
        shelf.filterType = .highShelf
        shelf.bypass = false
        let lowPass = eq.bands[2]
        lowPass.filterType = .lowPass
        switch filter {
        case .standard:
            // The music's presence dip, a little deeper: ambience is mostly broadband noise.
            presence.frequency = 2500
            presence.bandwidth = 2
            presence.gain = -6
            shelf.frequency = 7000
            shelf.gain = -3
            lowPass.bypass = true
        case .speechSafe:
            // 1 to 4 kHz is where words are made out; take it well down and roll off the
            // top, so a crowd is a murmur, not voices.
            presence.frequency = 2000
            presence.bandwidth = 2
            presence.gain = -12
            shelf.frequency = 5000
            shelf.gain = -6
            lowPass.frequency = 6000
            lowPass.bypass = false
        }
    }

    private func observeSession() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        let session = AVAudioSession.sharedInstance()
        sessionObservers.append(notifications.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: nil
        ) { [weak self] notification in
            guard let self,
                  let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended
            else { return }
            self.withLock { for slot in 0..<self.slotCount { self.generations[slot] += 1 } }
            self.delegate?.ambienceBackend(self, needsRestart: .interruptionEnded)
        })
        sessionObservers.append(notifications.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            switch raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:)) {
            case .oldDeviceUnavailable?:
                self.delegate?.ambienceBackend(self, routeDidChange: self.currentRoute, previousOutputLost: true)
            case .newDeviceAvailable?, .override?, .routeConfigurationChange?, .wakeFromSleep?, .noSuitableRouteForCategory?:
                self.delegate?.ambienceBackend(self, routeDidChange: self.currentRoute, previousOutputLost: false)
            default:
                break
            }
        })
        sessionObservers.append(notifications.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.delegate?.ambienceBackend(self, needsRestart: .mediaServicesReset)
        })
        #endif
    }

    #if os(iOS) || os(tvOS) || os(visionOS)
    static func route(of description: AVAudioSessionRouteDescription) -> OutputRoute {
        guard let port = description.outputs.first?.portType else { return .other }
        switch port {
        case .builtInSpeaker, .builtInReceiver: return .builtIn
        case .headphones, .lineOut, .usbAudio, .HDMI: return .wired
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP: return .bluetooth
        case .airPlay: return .airPlay
        case .carAudio: return .carPlay
        default: return .other
        }
    }
    #endif

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
#endif
