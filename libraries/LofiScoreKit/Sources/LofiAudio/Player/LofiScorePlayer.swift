import Foundation
import LofiDirector
import LofiScoreCore

/// The lofi music engine: follows the narrator, asks the ``MoodDirector`` what mood to play,
/// and plays it on two decks with equal-power crossfades, a bed level under the voice, and a
/// small lift in long silences.
///
/// The host app (the Expo module, or the v3 adapter later) forwards narrator events:
///
/// | Narrator event                    | Call                                   | Music response                          |
/// |-----------------------------------|----------------------------------------|-----------------------------------------|
/// | Book opened / closed              | ``openBook(id:)`` / ``closeBook()``    | Fade out and drop the old book's state  |
/// | Play                              | ``narratorDidPlay()``                  | Fade in the current mood over 2 s       |
/// | Pause, sleep timer                | ``narratorDidPause()``                 | Fade out over 1 s; engine off after 2 min |
/// | Sentence starts                   | ``sentenceDidStart(globalSentenceIndex:duration:)`` | Bed level; lift after 1.5 s of silence |
/// | Seek, skip, chapter jump          | ``narratorDidSeek(toGlobalSentenceIndex:)`` | Wait for the new place's reading   |
/// | Rate change                       | nothing                                | Nothing: the music keeps its own speed  |
///
/// Mood readings from the text side go to ``receive(_:)``.
///
/// The player never changes the audio session (category, mode, options or activation),
/// Now Playing, or the remote commands. The narrator owns all of those; the music simply
/// plays inside the same session.
///
/// Thread safety: every public method may be called from any thread. The player hops onto
/// its scheduler (one serial queue in the app) and touches its state only there; callbacks
/// (``onDecision``, ``onEvent``) run there too.
public final class LofiScorePlayer: @unchecked Sendable {
    /// Called when the director changes the mood.
    public var onDecision: ((MoodDecision) -> Void)?
    /// Called for everything worth logging: tracks starting, crossfades, errors.
    public var onEvent: ((PlayerEvent) -> Void)?

    public let library: MusicLibrary
    private let backend: LofiAudioBackend
    private let scheduler: LofiScheduler
    private var config: ScoreConfig
    private let director: MoodDirector
    private var rotation: TrackRotation

    private var bookID: String?
    private var enabled = true
    private var narrating = false
    private var routeMuted = false
    private var transport = Ramp(value: 0)
    private var crossfader = Crossfader()
    private var ducker = Ducker()
    private var decks = DeckPair()
    /// A change waiting for the outgoing track's next bar line.
    private var pendingStart: MusicRequest?
    /// A change waiting for the current crossfade (or fade-out) to finish.
    private var queued: MusicRequest?
    /// The decks hold the previous book's music; clear them once silent.
    private var decksStale = false
    private var graceUsed = false
    private var failedTracks: Set<String> = []
    private var engineRetries = 0
    private var lastError: String?

    private var ticker: LofiCancellable?
    private var barTimer: LofiCancellable?
    private var crossfadeTimer: LofiCancellable?
    private var rotationTimer: LofiCancellable?
    private var directorTimer: LofiCancellable?
    private var gapTimer: LofiCancellable?
    private var fadeOutTimer: LofiCancellable?
    private var engineStopTimer: LofiCancellable?
    private var graceTimer: LofiCancellable?
    private var retryTimer: LofiCancellable?

    public init(
        library: MusicLibrary,
        backend: LofiAudioBackend,
        scheduler: LofiScheduler = DispatchScheduler(),
        config: ScoreConfig = ScoreConfig(),
        rotationSeed: UInt64? = nil
    ) {
        self.library = library
        self.backend = backend
        self.scheduler = scheduler
        self.config = config
        director = MoodDirector(config: config.director, clock: scheduler)
        rotation = TrackRotation(
            avoidLast: config.avoidRecentTracks,
            seed: rotationSeed ?? UInt64.random(in: 1...UInt64.max)
        )
        director.setNarrationPlaying(false)
        backend.delegate = self
    }

    deinit {
        for timer in [ticker, barTimer, crossfadeTimer, rotationTimer, directorTimer, gapTimer, fadeOutTimer, engineStopTimer, graceTimer, retryTimer] {
            timer?.cancel()
        }
    }

    // MARK: - Narrator events

    /// A book was opened. `id` only needs to tell books apart.
    public func openBook(id: String) {
        scheduler.perform { [self] in
            let now = scheduler.now
            if bookID != nil {
                closeBookNow(at: now)
            }
            bookID = id
            director.reset()
            director.setNarrationPlaying(narrating)
            graceUsed = false
            updateTransport(at: now)
            emit(.bookOpened(id))
        }
    }

    /// The book was closed: fade out and forget it.
    public func closeBook() {
        scheduler.perform { [self] in
            guard bookID != nil else { return }
            closeBookNow(at: scheduler.now)
            emit(.bookClosed)
        }
    }

    public func narratorDidPlay() {
        scheduler.perform { [self] in
            narrating = true
            engineRetries = 0
            director.setNarrationPlaying(true)
            updateTransport(at: scheduler.now)
        }
    }

    /// The narrator paused, or the sleep timer stopped it.
    public func narratorDidPause() {
        scheduler.perform { [self] in
            narrating = false
            director.setNarrationPlaying(false)
            cancel(&gapTimer)
            updateTransport(at: scheduler.now)
        }
    }

    /// The listener jumped (seek, skip, chapter jump). The music keeps going until the
    /// reading for the new place arrives, then moves there with a quick crossfade.
    public func narratorDidSeek(toGlobalSentenceIndex index: Int?) {
        scheduler.perform { [self] in
            let now = scheduler.now
            director.noteSeek(toGlobalSentenceIndex: index)
            ducker.reset(at: now)
            cancel(&gapTimer)
            armDirectorTimer(at: now)
            pushGains()
        }
    }

    /// A sentence started playing.
    /// - Parameters:
    ///   - globalSentenceIndex: its index across the whole book, if known. Readings for later
    ///     sentences are then refused.
    ///   - duration: how long its audio lasts in wall-clock seconds (clip length divided by
    ///     the playback rate), if known. Needed to notice long silences.
    public func sentenceDidStart(globalSentenceIndex: Int?, duration: TimeInterval?) {
        scheduler.perform { [self] in
            let now = scheduler.now
            if let globalSentenceIndex {
                director.notePlayhead(globalSentenceIndex: globalSentenceIndex)
            }
            ducker.sentenceStarted(at: now, duration: duration, settings: config.ducking)
            armGapTimer(at: now)
            pushGains()
        }
    }

    /// The current sentence's audio ended (for hosts that know ends rather than durations).
    public func sentenceDidEnd() {
        scheduler.perform { [self] in
            ducker.sentenceEnded(at: scheduler.now)
            armGapTimer(at: scheduler.now)
        }
    }

    /// A mood reading from the text side.
    public func receive(_ observation: MoodObservation) {
        scheduler.perform { [self] in
            let now = scheduler.now
            guard bookID != nil else { return }
            handle(director.receive(observation), at: now)
            if graceTimer != nil, director.phase != .awaitingFirstReading {
                // The first reading arrived during the start grace: begin now, in its mood.
                cancel(&graceTimer)
                updateTransport(at: now)
            }
        }
    }

    // MARK: - Settings

    /// Turns the music on or off (the toolbar button, or the per-book opt-out).
    public func setEnabled(_ isEnabled: Bool) {
        scheduler.perform { [self] in
            enabled = isEnabled
            updateTransport(at: scheduler.now)
        }
    }

    public func setDucking(_ settings: DuckingSettings) {
        scheduler.perform { [self] in
            config.ducking = settings
            for deck in Deck.allCases {
                if let track = decks[deck].track {
                    decks[deck].bedGain = settings.bedGain(forTrackLoudness: library.loudness(of: track))
                }
            }
            armGapTimer(at: scheduler.now)
            pushGains()
        }
    }

    public func setMusicVolume(_ volume: Double) {
        scheduler.perform { [self] in
            config.musicVolume = min(1, max(0, volume))
            pushGains()
        }
    }

    /// Routes where the music stays off, such as `[.carPlay]`.
    public func setMutedRoutes(_ routes: Set<OutputRoute>) {
        scheduler.perform { [self] in
            config.mutedRoutes = routes
            routeMuted = routes.contains(backend.currentRoute)
            updateTransport(at: scheduler.now)
        }
    }

    /// Delivers a snapshot of the player's state on the scheduler's context.
    public func snapshot(_ completion: @escaping (PlayerSnapshot) -> Void) {
        scheduler.perform { [self] in
            completion(makeSnapshot())
        }
    }

    // MARK: - Transport

    private var shouldPlay: Bool {
        bookID != nil && enabled && narrating && !routeMuted
    }

    private func updateTransport(at now: TimeInterval) {
        if shouldPlay {
            guard transport.target < 1 else { return }
            guard beginPlayback(at: now) else { return }
            transport.go(to: 1, over: config.fadeIn, at: now, shape: .equalPower)
            armRotation(at: now)
            armGapTimer(at: now)
            pushGains()
        } else {
            cancel(&graceTimer)
            guard transport.target > 0 else { return }
            beginFadeOut(over: config.fadeOut, at: now)
        }
    }

    /// Gets the engine and the right deck going. Returns false when playback has to wait
    /// (for the first reading, a fade-out, or an engine that will not start yet).
    private func beginPlayback(at now: TimeInterval) -> Bool {
        cancel(&engineStopTimer)
        if decksStale {
            if fadeOutTimer != nil { return false }
            clearDecks(at: now)
        }
        if director.phase == .awaitingFirstReading, !graceUsed, config.startGrace > 0 {
            graceUsed = true
            graceTimer = scheduler.schedule(after: config.startGrace) { [weak self] in
                guard let self else { return }
                self.graceTimer = nil
                self.updateTransport(at: self.scheduler.now)
            }
            return false
        }
        if graceTimer != nil { return false }
        cancel(&fadeOutTimer)
        if !backend.isEngineRunning {
            do {
                try backend.startEngine()
                engineRetries = 0
                emit(.engineStarted)
            } catch {
                report("The audio engine would not start: \(error)")
                scheduleEngineRetry()
                return false
            }
            // With the engine off nothing was really playing, whatever the decks say.
            for deck in Deck.allCases where decks[deck].isRunning {
                markStopped(deck, at: now)
            }
        }
        let target = crossfader.targetDeck
        if decks[target].track == nil {
            guard load(director.currentBucket, on: target) else { return false }
        }
        let moving = crossfader.isMoving(at: now)
        for deck in Deck.allCases where decks[deck].track != nil && !decks[deck].isRunning {
            guard deck == target || moving else { continue }
            startDeck(deck, from: decks[deck].resumeAt, at: now)
        }
        return decks[target].isRunning
    }

    private func beginFadeOut(over duration: TimeInterval, at now: TimeInterval) {
        transport.go(to: 0, over: duration, at: now, shape: .equalPower)
        cancel(&rotationTimer)
        cancel(&fadeOutTimer)
        fadeOutTimer = scheduler.schedule(after: duration) { [weak self] in
            guard let self else { return }
            self.fadeOutTimer = nil
            self.finishFadeOut(at: self.scheduler.now)
        }
        pushGains()
    }

    private func finishFadeOut(at now: TimeInterval) {
        guard transport.target == 0 else { return }
        if crossfader.isMoving(at: now) {
            crossfader.snap(to: crossfader.targetDeck, at: now)
        }
        cancel(&crossfadeTimer)
        let target = crossfader.targetDeck
        stopDeck(target, at: now, clear: false)
        stopDeck(target.other, at: now, clear: true)
        if decksStale || bookID == nil {
            clearDecks(at: now)
        }
        // A change that was waiting for a bar line or a crossfade happens silently now.
        if let request = pendingStart ?? queued, bookID != nil {
            applySilently(request, at: now)
        }
        pendingStart = nil
        queued = nil
        cancel(&barTimer)
        ducker.reset(at: now)
        cancel(&engineStopTimer)
        engineStopTimer = scheduler.schedule(after: config.stopEngineAfterPause) { [weak self] in
            self?.stopEngineWhileIdle()
        }
        pushGains()
        if shouldPlay {
            // A new book opened while the old one faded out.
            updateTransport(at: now)
        }
    }

    private func stopEngineWhileIdle() {
        engineStopTimer = nil
        guard transport.target == 0, fadeOutTimer == nil, backend.isEngineRunning else { return }
        let now = scheduler.now
        for deck in Deck.allCases {
            stopDeck(deck, at: now, clear: false)
        }
        backend.stopEngine()
        emit(.engineStopped)
    }

    private func scheduleEngineRetry() {
        guard retryTimer == nil, engineRetries < config.engineRetryLimit else { return }
        engineRetries += 1
        retryTimer = scheduler.schedule(after: config.engineRetryDelay) { [weak self] in
            guard let self else { return }
            self.retryTimer = nil
            self.updateTransport(at: self.scheduler.now)
        }
    }

    private func closeBookNow(at now: TimeInterval) {
        bookID = nil
        director.reset()
        pendingStart = nil
        queued = nil
        for timer in [barTimer, directorTimer, gapTimer, graceTimer] {
            timer?.cancel()
        }
        barTimer = nil
        directorTimer = nil
        gapTimer = nil
        graceTimer = nil
        ducker.reset(at: now)
        decksStale = true
        if transport.target > 0 {
            beginFadeOut(over: config.fadeOut, at: now)
        } else if fadeOutTimer == nil {
            clearDecks(at: now)
        }
    }

    // MARK: - Mood changes

    private func handle(_ decision: MoodDecision?, at now: TimeInterval) {
        if let decision {
            onDecision?(decision)
            emit(.moodChanged(decision))
            request(MusicRequest(mood: decision.bucket, transition: MusicTransition(decision.transition)), at: now)
        }
        armDirectorTimer(at: now)
    }

    private func armDirectorTimer(at now: TimeInterval) {
        cancel(&directorTimer)
        guard let deadline = director.nextDeadline else { return }
        directorTimer = scheduler.schedule(after: max(0, deadline - now)) { [weak self] in
            guard let self else { return }
            self.directorTimer = nil
            self.handle(self.director.tick(), at: self.scheduler.now)
        }
    }

    /// Moves the music to `request.mood`, choosing how from the current state.
    private func request(_ request: MusicRequest, at now: TimeInterval) {
        guard bookID != nil else { return }
        let target = crossfader.targetDeck
        let audible = transport.target > 0 && decks[target].isRunning
        guard audible else {
            if fadeOutTimer != nil {
                // Fading out: switch once silent.
                queued = request
                pendingStart = nil
            } else {
                applySilently(request, at: now)
            }
            return
        }
        if crossfader.isMoving(at: now) {
            // A crossfade already brings in a fresh track, so a rotation has nothing to do.
            guard request.transition != .rotation else { return }
            if decks[target].mood == request.mood {
                queued = nil
                return
            }
            if decks[target.other].mood == request.mood, decks[target.other].isRunning {
                // Heading back where we came from: reverse the crossfade.
                queued = nil
                crossfader.move(
                    toward: target.other,
                    fullDuration: config.crossfadeDuration(for: request.transition),
                    at: now
                )
                scheduleCrossfadeEnd(at: now)
                emit(.crossfadeReversed(toward: target.other))
                pushGains()
                return
            }
            queued = request
            pendingStart = nil
            // A mood change should not wait behind a slow fade: a rotation between two
            // tracks of the old mood, or any fade when the change is a quick one (a seek or
            // a big jump), finishes at the quick speed instead.
            let rotating = decks[target].mood == decks[target.other].mood
            if rotating || request.transition == .quick {
                var hurried = crossfader
                hurried.move(toward: target, fullDuration: config.quickCrossfade, at: now)
                if hurried.endTime < crossfader.endTime - 1e-6 {
                    crossfader = hurried
                    scheduleCrossfadeEnd(at: now)
                    pushGains()
                }
            }
            return
        }
        if request.transition != .rotation, decks[target].mood == request.mood {
            pendingStart = nil
            cancel(&barTimer)
            return
        }
        pendingStart = request
        queued = nil
        cancel(&barTimer)
        let delay = request.transition == .rotation ? 0 : barDelay(at: now)
        if delay <= 0.001 {
            beginCrossfade(at: now)
        } else {
            barTimer = scheduler.schedule(after: delay) { [weak self] in
                guard let self else { return }
                self.barTimer = nil
                self.beginCrossfade(at: self.scheduler.now)
            }
        }
    }

    /// Seconds to the outgoing track's next bar line, or 0 to start now.
    private func barDelay(at now: TimeInterval) -> TimeInterval {
        guard config.alignToBars else { return 0 }
        let deck = crossfader.targetDeck
        guard decks[deck].isRunning, let grid = decks[deck].grid else { return 0 }
        let delay = grid.delayToNextBar(from: position(of: deck, at: now))
        return delay <= config.maxBarWait ? delay : 0
    }

    private func beginCrossfade(at now: TimeInterval) {
        guard let request = pendingStart else { return }
        pendingStart = nil
        let outgoing = crossfader.targetDeck
        guard transport.target > 0, decks[outgoing].isRunning, !crossfader.isMoving(at: now) else {
            // Things changed while waiting for the bar line; decide again.
            self.request(request, at: now)
            return
        }
        let incoming = outgoing.other
        stopDeck(incoming, at: now, clear: true)
        guard load(request.mood, on: incoming, avoiding: decks[outgoing].track?.id) else { return }
        startDeck(incoming, from: 0, at: now)
        var duration = config.crossfadeDuration(for: request.transition)
        if request.transition == .rotation, decks[outgoing].duration > 0 {
            let remaining = decks[outgoing].duration - position(of: outgoing, at: now)
            duration = min(duration, max(1, remaining))
        }
        crossfader.move(toward: incoming, fullDuration: duration, at: now)
        scheduleCrossfadeEnd(at: now)
        cancel(&rotationTimer)
        emit(.crossfadeStarted(
            from: decks[outgoing].track?.id,
            to: decks[incoming].track?.id ?? "",
            transition: request.transition,
            duration: duration
        ))
        pushGains()
    }

    private func scheduleCrossfadeEnd(at now: TimeInterval) {
        cancel(&crossfadeTimer)
        crossfadeTimer = scheduler.schedule(after: max(0, crossfader.endTime - now)) { [weak self] in
            guard let self else { return }
            self.crossfadeTimer = nil
            self.finishCrossfade(at: self.scheduler.now)
        }
    }

    private func finishCrossfade(at now: TimeInterval) {
        guard !crossfader.isMoving(at: now) else {
            scheduleCrossfadeEnd(at: now)
            return
        }
        let target = crossfader.targetDeck
        stopDeck(target.other, at: now, clear: true)
        emit(.crossfadeFinished(deck: target))
        if let next = queued {
            queued = nil
            request(next, at: now)
        }
        armRotation(at: now)
        pushGains()
    }

    /// Switches without a crossfade, because nothing is audible.
    private func applySilently(_ request: MusicRequest, at now: TimeInterval) {
        let target = crossfader.targetDeck
        if crossfader.isMoving(at: now) {
            crossfader.snap(to: target, at: now)
            cancel(&crossfadeTimer)
        }
        stopDeck(target.other, at: now, clear: true)
        if request.transition != .rotation, decks[target].mood == request.mood {
            return
        }
        let previous = decks[target].track?.id
        stopDeck(target, at: now, clear: true)
        load(request.mood, on: target, avoiding: previous)
    }

    // MARK: - Track rotation

    private func armRotation(at now: TimeInterval) {
        cancel(&rotationTimer)
        guard transport.target > 0, !crossfader.isMoving(at: now) else { return }
        let deck = crossfader.targetDeck
        let slot = decks[deck]
        guard slot.isRunning, slot.duration > 0 else { return }
        let fade = min(config.rotationCrossfade, slot.duration / 3)
        var startAt = slot.duration - fade
        if config.alignToBars, let grid = slot.grid {
            startAt = grid.barLine(atOrBefore: startAt)
        }
        let delay = max(0, startAt - position(of: deck, at: now))
        rotationTimer = scheduler.schedule(after: delay) { [weak self] in
            guard let self else { return }
            self.rotationTimer = nil
            let now = self.scheduler.now
            guard self.transport.target > 0, !self.crossfader.isMoving(at: now), self.pendingStart == nil,
                  let mood = self.decks[self.crossfader.targetDeck].mood
            else { return }
            self.request(MusicRequest(mood: mood, transition: .rotation), at: now)
        }
    }

    private func deckFinished(_ deck: Deck, at now: TimeInterval) {
        guard decks[deck].isRunning else { return }
        decks[deck].isRunning = false
        decks[deck].resumeAt = 0
        guard deck == crossfader.targetDeck, transport.target > 0, !crossfader.isMoving(at: now),
              let mood = decks[deck].mood
        else { return }
        // The track ran out before its rotation (its duration was off): bring in the next one now.
        let previous = decks[deck].track?.id
        stopDeck(deck, at: now, clear: true)
        guard load(mood, on: deck, avoiding: previous) else { return }
        startDeck(deck, from: 0, at: now)
        transport.jump(to: 0, at: now)
        transport.go(to: 1, over: config.quickCrossfade / 2, at: now, shape: .equalPower)
        armRotation(at: now)
        pushGains()
    }

    // MARK: - Ducking

    private func armGapTimer(at now: TimeInterval) {
        cancel(&gapTimer)
        guard transport.target > 0, let due = ducker.gapCheckTime(settings: config.ducking) else { return }
        gapTimer = scheduler.schedule(after: max(0, due - now)) { [weak self] in
            guard let self else { return }
            self.gapTimer = nil
            self.ducker.checkGap(at: self.scheduler.now, settings: self.config.ducking)
            self.pushGains()
        }
    }

    // MARK: - Engine events

    private func restart(after reason: BackendRestartReason) {
        let now = scheduler.now
        for deck in Deck.allCases where decks[deck].isRunning {
            markStopped(deck, at: now)
        }
        if reason == .mediaServicesReset {
            // Every audio object is gone: rebuild the graph and reopen the decks' files.
            backend.rebuild()
            for deck in Deck.allCases {
                guard let track = decks[deck].track else { continue }
                do {
                    _ = try backend.load(library.url(for: track), on: deck)
                } catch {
                    report(LofiAudioError.loadFailed(trackID: track.id, reason: "\(error)").description)
                    decks[deck] = DeckSlot()
                }
            }
        }
        emit(.engineRestarting(reason))
        guard transport.target > 0 else { return }
        do {
            try backend.startEngine()
        } catch {
            report("The audio engine would not restart: \(error)")
            transport.jump(to: 0, at: now)
            scheduleEngineRetry()
            pushGains()
            return
        }
        let target = crossfader.targetDeck
        let moving = crossfader.isMoving(at: now)
        for deck in Deck.allCases where decks[deck].track != nil && (deck == target || moving) {
            startDeck(deck, from: decks[deck].resumeAt, at: now)
        }
        // A short fade-in hides the restart.
        transport.jump(to: 0, at: now)
        transport.go(to: 1, over: 0.5, at: now, shape: .equalPower)
        armRotation(at: now)
        pushGains()
    }

    private func routeChanged(_ route: OutputRoute, previousOutputLost: Bool) {
        let now = scheduler.now
        routeMuted = config.mutedRoutes.contains(route)
        if previousOutputLost, transport.target > 0 {
            // Headphones pulled: the narrator pauses itself, and the music must not carry on
            // through the speaker. It comes back with the narrator's next play.
            narrating = false
            director.setNarrationPlaying(false)
            cancel(&graceTimer)
            beginFadeOut(over: config.routeLossFadeOut, at: now)
        } else {
            updateTransport(at: now)
        }
        emit(.routeChanged(route))
    }

    // MARK: - Decks

    @discardableResult
    private func load(_ mood: MoodBucket, on deck: Deck, avoiding: String? = nil) -> Bool {
        for bucket in library.fallbackOrder(for: mood) {
            var candidates = library.tracks(in: bucket).filter { !failedTracks.contains($0.id) }
            while let track = rotation.pick(from: candidates, playing: avoiding) {
                do {
                    let duration = try backend.load(library.url(for: track), on: deck)
                    rotation.notePlayed(track.id)
                    var slot = DeckSlot()
                    slot.track = track
                    slot.mood = mood
                    slot.duration = duration > 0 ? duration : (track.duration ?? 0)
                    slot.bedGain = config.ducking.bedGain(forTrackLoudness: library.loudness(of: track))
                    slot.grid = track.barGrid
                    decks[deck] = slot
                    if bucket != mood {
                        emit(.fallback(requested: mood, used: bucket))
                    }
                    return true
                } catch {
                    failedTracks.insert(track.id)
                    report(LofiAudioError.loadFailed(trackID: track.id, reason: "\(error)").description)
                    candidates.removeAll { $0.id == track.id }
                }
            }
        }
        report(LofiAudioError.emptyLibrary.description)
        return false
    }

    private func startDeck(_ deck: Deck, from offset: TimeInterval, at now: TimeInterval) {
        var slot = decks[deck]
        guard let track = slot.track else { return }
        let start = (slot.duration > 0 && offset >= slot.duration - 0.25) ? 0 : max(0, offset)
        backend.setGain(0, for: deck)
        do {
            try backend.play(deck, from: start)
        } catch {
            report("Deck \(deck) would not play \(track.id): \(error)")
            return
        }
        slot.isRunning = true
        slot.startedAt = now
        slot.startOffset = start
        slot.resumeAt = start
        decks[deck] = slot
        emit(.trackStarted(trackID: track.id, mood: slot.mood ?? track.bucket, deck: deck, offset: start))
    }

    private func stopDeck(_ deck: Deck, at now: TimeInterval, clear: Bool) {
        if decks[deck].isRunning {
            let position = self.position(of: deck, at: now)
            backend.stop(deck)
            markStopped(deck, at: now, resumeAt: position)
        }
        if clear {
            decks[deck] = DeckSlot()
            backend.setGain(0, for: deck)
        }
    }

    private func markStopped(_ deck: Deck, at now: TimeInterval, resumeAt: TimeInterval? = nil) {
        decks[deck].resumeAt = resumeAt ?? decks[deck].estimatedPosition(at: now)
        decks[deck].isRunning = false
    }

    private func clearDecks(at now: TimeInterval) {
        for deck in Deck.allCases {
            stopDeck(deck, at: now, clear: true)
        }
        crossfader.snap(to: .a, at: now)
        cancel(&crossfadeTimer)
        cancel(&rotationTimer)
        decksStale = false
    }

    private func position(of deck: Deck, at now: TimeInterval) -> TimeInterval {
        backend.position(of: deck) ?? decks[deck].estimatedPosition(at: now)
    }

    // MARK: - Gains

    /// Sends both decks their gains: crossfade × bed level × transport fade × silence lift ×
    /// music volume. While anything is moving, a ticker repeats this at ``ScoreConfig/gainUpdateRate``.
    private func pushGains() {
        let now = scheduler.now
        let master = transport.value(at: now)
            * Gain.linear(fromDB: ducker.offsetDB(at: now))
            * min(1, max(0, config.musicVolume))
        for deck in Deck.allCases {
            let slot = decks[deck]
            let gain = slot.track == nil ? 0 : crossfader.gain(of: deck, at: now) * slot.bedGain * master
            backend.setGain(Float(min(1, max(0, gain))), for: deck)
        }
        if transport.isRunning(at: now) || crossfader.isMoving(at: now) || ducker.isRamping(at: now) {
            if ticker == nil {
                let interval = 1 / max(30, config.gainUpdateRate)
                ticker = scheduler.scheduleRepeating(every: interval) { [weak self] in
                    self?.pushGains()
                }
            }
        } else {
            cancel(&ticker)
        }
    }

    // MARK: - Reporting

    private func emit(_ event: PlayerEvent) {
        onEvent?(event)
    }

    private func report(_ message: String) {
        lastError = message
        emit(.error(message))
    }

    private func cancel(_ timer: inout LofiCancellable?) {
        timer?.cancel()
        timer = nil
    }

    private func makeSnapshot() -> PlayerSnapshot {
        let now = scheduler.now
        let deckStates = Deck.allCases.map { deck -> PlayerSnapshot.DeckState in
            let slot = decks[deck]
            return PlayerSnapshot.DeckState(
                deck: deck,
                trackID: slot.track?.id,
                trackBucket: slot.track?.bucket,
                mood: slot.mood,
                crossfadeGain: crossfader.gain(of: deck, at: now),
                bedGain: slot.bedGain,
                position: slot.track == nil ? nil : position(of: deck, at: now),
                duration: slot.duration,
                isRunning: slot.isRunning
            )
        }
        return PlayerSnapshot(
            time: now,
            bookID: bookID,
            enabled: enabled,
            narrating: narrating,
            routeMuted: routeMuted,
            engineRunning: backend.isEngineRunning,
            musicMood: decks[crossfader.targetDeck].mood,
            activeDeck: crossfader.targetDeck,
            crossfadePosition: crossfader.position(at: now),
            isCrossfading: crossfader.isMoving(at: now),
            transportGain: transport.value(at: now),
            duckOffsetDB: ducker.offsetDB(at: now),
            pendingMood: (pendingStart ?? queued)?.mood,
            decks: deckStates,
            director: director.snapshot,
            recentDecisions: director.recentDecisions,
            lastError: lastError
        )
    }
}

extension LofiScorePlayer: LofiAudioBackendDelegate {
    public func audioBackend(_ backend: LofiAudioBackend, deckDidFinish deck: Deck) {
        scheduler.perform { [weak self] in
            guard let self else { return }
            self.deckFinished(deck, at: self.scheduler.now)
        }
    }

    public func audioBackend(_ backend: LofiAudioBackend, needsRestart reason: BackendRestartReason) {
        scheduler.perform { [weak self] in
            self?.restart(after: reason)
        }
    }

    public func audioBackend(_ backend: LofiAudioBackend, routeDidChange route: OutputRoute, previousOutputLost: Bool) {
        scheduler.perform { [weak self] in
            self?.routeChanged(route, previousOutputLost: previousOutputLost)
        }
    }
}

/// A request to move the music to a mood.
struct MusicRequest: Hashable {
    var mood: MoodBucket
    var transition: MusicTransition
}

/// What one deck holds.
struct DeckSlot: Hashable {
    var track: LibraryTrack?
    /// The mood this deck stands for (its track may come from a fallback bucket).
    var mood: MoodBucket?
    var duration: TimeInterval = 0
    var bedGain: Double = 0
    var grid: BarGrid?
    var isRunning = false
    var startedAt: TimeInterval = 0
    var startOffset: TimeInterval = 0
    /// Where to continue from when the deck starts again.
    var resumeAt: TimeInterval = 0

    func estimatedPosition(at time: TimeInterval) -> TimeInterval {
        isRunning ? startOffset + max(0, time - startedAt) : resumeAt
    }
}

struct DeckPair: Hashable {
    var a = DeckSlot()
    var b = DeckSlot()

    subscript(deck: Deck) -> DeckSlot {
        get { deck == .a ? a : b }
        set {
            if deck == .a { a = newValue } else { b = newValue }
        }
    }
}
