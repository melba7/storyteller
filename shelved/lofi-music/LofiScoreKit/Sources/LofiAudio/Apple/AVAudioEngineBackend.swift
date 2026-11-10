#if canImport(AVFoundation)
import AVFoundation
import Foundation

/// A gentle cut where speech is clearest, so the music sits behind the narrator's consonants
/// instead of on top of them.
public struct PresenceEQ: Sendable, Hashable {
    public var enabled = true
    /// Centre of the dip, in Hz: the middle of the band that carries speech consonants.
    public var frequency: Float = 2500
    /// Deep enough that the music steps back from the voice without sounding filtered.
    public var gainDB: Float = -4.5
    /// Width of the dip, in octaves (2 octaves covers roughly 1.25 to 5 kHz).
    public var bandwidth: Float = 2
    /// A soft high shelf above the presence band.
    public var shelfFrequency: Float = 7000
    public var shelfGainDB: Float = -3

    public init() {}
}

/// The real backend: two `AVAudioPlayerNode` decks → a music mixer → a presence EQ → the
/// engine's main mixer.
///
/// What it never does, by design (and a test scans this file to keep it that way):
/// - change the audio session: no category, mode, options or activation calls. The narrator
///   owns the session; the engine plays inside it. Start the engine only while the narrator
///   is playing, which ``LofiScorePlayer`` does.
/// - touch Now Playing or the remote commands.
/// - touch the engine's input node (that would ask for the microphone).
///
/// It only reads the session's current route and listens to its notifications, so the
/// player can react to interruptions, route changes and media services resets.
public final class AVAudioEngineBackend: LofiAudioBackend, @unchecked Sendable {
    public weak var delegate: LofiAudioBackendDelegate?

    private let eqSettings: PresenceEQ
    private let notifications: NotificationCenter

    private var engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var musicMixer = AVAudioMixerNode()
    private var eq = AVAudioUnitEQ(numberOfBands: 2)
    private var files: [AVAudioFile?] = [nil, nil]
    private var connectedFormats: [AVAudioFormat?] = [nil, nil]
    /// The file frame each deck's current segment started at.
    private var segmentStarts: [AVAudioFramePosition] = [0, 0]

    /// Bumped whenever a deck is stopped or replaced, so completion callbacks from earlier
    /// segments are ignored. Guarded by `lock`, which is never held across AVFoundation calls.
    private var generations = [0, 0]
    private var outputChanged = false
    private let lock = NSLock()

    private var engineObserver: NSObjectProtocol?
    private var sessionObservers: [NSObjectProtocol] = []

    /// Set for offline rendering: the engine renders on request instead of to the output.
    private let offline: (format: AVAudioFormat, maximumFrameCount: AVAudioFrameCount)?
    private var offlineSetupError: Error?

    public init(eq: PresenceEQ = PresenceEQ(), notificationCenter: NotificationCenter = .default) {
        eqSettings = eq
        notifications = notificationCenter
        offline = nil
        buildGraph()
        observeSession()
    }

    /// A backend that renders offline, as fast as it can, for tools that write the music to
    /// a file (`lofi-render`). Nothing is played and the audio session is not observed.
    /// Call ``renderOffline(_:into:)`` to pull audio; the player drives it as usual.
    public init(offlineFormat format: AVAudioFormat, maximumFrameCount: AVAudioFrameCount = 4096, eq: PresenceEQ = PresenceEQ()) throws {
        eqSettings = eq
        // A private centre: an offline engine has no hardware or session to hear about.
        notifications = NotificationCenter()
        offline = (format, maximumFrameCount)
        buildGraph()
        if let offlineSetupError {
            throw offlineSetupError
        }
    }

    /// The format ``renderOffline(_:into:)`` produces.
    public var offlineFormat: AVAudioFormat? {
        offline == nil ? nil : engine.manualRenderingFormat
    }

    /// Renders the next `frames` frames into `buffer` (offline backends only). Returns
    /// false and leaves the buffer silent while the engine is stopped.
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
            throw LofiAudioError.loadFailed(trackID: "offline render", reason: "render status \(status.rawValue)")
        }
        return true
    }

    deinit {
        if let engineObserver {
            notifications.removeObserver(engineObserver)
        }
        for observer in sessionObservers {
            notifications.removeObserver(observer)
        }
        engine.stop()
    }

    // MARK: - LofiAudioBackend

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
            let changed = outputChanged
            outputChanged = false
            return changed
        }
        if reconnect {
            connectMusicChain()
        }
        engine.prepare()
        try engine.start()
    }

    public func stopEngine() {
        for deck in Deck.allCases {
            stop(deck)
        }
        engine.stop()
    }

    public func rebuild() {
        for deck in Deck.allCases {
            bumpGeneration(deck)
        }
        engine.stop()
        if let engineObserver {
            notifications.removeObserver(engineObserver)
            self.engineObserver = nil
        }
        engine = AVAudioEngine()
        files = [nil, nil]
        connectedFormats = [nil, nil]
        segmentStarts = [0, 0]
        buildGraph()
    }

    public func load(_ url: URL, on deck: Deck) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: url)
        let index = deck.rawValue
        stop(deck)
        let format = file.processingFormat
        if let connected = connectedFormats[index],
           connected.sampleRate == format.sampleRate, connected.channelCount == format.channelCount {
            // Same shape as before: keep the connection.
        } else {
            let player = players[index]
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: musicMixer, fromBus: 0, toBus: index, format: format)
            connectedFormats[index] = format
        }
        files[index] = file
        segmentStarts[index] = 0
        guard format.sampleRate > 0 else { return 0 }
        return Double(file.length) / format.sampleRate
    }

    public func play(_ deck: Deck, from offset: TimeInterval) throws {
        let index = deck.rawValue
        guard engine.isRunning else { throw LofiAudioError.engineNotRunning }
        guard let file = files[index] else { throw LofiAudioError.nothingLoaded(deck) }
        let player = players[index]
        let token = bumpGeneration(deck)
        player.stop()

        let sampleRate = file.processingFormat.sampleRate
        var startFrame = AVAudioFramePosition(max(0, offset) * sampleRate)
        if startFrame >= file.length {
            startFrame = 0
        }
        let frameCount = AVAudioFrameCount(clamping: file.length - startFrame)
        guard frameCount > 0 else { throw LofiAudioError.nothingLoaded(deck) }
        segmentStarts[index] = startFrame
        player.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: frameCount,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            self?.segmentFinished(deck, token: token)
        }
        player.play()
    }

    public func stop(_ deck: Deck) {
        bumpGeneration(deck)
        players[deck.rawValue].stop()
    }

    public func position(of deck: Deck) -> TimeInterval? {
        let index = deck.rawValue
        let player = players[index]
        guard engine.isRunning, player.isPlaying, let file = files[index],
              let nodeTime = player.lastRenderTime, nodeTime.isSampleTimeValid,
              let playerTime = player.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0
        else { return nil }
        let frames = segmentStarts[index] + max(0, playerTime.sampleTime)
        return min(Double(frames), Double(file.length)) / playerTime.sampleRate
    }

    public func setGain(_ gain: Float, for deck: Deck) {
        players[deck.rawValue].volume = min(1, max(0, gain))
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
        players = [AVAudioPlayerNode(), AVAudioPlayerNode()]
        musicMixer = AVAudioMixerNode()
        eq = AVAudioUnitEQ(numberOfBands: 2)
        configureEQ()
        for player in players {
            engine.attach(player)
            player.volume = 0
        }
        engine.attach(musicMixer)
        engine.attach(eq)
        let standard = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)
        for (index, player) in players.enumerated() {
            engine.connect(player, to: musicMixer, fromBus: 0, toBus: index, format: standard)
            connectedFormats[index] = standard
        }
        connectMusicChain()

        engineObserver = notifications.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.engineConfigurationChanged()
        }
    }

    /// Music mixer → EQ → main mixer, at the output's sample rate.
    private func connectMusicChain() {
        let outputRate = offline != nil ? engine.manualRenderingFormat.sampleRate : engine.outputNode.outputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: outputRate > 0 ? outputRate : 44_100, channels: 2)
        engine.disconnectNodeOutput(musicMixer)
        engine.disconnectNodeOutput(eq)
        engine.connect(musicMixer, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
    }

    private func configureEQ() {
        eq.globalGain = 0
        eq.bypass = !eqSettings.enabled
        let presence = eq.bands[0]
        presence.filterType = .parametric
        presence.frequency = eqSettings.frequency
        presence.bandwidth = eqSettings.bandwidth
        presence.gain = eqSettings.gainDB
        presence.bypass = false
        let shelf = eq.bands[1]
        shelf.filterType = .highShelf
        shelf.frequency = eqSettings.shelfFrequency
        shelf.gain = eqSettings.shelfGainDB
        shelf.bypass = false
    }

    // MARK: - Callbacks

    @discardableResult
    private func bumpGeneration(_ deck: Deck) -> Int {
        withLock {
            generations[deck.rawValue] += 1
            return generations[deck.rawValue]
        }
    }

    private func segmentFinished(_ deck: Deck, token: Int) {
        let current = withLock { generations[deck.rawValue] == token }
        // Completion handlers also fire when a deck is stopped or the engine stops; only a
        // segment that really played to its end counts.
        guard current, engine.isRunning, players[deck.rawValue].isPlaying else { return }
        delegate?.audioBackend(self, deckDidFinish: deck)
    }

    private func engineConfigurationChanged() {
        // The engine has stopped itself because the output hardware changed.
        withLock {
            generations[0] += 1
            generations[1] += 1
            outputChanged = true
        }
        delegate?.audioBackend(self, needsRestart: .configurationChange)
    }

    private func observeSession() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        let session = AVAudioSession.sharedInstance()
        sessionObservers.append(notifications.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            guard let self,
                  let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended
            else { return }
            self.withLock {
                self.generations[0] += 1
                self.generations[1] += 1
            }
            self.delegate?.audioBackend(self, needsRestart: .interruptionEnded)
        })
        sessionObservers.append(notifications.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let reason = raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            switch reason {
            case .oldDeviceUnavailable?:
                self.delegate?.audioBackend(self, routeDidChange: self.currentRoute, previousOutputLost: true)
            case .newDeviceAvailable?, .override?, .routeConfigurationChange?, .wakeFromSleep?, .noSuitableRouteForCategory?:
                self.delegate?.audioBackend(self, routeDidChange: self.currentRoute, previousOutputLost: false)
            default:
                break
            }
        })
        sessionObservers.append(notifications.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.delegate?.audioBackend(self, needsRestart: .mediaServicesReset)
        })
        #endif
    }

    #if os(iOS) || os(tvOS) || os(visionOS)
    static func route(of description: AVAudioSessionRouteDescription) -> OutputRoute {
        guard let port = description.outputs.first?.portType else { return .other }
        switch port {
        case .builtInSpeaker, .builtInReceiver:
            return .builtIn
        case .headphones, .lineOut, .usbAudio, .HDMI:
            return .wired
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
            return .bluetooth
        case .airPlay:
            return .airPlay
        case .carAudio:
            return .carPlay
        default:
            return .other
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
