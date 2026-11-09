import Foundation
import LofiAudio
import LofiDirector

/// What the atmosphere player reports, for the log and the status screen.
public enum AmbienceEvent: Sendable, Hashable {
    case sceneChanged(StoryScene)
    case musicYield(Bool)
    /// A swell or hush asked the narrator to pause after the sentence.
    case narrationHold(StoryScene.Moment)
    /// A one-off sound played on its sentence.
    case oneShot(OneShotSound)
    case missingSound(AmbientSound)
    case error(String)
}

/// The atmosphere's state, for the status screen and tests.
public struct AmbienceSnapshot: Sendable, Hashable {
    public struct Voice: Sendable, Hashable {
        public var sound: AmbientSound
        /// The variant playing, when the recording is one.
        public var variant: String?
        public var recording: String
        public var gain: Double
        public var playing: Bool
        public var fadingOut: Bool
    }

    public var enabled: Bool
    public var narrating: Bool
    public var engineRunning: Bool
    public var hasTrack: Bool
    /// The scene playing now. Only the present: never anything ahead of the narration.
    public var scene: StoryScene?
    public var dipped: Bool
    public var musicYielding: Bool
    public var routeMuted: Bool
    /// Short narration pauses for swells and hushes are on, and the app can do them.
    public var pausesEnabled: Bool
    public var pausesAvailable: Bool
    /// One-off sounds are on, and how many of them have a recording.
    public var oneShotsEnabled: Bool
    public var oneShotSounds: Int
    public var voices: [Voice]
    public var missingSounds: [AmbientSound]
    public var missingOneShots: [OneShotSound]
    public var lastError: String?
}

/// Plays the atmosphere: the sounds of the scene being narrated, looped seamlessly
/// under the voice and the music, changing only when the story changes scene.
///
/// The host forwards the same narrator events it gives ``LofiScorePlayer``, and
/// ``setTrack(_:forBook:)`` once the book's atmosphere track has been found. When a scene
/// has a sound that would clash with the music (a crowd), ``onMusicYieldChanged`` asks the
/// host to fade the music out until the scene moves on.
///
/// Like the music, it never touches the audio session, Now Playing or the remote commands.
///
/// Thread safety: every public method may be called from any thread. The player hops onto
/// its scheduler and touches its state only there; callbacks run there too.
public final class AmbiencePlayer: @unchecked Sendable {
    /// Called with true when the music should step aside, false when it may come back.
    public var onMusicYieldChanged: ((Bool) -> Void)?
    public var onEvent: ((AmbienceEvent) -> Void)?
    /// Asks the app to pause the narrator for this many seconds at the end of the
    /// sentence being narrated, for a swell or a hush. It answers false when it cannot,
    /// and the scene then changes without a pause. The app reports the pause itself
    /// through ``narrationHold(began:)``. Nil: no pauses.
    public var requestNarrationHold: ((TimeInterval) -> Bool)?

    public let library: AmbienceLibrary
    public let oneShots: OneShotLibrary
    private let backend: AmbienceBackend
    private let scheduler: LofiScheduler
    private var config: AtmosphereConfig
    private var director: AtmosphereDirector
    private var rng: SplitMix64

    private struct Voice {
        var sound: AmbientSound
        var level: AmbientLevel
        var recording: AmbienceRecording
        var duration: TimeInterval
        /// Linear gain before the transport and the chapter dip.
        var ramp: Ramp
        var playing: Bool
        var retiring: Bool
    }

    private var bookID: String?
    /// The last track given, kept for its book: it may arrive just before the book opens.
    private var givenTrack: (bookID: String, track: AtmosphereTrack?)?
    private var enabled = true
    private var narrating = false
    private var routeMuted = false
    private var playhead: Int?
    private var transport = Ramp(value: 0)
    private var dip = Ramp(value: 1)
    private var voices: [Voice?]
    private var yielding = false
    private var missing: Set<AmbientSound> = []
    private var lastError: String?
    private var engineRetries = 0

    // Swells and hushes.
    private var pausesEnabled = true
    private var sentenceDuration: TimeInterval?
    /// When the narrator last started or the listener last sought; no pause soon after.
    private var settledSince: TimeInterval = -.infinity
    private var lastHoldAt: TimeInterval = -.infinity
    /// A pause asked for and not begun yet, until it expires.
    private var pendingMoment: (moment: StoryScene.Moment, expires: TimeInterval)?
    private var holding = false
    /// Extra gain on the sounds of the scene playing, while it swells.
    private var swell = Ramp(value: 1)
    private var holdTimer: LofiCancellable?

    // One-off sounds.
    private var oneShotsEnabled = false
    private var lastOneShotAt: TimeInterval = -.infinity
    private var lastOneShotIndex: Int?
    /// A one-off sound waiting for its moment inside the sentence being narrated.
    private var pendingCue: (cue: AtmosphereTrack.Cue, timer: LofiCancellable)?
    private var missingOneShots: Set<OneShotSound> = []

    private var ticker: LofiCancellable?
    private var dwellTimer: LofiCancellable?
    private var stopSlotsTimer: LofiCancellable?
    private var engineStopTimer: LofiCancellable?
    private var retryTimer: LofiCancellable?

    public init(
        library: AmbienceLibrary,
        oneShots: OneShotLibrary? = nil,
        backend: AmbienceBackend,
        scheduler: LofiScheduler = DispatchScheduler(label: "LofiScore.atmosphere"),
        config: AtmosphereConfig = AtmosphereConfig(),
        seed: UInt64? = nil
    ) {
        self.library = library
        self.oneShots = oneShots ?? .empty(at: library.folder.appendingPathComponent(OneShotLibrary.folderName))
        self.backend = backend
        self.scheduler = scheduler
        self.config = config
        director = AtmosphereDirector(config: config)
        rng = SplitMix64(seed: seed ?? UInt64.random(in: 1...UInt64.max))
        voices = Array(repeating: nil, count: backend.slotCount)
        backend.delegate = self
    }

    deinit {
        for timer in [ticker, dwellTimer, stopSlotsTimer, engineStopTimer, retryTimer, holdTimer, pendingCue?.timer] {
            timer?.cancel()
        }
    }

    // MARK: - Narrator events

    public func openBook(id: String) {
        scheduler.perform { [self] in
            guard bookID != id else { return }
            bookID = id
            director.setTrack(givenTrack?.bookID == id ? givenTrack?.track : nil)
            missing = []
            playhead = nil
            cancelCue()
            lastOneShotIndex = nil
            retireAll(over: config.fadeOut, at: scheduler.now)
            updateTransport(at: scheduler.now)
            updateYield()
        }
    }

    public func closeBook() {
        scheduler.perform { [self] in
            guard bookID != nil else { return }
            bookID = nil
            director.setTrack(nil)
            playhead = nil
            cancelCue()
            dwellTimer?.cancel()
            dwellTimer = nil
            retireAll(over: config.fadeOut, at: scheduler.now)
            updateTransport(at: scheduler.now)
            updateYield()
        }
    }

    /// The book's atmosphere track, or nil when it has none. Kept for when that book opens
    /// if another book is open now.
    public func setTrack(_ track: AtmosphereTrack?, forBook id: String) {
        scheduler.perform { [self] in
            givenTrack = (id, track)
            guard bookID == id else { return }
            director.setTrack(track)
            missing = []
            cancelCue()
            if track == nil { retireAll(over: config.sceneFade, at: scheduler.now) }
            evaluate(seek: true)
            updateTransport(at: scheduler.now)
            updateYield()
        }
    }

    public func narratorDidPlay() {
        scheduler.perform { [self] in
            if !narrating { settledSince = scheduler.now }
            narrating = true
            updateTransport(at: scheduler.now)
        }
    }

    public func narratorDidPause() {
        scheduler.perform { [self] in
            narrating = false
            endHold(release: config.fadeOut)
            cancelCue()
            updateTransport(at: scheduler.now)
        }
    }

    public func narratorDidSeek(toGlobalSentenceIndex index: Int?) {
        scheduler.perform { [self] in
            guard let index else { return }
            playhead = index
            settledSince = scheduler.now
            pendingMoment = nil
            cancelCue()
            evaluate(seek: true)
        }
    }

    public func sentenceDidStart(globalSentenceIndex: Int?, duration: TimeInterval?) {
        scheduler.perform { [self] in
            guard let globalSentenceIndex else { return }
            let isJump = playhead.map { globalSentenceIndex < $0 } ?? true
            if isJump { settledSince = scheduler.now }
            playhead = globalSentenceIndex
            sentenceDuration = duration
            evaluate(seek: isJump)
            if let pending = pendingCue, pending.cue.globalIndex != globalSentenceIndex {
                // The narrator has read past the sound's words: play it now, unless this
                // is a jump rather than the next sentence.
                if !isJump, globalSentenceIndex == pending.cue.globalIndex + 1 {
                    pending.timer.cancel()
                    pendingCue = nil
                    playOneShot(pending.cue)
                } else {
                    cancelCue()
                }
            }
            considerOneShot(at: globalSentenceIndex, duration: duration, jump: isJump)
        }
    }

    /// The narrator's pause for a swell or a hush began (true) or ended (false).
    public func narrationHold(began: Bool) {
        scheduler.perform { [self] in
            let now = scheduler.now
            if began {
                guard let pending = pendingMoment, now <= pending.expires else { return }
                pendingMoment = nil
                beginHold(pending.moment, at: now)
            } else {
                endHold(release: config.swellRelease)
            }
        }
    }

    // MARK: - Settings

    public func setEnabled(_ isEnabled: Bool) {
        scheduler.perform { [self] in
            enabled = isEnabled
            if !isEnabled {
                endHold(release: config.fadeOut)
                cancelCue()
            }
            updateTransport(at: scheduler.now)
            updateYield()
        }
    }

    /// Short narration pauses for swells and hushes.
    public func setPausesEnabled(_ isEnabled: Bool) {
        scheduler.perform { [self] in
            pausesEnabled = isEnabled
            if !isEnabled { pendingMoment = nil }
        }
    }

    /// One-off sounds (a knock, a clap of thunder) on the sentences that say they happen.
    public func setOneShotsEnabled(_ isEnabled: Bool) {
        scheduler.perform { [self] in
            oneShotsEnabled = isEnabled
            if !isEnabled { cancelCue() }
        }
    }

    /// Where a sound at "full" sits under the voice, in dB.
    public func setLevel(dB: Double) {
        scheduler.perform { [self] in
            config.bedLevelDB = min(AtmosphereConfig.levelRange.upperBound, max(AtmosphereConfig.levelRange.lowerBound, dB))
            director.config.bedLevelDB = config.bedLevelDB
            let now = scheduler.now
            for slot in voices.indices {
                guard var voice = voices[slot], !voice.retiring else { continue }
                voice.ramp.go(to: gain(for: voice.sound, level: voice.level, recording: voice.recording), over: 1, at: now, shape: .linear)
                voices[slot] = voice
            }
            ensureTicker()
        }
    }

    public func setMutedRoutes(_ routes: Set<OutputRoute>) {
        scheduler.perform { [self] in
            config.mutedRoutes = routes
            routeMuted = routes.contains(backend.currentRoute)
            updateTransport(at: scheduler.now)
            updateYield()
        }
    }

    public func snapshot(_ completion: @escaping (AmbienceSnapshot) -> Void) {
        scheduler.perform { [self] in
            completion(makeSnapshot())
        }
    }

    // MARK: - Deciding

    private func evaluate(seek: Bool) {
        guard let playhead, director.track != nil, bookID != nil else { return }
        let now = scheduler.now
        switch director.step(at: playhead, now: now, seek: seek) {
        case .hold:
            break
        case let .change(target, fade):
            dwellTimer?.cancel()
            dwellTimer = nil
            apply(target, fade: fade, at: now)
            if !seek, let moment = target.scene.moment, target.entryIndex == playhead {
                askForHold(moment, at: now)
            }
        case let .dip(dipped):
            dip.go(to: dipped ? Gain.linear(fromDB: config.chapterDipDB) : 1, over: config.levelFade, at: now, shape: .linear)
            ensureTicker()
        case let .wait(until):
            guard dwellTimer == nil else { return }
            dwellTimer = scheduler.schedule(after: max(0.05, until - now)) { [weak self] in
                guard let self else { return }
                self.dwellTimer = nil
                self.evaluate(seek: false)
            }
        }
    }

    private func apply(_ target: AtmosphereTarget, fade: TimeInterval, at now: TimeInterval) {
        let scene = target.scene
        dip.go(to: target.dipped ? Gain.linear(fromDB: config.chapterDipDB) : 1, over: fade, at: now, shape: .linear)

        var desired: [(layer: SceneLayer, recording: AmbienceRecording)] = []
        for layer in scene.layers {
            guard let recording = library.recording(for: layer, key: recordingKey(layer, scene: scene)) else {
                if missing.insert(layer.sound).inserted { onEvent?(.missingSound(layer.sound)) }
                continue
            }
            desired.append((layer, recording))
        }
        let wanted = Set(desired.map(\.recording.id))

        // Fade out what the new scene does not have.
        for slot in voices.indices {
            guard var voice = voices[slot], !wanted.contains(voice.recording.id), !voice.retiring else { continue }
            voice.retiring = true
            voice.ramp.go(to: 0, over: fade, at: now, shape: .equalPower)
            voices[slot] = voice
        }
        // Keep, adjust or start what it has.
        for (layer, recording) in desired {
            let target = gain(for: layer.sound, level: layer.level, recording: recording)
            if let slot = voices.firstIndex(where: { $0?.recording.id == recording.id }), var voice = voices[slot] {
                let sameLevel = !voice.retiring && voice.level == layer.level
                voice.retiring = false
                voice.level = layer.level
                if !sameLevel {
                    voice.ramp.go(to: target, over: fade, at: now, shape: .linear)
                }
                voices[slot] = voice
                continue
            }
            guard let slot = freeSlot() else { continue }
            do {
                let duration = try backend.load(library.url(for: recording), slot: slot, filter: AmbienceFilter(for: layer.sound))
                var voice = Voice(
                    sound: layer.sound, level: layer.level, recording: recording, duration: duration,
                    ramp: Ramp(value: 0), playing: false, retiring: false
                )
                voice.ramp.jump(to: 0, at: now)
                voice.ramp.go(to: target, over: fade, at: now, shape: .equalPower)
                backend.setGain(0, slot: slot)
                voices[slot] = voice
                if shouldPlay, backend.isEngineRunning { startSlot(slot) }
            } catch {
                report("could not load \(recording.file): \(error)")
            }
        }
        onEvent?(.sceneChanged(scene))
        updateYield()
        ensureTicker()
    }

    /// The key that picks a recording: weather is the same across the book, everything
    /// else belongs to its place. A variant behaves like the sound it is a kind of.
    private func recordingKey(_ layer: SceneLayer, scene: StoryScene) -> String {
        let book = bookID ?? ""
        switch layer.sound.scope {
        case .weather: return "\(book)|\(layer.key)"
        case .place: return "\(book)|\(scene.placeID ?? "-")|\(layer.key)"
        }
    }

    /// Linear gain for a sound at a level, from the file's measured loudness.
    private func gain(for sound: AmbientSound, level: AmbientLevel, recording: AmbienceRecording) -> Double {
        let targetLUFS = config.voiceLoudnessLUFS + config.bedLevelDB + sound.levelOffsetDB + level.offsetDB
        return min(1, Gain.linear(fromDB: targetLUFS - library.loudness(of: recording)))
    }

    private func freeSlot() -> Int? {
        if let free = voices.firstIndex(where: { $0 == nil }) { return free }
        // Take the quietest voice that is already fading out.
        let now = scheduler.now
        let retiring = voices.indices.filter { voices[$0]?.retiring == true }
        guard let slot = retiring.min(by: { voices[$0]!.ramp.value(at: now) < voices[$1]!.ramp.value(at: now) }) else { return nil }
        backend.stop(slot: slot)
        voices[slot] = nil
        return slot
    }

    private func retireAll(over fade: TimeInterval, at now: TimeInterval) {
        for slot in voices.indices {
            guard var voice = voices[slot] else { continue }
            voice.retiring = true
            voice.ramp.go(to: 0, over: fade, at: now, shape: .equalPower)
            voices[slot] = voice
        }
        ensureTicker()
    }

    private func updateYield() {
        let crowd = voices.contains { voice in
            guard let voice, !voice.retiring else { return false }
            return voice.sound.musicPolicy == .replacesMusic && voice.level >= .soft
        }
        let should = enabled && !routeMuted && bookID != nil && crowd
        guard should != yielding else { return }
        yielding = should
        onEvent?(.musicYield(should))
        onMusicYieldChanged?(should)
    }

    // MARK: - Swells and hushes

    /// Asks the app to pause the narrator after this sentence, when a pause is allowed and
    /// would be heard: a swell needs sounds to rise, a hush sounds to cut.
    private func askForHold(_ moment: StoryScene.Moment, at now: TimeInterval) {
        guard pausesEnabled, shouldPlay, backend.isEngineRunning, !holding,
              now - lastHoldAt >= config.minTimeBetweenHolds,
              now - settledSince >= config.noHoldAfterStart,
              let request = requestNarrationHold
        else { return }
        let heard: Bool
        switch moment {
        case .swell: heard = voices.contains { $0 != nil && $0?.retiring == false }
        case .hush: heard = voices.contains { $0?.retiring == true }
        }
        guard heard, request(config.holdSeconds) else { return }
        lastHoldAt = now
        pendingMoment = (moment, now + (sentenceDuration ?? 10) + config.holdSeconds + 2)
        onEvent?(.narrationHold(moment))
    }

    private func beginHold(_ moment: StoryScene.Moment, at now: TimeInterval) {
        holding = true
        switch moment {
        case .swell:
            // The new sounds finish fading in and rise while the narrator is quiet.
            for slot in voices.indices {
                guard var voice = voices[slot], !voice.retiring else { continue }
                voice.ramp.go(to: gain(for: voice.sound, level: voice.level, recording: voice.recording), over: config.swellRise, at: now, shape: .equalPower)
                voices[slot] = voice
            }
            swell.go(to: Gain.linear(fromDB: config.swellBoostDB), over: config.swellRise, at: now, shape: .equalPower)
        case .hush:
            // What the old scene still had is gone in the pause.
            for slot in voices.indices {
                guard var voice = voices[slot], voice.retiring else { continue }
                voice.ramp.go(to: 0, over: min(0.3, config.holdSeconds / 2), at: now, shape: .equalPower)
                voices[slot] = voice
            }
        }
        holdTimer?.cancel()
        // If the app never says the pause ended, settle anyway.
        holdTimer = scheduler.schedule(after: config.holdSeconds + 3) { [weak self] in
            guard let self else { return }
            self.holdTimer = nil
            self.endHold(release: self.config.swellRelease)
        }
        ensureTicker()
    }

    private func endHold(release: TimeInterval) {
        pendingMoment = nil
        holdTimer?.cancel()
        holdTimer = nil
        guard holding else { return }
        holding = false
        swell.go(to: 1, over: release, at: scheduler.now, shape: .equalPower)
        ensureTicker()
    }

    // MARK: - One-off sounds

    /// Waits for the moment inside the sentence where the track's one-off sound for it
    /// happens, when one-off sounds are on and one would not crowd the listener: only
    /// while narrating (a sentence with a duration: never while reading on screen), not
    /// on a jump, not right after starting or seeking, and not soon after the last one.
    private func considerOneShot(at index: Int, duration: TimeInterval?, jump: Bool) {
        let now = scheduler.now
        guard oneShotsEnabled, shouldPlay, !jump,
              let duration, duration > 0,
              let cue = director.track?.cue(at: index),
              pendingCue == nil, lastOneShotIndex != index,
              now - settledSince >= config.noOneShotAfterStart,
              now - lastOneShotAt >= config.minTimeBetweenOneShots
        else { return }
        let delay = min(config.maxOneShotDelay, duration * cue.fraction)
        guard delay > 0.05 else {
            playOneShot(cue)
            return
        }
        let timer = scheduler.schedule(after: delay) { [weak self] in
            guard let self, let pending = self.pendingCue, pending.cue == cue else { return }
            self.pendingCue = nil
            self.playOneShot(cue)
        }
        pendingCue = (cue, timer)
    }

    private func playOneShot(_ cue: AtmosphereTrack.Cue) {
        guard oneShotsEnabled, shouldPlay, backend.isEngineRunning else { return }
        let now = scheduler.now
        lastOneShotIndex = cue.globalIndex
        guard let recording = oneShots.recording(of: cue.sound, key: "\(bookID ?? "")|\(cue.globalIndex)") else {
            missingOneShots.insert(cue.sound)
            return
        }
        let targetLUFS = config.voiceLoudnessLUFS + config.bedLevelDB + config.oneShotBoostDB + cue.sound.levelOffsetDB
        let gain = min(1, Gain.linear(fromDB: targetLUFS - oneShots.loudness(of: recording))) * transport.value(at: now)
        do {
            try backend.playOnce(oneShots.url(for: recording), gain: Float(gain), filter: .standard)
            lastOneShotAt = now
            onEvent?(.oneShot(cue.sound))
        } catch {
            report("could not play \(recording.file): \(error)")
        }
    }

    private func cancelCue() {
        pendingCue?.timer.cancel()
        pendingCue = nil
    }

    // MARK: - Engine and transport

    private var shouldPlay: Bool {
        enabled && narrating && !routeMuted && bookID != nil && director.track != nil
    }

    private func updateTransport(at now: TimeInterval, fadeOut: TimeInterval? = nil) {
        if shouldPlay {
            stopSlotsTimer?.cancel()
            stopSlotsTimer = nil
            engineStopTimer?.cancel()
            engineStopTimer = nil
            guard ensureEngine() else { return }
            for slot in voices.indices where voices[slot]?.playing == false {
                startSlot(slot)
            }
            transport.go(to: 1, over: config.fadeIn, at: now, shape: .equalPower)
        } else {
            let fade = fadeOut ?? config.fadeOut
            transport.go(to: 0, over: fade, at: now, shape: .equalPower)
            if stopSlotsTimer == nil {
                stopSlotsTimer = scheduler.schedule(after: fade + 0.1) { [weak self] in
                    self?.stopSlots()
                }
            }
            if engineStopTimer == nil, backend.isEngineRunning {
                engineStopTimer = scheduler.schedule(after: config.stopEngineAfterPause) { [weak self] in
                    guard let self else { return }
                    self.engineStopTimer = nil
                    guard !self.shouldPlay else { return }
                    self.stopSlots()
                    self.backend.stopEngine()
                }
            }
        }
        ensureTicker()
    }

    private func stopSlots() {
        stopSlotsTimer = nil
        guard !shouldPlay else { return }
        for slot in voices.indices {
            guard var voice = voices[slot] else { continue }
            if voice.playing { backend.stop(slot: slot) }
            voice.playing = false
            if voice.retiring {
                voices[slot] = nil
            } else {
                voices[slot] = voice
            }
        }
    }

    @discardableResult
    private func ensureEngine() -> Bool {
        if backend.isEngineRunning { return true }
        do {
            try backend.startEngine()
            engineRetries = 0
            return true
        } catch {
            report("could not start the engine: \(error)")
            scheduleRetry()
            return false
        }
    }

    private func scheduleRetry() {
        guard retryTimer == nil, engineRetries < 5 else { return }
        engineRetries += 1
        retryTimer = scheduler.schedule(after: 1) { [weak self] in
            guard let self else { return }
            self.retryTimer = nil
            self.updateTransport(at: self.scheduler.now)
        }
    }

    private func startSlot(_ slot: Int) {
        guard var voice = voices[slot] else { return }
        let offset = voice.duration > 1 ? rng.nextUnit() * voice.duration : 0
        do {
            try backend.play(slot: slot, from: offset)
            voice.playing = true
            voices[slot] = voice
        } catch {
            report("could not play \(voice.recording.file): \(error)")
        }
    }

    // MARK: - Gains

    private func ensureTicker() {
        pushGains()
        guard ticker == nil, isMoving(at: scheduler.now) else { return }
        ticker = scheduler.scheduleRepeating(every: 1 / max(1, config.gainUpdateRate)) { [weak self] in
            guard let self else { return }
            self.pushGains()
            if !self.isMoving(at: self.scheduler.now) {
                self.ticker?.cancel()
                self.ticker = nil
            }
        }
    }

    private func isMoving(at now: TimeInterval) -> Bool {
        transport.isRunning(at: now) || dip.isRunning(at: now) || swell.isRunning(at: now)
            || voices.contains { $0.map { $0.ramp.isRunning(at: now) } ?? false }
            || voices.contains { $0?.retiring == true }
    }

    private func pushGains() {
        let now = scheduler.now
        let master = transport.value(at: now) * dip.value(at: now)
        let swelling = swell.value(at: now)
        for slot in voices.indices {
            guard let voice = voices[slot] else { continue }
            let value = voice.ramp.value(at: now)
            backend.setGain(Float(min(1, max(0, value * master * (voice.retiring ? 1 : swelling)))), slot: slot)
            if voice.retiring, !voice.ramp.isRunning(at: now), value <= 0.0001 {
                if voice.playing { backend.stop(slot: slot) }
                voices[slot] = nil
            }
        }
    }

    private func report(_ message: String) {
        lastError = message
        onEvent?(.error(message))
    }

    private func makeSnapshot() -> AmbienceSnapshot {
        let now = scheduler.now
        let master = transport.value(at: now) * dip.value(at: now)
        return AmbienceSnapshot(
            enabled: enabled,
            narrating: narrating,
            engineRunning: backend.isEngineRunning,
            hasTrack: director.track != nil,
            scene: director.track == nil ? nil : director.applied.scene,
            dipped: director.applied.dipped,
            musicYielding: yielding,
            routeMuted: routeMuted,
            pausesEnabled: pausesEnabled,
            pausesAvailable: requestNarrationHold != nil,
            oneShotsEnabled: oneShotsEnabled,
            oneShotSounds: oneShots.sounds.count,
            voices: voices.compactMap { voice in
                voice.map {
                    AmbienceSnapshot.Voice(
                        sound: $0.sound, variant: $0.recording.variant, recording: $0.recording.file,
                        gain: $0.ramp.value(at: now) * master, playing: $0.playing, fadingOut: $0.retiring
                    )
                }
            },
            missingSounds: missing.sorted { $0.rawValue < $1.rawValue },
            missingOneShots: missingOneShots.sorted { $0.rawValue < $1.rawValue },
            lastError: lastError
        )
    }
}

extension AmbiencePlayer: AmbienceBackendDelegate {
    public func ambienceBackend(_ backend: AmbienceBackend, needsRestart reason: BackendRestartReason) {
        scheduler.perform { [self] in
            if reason == .mediaServicesReset {
                backend.rebuild()
                for slot in voices.indices {
                    guard var voice = voices[slot] else { continue }
                    voice.playing = false
                    if voice.retiring || (try? backend.load(library.url(for: voice.recording), slot: slot, filter: AmbienceFilter(for: voice.sound))) == nil {
                        voices[slot] = nil
                    } else {
                        voices[slot] = voice
                    }
                }
            } else {
                for slot in voices.indices where voices[slot] != nil {
                    voices[slot]?.playing = false
                }
            }
            engineRetries = 0
            if shouldPlay { updateTransport(at: scheduler.now) }
        }
    }

    public func ambienceBackend(_ backend: AmbienceBackend, routeDidChange route: OutputRoute, previousOutputLost: Bool) {
        scheduler.perform { [self] in
            routeMuted = config.mutedRoutes.contains(route)
            // Headphones pulled: out at once; the narrator pauses and its next play brings us back.
            if previousOutputLost { narrating = false }
            updateTransport(at: scheduler.now, fadeOut: previousOutputLost ? 0.1 : nil)
            updateYield()
        }
    }
}
