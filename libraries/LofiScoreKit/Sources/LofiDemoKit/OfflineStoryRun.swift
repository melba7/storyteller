import Foundation
import LofiAudio
import LofiDirector
import LofiScoreCore

/// A sentence the narrator spoke during an offline run.
public struct SpokenClip: Sendable, Hashable {
    public var globalIndex: Int
    public var text: String
    /// Seconds from the start of the run.
    public var start: TimeInterval
    public var duration: TimeInterval

    public init(globalIndex: Int, text: String, start: TimeInterval, duration: TimeInterval) {
        self.globalIndex = globalIndex
        self.text = text
        self.start = start
        self.duration = duration
    }
}

/// A "speaker" for a manual clock: every sentence lasts as long as its rendered voice, and
/// each one is written down so the voice can be placed in the mix afterwards.
public final class TimelineSpeaker: SentenceSpeaker {
    public private(set) var clips: [SpokenClip] = []

    private let scheduler: ManualScheduler
    private let duration: (String) -> TimeInterval
    private let currentIndex: () -> Int
    private var pending: LofiCancellable?

    public init(scheduler: ManualScheduler, currentIndex: @escaping () -> Int, duration: @escaping (String) -> TimeInterval) {
        self.scheduler = scheduler
        self.currentIndex = currentIndex
        self.duration = duration
    }

    /// `rate` is ignored: the voice was rendered at its own speed.
    public func speak(_ text: String, rate: Double, completion: @escaping () -> Void) {
        stop()
        let length = max(0.05, duration(text))
        clips.append(SpokenClip(globalIndex: currentIndex(), text: text, start: scheduler.now, duration: length))
        pending = scheduler.schedule(after: length) { [weak self] in
            self?.pending = nil
            completion()
        }
    }

    public func stop() {
        guard let pending else { return }
        pending.cancel()
        self.pending = nil
        // Cut short: the clip ends now.
        if var last = clips.popLast() {
            last.duration = max(0, scheduler.now - last.start)
            clips.append(last)
        }
    }
}

/// Holds an audio backend's callbacks until the run's own thread asks for them.
///
/// A real engine reports a finished deck from its render thread. In an offline run the
/// player lives on a ``ManualScheduler``, which runs actions on the calling thread, so the
/// callbacks are queued here and delivered between render steps instead.
public final class DeferredBackendEvents: LofiAudioBackendDelegate {
    public weak var target: LofiAudioBackendDelegate?
    private var queue: [(LofiAudioBackendDelegate, LofiAudioBackend) -> Void] = []
    private weak var backend: LofiAudioBackend?
    private let lock = NSLock()

    public init(target: LofiAudioBackendDelegate?, backend: LofiAudioBackend) {
        self.target = target
        self.backend = backend
    }

    public func audioBackend(_ backend: LofiAudioBackend, deckDidFinish deck: Deck) {
        enqueue { $0.audioBackend($1, deckDidFinish: deck) }
    }

    public func audioBackend(_ backend: LofiAudioBackend, needsRestart reason: BackendRestartReason) {
        enqueue { $0.audioBackend($1, needsRestart: reason) }
    }

    public func audioBackend(_ backend: LofiAudioBackend, routeDidChange route: OutputRoute, previousOutputLost: Bool) {
        enqueue { $0.audioBackend($1, routeDidChange: route, previousOutputLost: previousOutputLost) }
    }

    /// Delivers everything queued so far, in order.
    public func drain() {
        lock.lock()
        let pending = queue
        queue.removeAll()
        lock.unlock()
        guard let target, let backend else { return }
        for call in pending {
            call(target, backend)
        }
    }

    private func enqueue(_ call: @escaping (LofiAudioBackendDelegate, LofiAudioBackend) -> Void) {
        lock.lock()
        queue.append(call)
        lock.unlock()
    }
}

/// Plays the demo story through the real player on a manual clock, as fast as the backend
/// can render, and records what happened: when each sentence was spoken, every reading,
/// every music decision and player event.
///
/// `lofi-render` uses it with an offline `AVAudioEngineBackend` to write the story, read
/// aloud with the music underneath, to an audio file. The tests use it with
/// ``FakeAudioBackend``.
public final class OfflineStoryRun {
    public struct Options: Sendable {
        /// Silence before the narrator starts.
        public var leadIn: TimeInterval = 1
        /// Kept after the last sentence, so the music can fade out.
        public var tail: TimeInterval = 4
        /// Render step: the clock moves this far, then the backend renders this much.
        public var step: TimeInterval = 0.01
        public var narrator = StoryNarrator.Settings()
        /// Gives up after this long, in case something never ends.
        public var maximumDuration: TimeInterval = 4 * 3600

        public init() {}
    }

    public struct TimedReading: Sendable {
        public var time: TimeInterval
        public var observation: MoodObservation
    }

    public struct TimedDecision: Sendable {
        public var time: TimeInterval
        public var decision: MoodDecision
    }

    public struct TimedEvent: Sendable {
        public var time: TimeInterval
        public var event: PlayerEvent
    }

    public struct Report: Sendable {
        public var clips: [SpokenClip]
        public var readings: [TimedReading]
        public var decisions: [TimedDecision]
        public var events: [TimedEvent]
        /// Length of the whole run, lead-in and tail included.
        public var duration: TimeInterval
        /// False when the run hit ``Options/maximumDuration`` first.
        public var finished: Bool
    }

    public let story: DemoStory
    public let scheduler: ManualScheduler
    public let player: LofiScorePlayer
    public let narrator: StoryNarrator
    public let speaker: TimelineSpeaker
    public let options: Options

    private let backend: LofiAudioBackend
    private let relay: DeferredBackendEvents
    private var readings: [TimedReading] = []
    private var decisions: [TimedDecision] = []
    private var events: [TimedEvent] = []

    /// - Parameters:
    ///   - voiceDuration: how long the rendered voice of a sentence lasts, in seconds.
    ///   - scheduler: the clock the backend also reads, if it needs one (``FakeAudioBackend``).
    public init(
        story: DemoStory = .greenLantern,
        library: MusicLibrary,
        backend: LofiAudioBackend,
        config: ScoreConfig,
        moodSource: ScriptedMoodSource = ScriptedMoodSource(),
        scheduler: ManualScheduler = ManualScheduler(),
        options: Options = Options(),
        rotationSeed: UInt64? = 1,
        voiceDuration: @escaping (String) -> TimeInterval
    ) {
        self.story = story
        self.scheduler = scheduler
        self.backend = backend
        self.options = options
        let player = LofiScorePlayer(
            library: library,
            backend: backend,
            scheduler: scheduler,
            config: config,
            rotationSeed: rotationSeed
        )
        self.player = player
        relay = DeferredBackendEvents(target: player, backend: backend)
        backend.delegate = relay

        let narrator = StoryNarrator(story: story, player: player, scheduler: scheduler, moodSource: moodSource)
        narrator.settings = options.narrator
        self.narrator = narrator
        speaker = TimelineSpeaker(
            scheduler: scheduler,
            currentIndex: { [unowned narrator] in narrator.index },
            duration: voiceDuration
        )
        narrator.speaker = speaker

        narrator.onReading = { [unowned self] observation in
            self.readings.append(TimedReading(time: self.scheduler.now, observation: observation))
        }
        player.onDecision = { [unowned self] decision in
            self.decisions.append(TimedDecision(time: self.scheduler.now, decision: decision))
        }
        player.onEvent = { [unowned self] event in
            self.events.append(TimedEvent(time: self.scheduler.now, event: event))
        }
    }

    /// Runs the story from the first sentence to the end.
    ///
    /// For every step the clock first moves to the step's start (so the player has set its
    /// gains and started its decks), then `render` is asked for `step` seconds of music
    /// starting there. Steps are contiguous and cover the whole report duration.
    @discardableResult
    public func run(render: (_ start: TimeInterval, _ duration: TimeInterval) throws -> Void) rethrows -> Report {
        let step = max(0.001, options.step)
        let origin = scheduler.now
        var time = origin
        var endAt: TimeInterval?
        var started = false
        var finished = false
        narrator.openBook()

        while true {
            scheduler.advance(to: time)
            relay.drain()
            if !started, time - origin >= options.leadIn - 1e-9 {
                started = true
                narrator.play()
            }
            if started, endAt == nil, narrator.isFinished {
                endAt = time + options.tail
            }
            if let endAt, time >= endAt - 1e-9 {
                finished = true
                break
            }
            if time - origin >= options.maximumDuration {
                break
            }
            try render(time - origin, step)
            time += step
        }
        narrator.closeBook()
        relay.drain()
        return Report(
            clips: speaker.clips.map { clip in
                var shifted = clip
                shifted.start -= origin
                return shifted
            },
            readings: readings.map { TimedReading(time: $0.time - origin, observation: $0.observation) },
            decisions: decisions.map { TimedDecision(time: $0.time - origin, decision: $0.decision) },
            events: events.map { TimedEvent(time: $0.time - origin, event: $0.event) },
            duration: time - origin,
            finished: finished
        )
    }
}
