import Foundation
import LofiAudio
import LofiMood
import LofiScoreCore
import LofiText

/// What the follower drives. ``LofiScorePlayer`` is the real one; tests record the calls.
public protocol NarrationMusicSink: AnyObject {
    func openBook(id: String)
    func closeBook()
    func narratorDidPlay()
    func narratorDidPause()
    func narratorDidSeek(toGlobalSentenceIndex index: Int?)
    func sentenceDidStart(globalSentenceIndex: Int?, duration: TimeInterval?)
    func receive(_ observation: MoodObservation)
}

extension LofiScorePlayer: NarrationMusicSink {}

/// One media-overlay clip as the app's audiobook player reports it: the sentence's element in
/// its content document, and where its audio sits in which file.
public struct NarratorClip: Sendable, Hashable {
    /// The content document, as the player reports it (Readium `OverlayPar.textResource`).
    public var textResource: String
    /// The sentence element's id.
    public var fragmentId: String
    /// The audio file, relative to the book (Readium `OverlayPar.relativeUrl`).
    public var audioResource: String
    /// Start and end of the clip in that file, in seconds of audio.
    public var start: Double
    public var end: Double

    public init(textResource: String, fragmentId: String, audioResource: String, start: Double, end: Double) {
        self.textResource = textResource
        self.fragmentId = fragmentId
        self.audioResource = audioResource
        self.start = start
        self.end = end
    }
}

/// The text side of one open book: the guard that maps clips to sentences (and never reads
/// past the one being narrated) and the tracker that turns them into mood readings.
public struct BookText: Sendable {
    public let spoilerGuard: SpoilerGuard
    public let tracker: MoodTracker
    /// The engine's id, for the status screen.
    public let engineID: String

    /// - Parameter cadence: how often to take a reading; nil leaves it to the tracker,
    ///   which picks one to suit the engine.
    public init(
        spoilerGuard: SpoilerGuard,
        engine: any MoodEngine,
        cadence: ReadingCadence.Configuration? = nil,
        clock: @escaping @Sendable () -> Double = MoodTracker.uptimeSeconds
    ) {
        self.spoilerGuard = spoilerGuard
        if let cadence {
            tracker = MoodTracker(spoilerGuard: spoilerGuard, engine: engine, cadence: cadence, clock: clock)
        } else {
            tracker = MoodTracker(spoilerGuard: spoilerGuard, engine: engine, clock: clock)
        }
        engineID = engine.id
    }
}

/// Turns the app's narrator events into the music player's calls.
///
/// The audiobook player reports three things: a clip started (each sentence of a readaloud
/// book is a clip), playback started or stopped, and a book's track was loaded. From those
/// the follower works out what the music needs:
///
/// - which sentence is playing, through the book's ``SpoilerGuard``, so mood readings never
///   look past it;
/// - seeks: any jump backwards, or forwards by more than the reading cadence's step;
/// - how long each sentence lasts at the current speed, estimated from the clip times
///   (the speed itself is not reported), so the music can lift in long silences;
/// - real pauses, ignoring the brief stalls the player reports while it seeks or loads
///   the next file.
///
/// Mood readings run in order on one task, after the sentence they belong to has started,
/// and readings for a book that has since closed are dropped.
///
/// Thread safety: every method may be called from any thread. State lives on the
/// scheduler's context (one serial queue in the app).
public final class NarrationFollower: @unchecked Sendable {
    public struct Configuration: Sendable, Hashable {
        /// A stop shorter than this is a stall (seeking, loading the next file), not a pause.
        public var pauseDebounce: TimeInterval = 0.6
        /// After a pause this long, the next reading starts a new stretch.
        public var resetAfterPause: TimeInterval = 300
        /// A forward jump of more than this many sentences is a seek. Matches the reading
        /// cadence, so the director and the tracker agree on what a seek is.
        public var maxContinuousStep: Int = ReadingCadence.Configuration.default.maxContinuousStep
        /// A jump back of up to this many sentences (the app's automatic rewind after a
        /// pause, a skip-back button) replays what was just heard: the music keeps its mood
        /// and no reading is taken until the narration passes the furthest sentence again.
        public var rewindTolerance: Int = 8
        /// Plausible playback speeds; estimates outside are clamped.
        public var rateRange: ClosedRange<Double> = 0.5...3.5
        /// Weight of the newest speed estimate.
        public var rateSmoothing: Double = 0.35
        /// Ignore speed samples over less wall-clock time than this (timer jitter).
        public var minimumRateSample: TimeInterval = 1.0

        public init() {}
    }

    /// What the follower knows, for the settings screen and tests.
    public struct Status: Sendable, Hashable {
        public var bookID: String?
        /// The book's text is open and readings are flowing.
        public var hasText: Bool
        public var engineID: String?
        public var isNarrating: Bool
        public var position: SentencePosition?
        public var estimatedRate: Double
        /// Clips that did not match a narrated sentence (front matter, audio-only parts).
        public var unmatchedClips: Int
        public var readingsDelivered: Int
    }

    private enum Job {
        case reading(MoodTracker, SentencePosition, isSeek: Bool, generation: Int)
        case reset(MoodTracker)
    }

    public let configuration: Configuration
    private let scheduler: LofiScheduler
    private let jobs: AsyncStream<Job>.Continuation
    private var consumer: Task<Void, Never>?

    // State on the scheduler's context.
    private var sink: NarrationMusicSink?
    private var bookID: String?
    private var text: BookText?
    /// The latest clip that arrived before the book's text was ready.
    private var waitingClip: (clip: NarratorClip, audioTime: Double?)?
    private var narrating = false
    private var pauseTimer: LofiCancellable?
    private var pausedAt: TimeInterval?
    private var position: SentencePosition?
    /// The furthest sentence narrated since the last seek.
    private var furthest: SentencePosition?
    /// The last clip start seen while playing steadily: (file, seconds into it, wall time).
    private var anchor: (audio: String, time: Double, wall: TimeInterval)?
    private var rate: Double = 1
    private var unmatchedClips = 0

    // Shared with the reading task.
    private let lock = NSLock()
    private var generation = 0
    private var outstanding = 0
    private var delivered = 0
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    public init(scheduler: LofiScheduler, configuration: Configuration = Configuration()) {
        self.scheduler = scheduler
        self.configuration = configuration
        let (stream, continuation) = AsyncStream<Job>.makeStream()
        jobs = continuation
        consumer = Task { [weak self] in
            for await job in stream {
                guard let self else { return }
                await self.run(job)
            }
        }
    }

    deinit {
        jobs.finish()
        consumer?.cancel()
        pauseTimer?.cancel()
    }

    // MARK: - The music player

    /// Sets (or replaces) the player. A new player is brought up to date: the open book,
    /// whether the narrator is playing, and a fresh reading for the current sentence.
    public func attach(_ newSink: NarrationMusicSink?) {
        scheduler.perform { [self] in
            if let old = sink, old !== newSink {
                // Let the old player fade out.
                old.narratorDidPause()
                old.closeBook()
            }
            sink = newSink
            guard let newSink else { return }
            if narrating { newSink.narratorDidPlay() }
            guard let bookID, let text else { return }
            newSink.openBook(id: bookID)
            if let position {
                newSink.narratorDidSeek(toGlobalSentenceIndex: position.globalIndex)
                newSink.sentenceDidStart(globalSentenceIndex: position.globalIndex, duration: nil)
                enqueueReading(text.tracker, position, isSeek: true)
            }
        }
    }

    // MARK: - Narrator events

    /// The narrator loaded a book (or the next file of the same book). Only a new `id`
    /// changes anything. The music stays off until ``attachText(_:toBook:)`` gives the
    /// book's text: music with nothing to follow would only be a guess.
    public func bookOpened(id: String) {
        scheduler.perform { [self] in
            guard id != bookID else { return }
            if bookID != nil, text != nil { sink?.closeBook() }
            bookID = id
            text = nil
            waitingClip = nil
            position = nil
            furthest = nil
            anchor = nil
            unmatchedClips = 0
            lock.withLock { generation += 1 }
        }
    }

    /// The narrator closed the book.
    public func bookClosed() {
        scheduler.perform { [self] in
            guard bookID != nil else { return }
            if text != nil { sink?.closeBook() }
            bookID = nil
            text = nil
            waitingClip = nil
            position = nil
            furthest = nil
            anchor = nil
            lock.withLock { generation += 1 }
        }
    }

    /// The book's text is ready. Ignored if the narrator has moved to another book since.
    public func attachText(_ bookText: BookText, toBook id: String) {
        scheduler.perform { [self] in
            guard id == bookID, text == nil else { return }
            text = bookText
            sink?.openBook(id: id)
            if let waiting = waitingClip {
                waitingClip = nil
                handle(waiting.clip, audioTime: waiting.audioTime)
            }
        }
    }

    public func playingChanged(_ isPlaying: Bool) {
        scheduler.perform { [self] in
            if isPlaying {
                pauseTimer?.cancel()
                pauseTimer = nil
                guard !narrating else { return }
                narrating = true
                anchor = nil
                if let pausedAt, scheduler.now - pausedAt >= configuration.resetAfterPause, let text {
                    enqueue(.reset(text.tracker))
                }
                pausedAt = nil
                // Forwarded even before the text is ready: the player only plays with a
                // book open, and it has to know the narrator's state when one opens.
                sink?.narratorDidPlay()
            } else {
                guard narrating, pauseTimer == nil else { return }
                pauseTimer = scheduler.schedule(after: configuration.pauseDebounce) { [weak self] in
                    self?.pauseNow()
                }
            }
        }
    }

    /// A clip started. `audioTime` is where in the clip playback is, when it did not start
    /// at the clip's beginning (resuming in the middle of a sentence).
    public func clipStarted(_ clip: NarratorClip, audioTime: Double? = nil) {
        scheduler.perform { [self] in
            guard bookID != nil else { return }
            guard text != nil else {
                waitingClip = (clip, audioTime)
                return
            }
            handle(clip, audioTime: audioTime)
        }
    }

    // MARK: - Status

    public func status(_ completion: @escaping (Status) -> Void) {
        scheduler.perform { [self] in
            completion(Status(
                bookID: bookID,
                hasText: text != nil,
                engineID: text?.engineID,
                isNarrating: narrating,
                position: position,
                estimatedRate: rate,
                unmatchedClips: unmatchedClips,
                readingsDelivered: lock.withLock { delivered }
            ))
        }
    }

    /// Waits until every reading queued so far has been delivered or dropped. For tests.
    public func waitUntilIdle() async {
        await withCheckedContinuation { continuation in
            let idle: Bool = lock.withLock {
                if outstanding == 0 { return true }
                idleWaiters.append(continuation)
                return false
            }
            if idle { continuation.resume() }
        }
    }

    // MARK: - Internals

    private func pauseNow() {
        pauseTimer = nil
        guard narrating else { return }
        narrating = false
        pausedAt = scheduler.now
        anchor = nil
        sink?.narratorDidPause()
    }

    private func handle(_ clip: NarratorClip, audioTime: Double?) {
        guard let text else { return }
        let now = scheduler.now
        let found: SentencePosition?
        do {
            found = try text.spoilerGuard.position(
                textResource: clip.textResource,
                fragmentId: clip.fragmentId,
                audioResource: clip.audioResource,
                clipBegin: clip.start
            )
        } catch {
            found = nil
        }
        guard let found else {
            // Front matter or audio the book's text does not cover: no reading, no seek.
            unmatchedClips += 1
            anchor = nil
            return
        }

        let previous = position
        let step = previous.map { found.globalIndex - $0.globalIndex }
        let isRewind = step.map { $0 < 0 && -$0 <= configuration.rewindTolerance } ?? false
        let isSeek = !isRewind && (step.map { $0 < 0 || $0 > configuration.maxContinuousStep } ?? false)
        let reached = furthest

        updateRate(clip: clip, audioTime: audioTime, isSeek: isSeek, at: now)

        if isSeek {
            sink?.narratorDidSeek(toGlobalSentenceIndex: found.globalIndex)
        }
        let from = max(clip.start, audioTime ?? clip.start)
        let remaining = max(0, clip.end - from) / rate
        sink?.sentenceDidStart(globalSentenceIndex: found.globalIndex, duration: remaining > 0 ? remaining : nil)

        position = found
        if isSeek || reached.map({ found > $0 }) ?? true {
            furthest = found
        }
        // No new reading for a gap clip that maps to the sentence already playing, a resume
        // inside it, or sentences being heard again after a short rewind.
        let isNew = isSeek || reached.map { found.globalIndex > $0.globalIndex } ?? true
        if found != previous, !isRewind, isNew {
            enqueueReading(text.tracker, found, isSeek: isSeek)
        }
    }

    private func updateRate(clip: NarratorClip, audioTime: Double?, isSeek: Bool, at now: TimeInterval) {
        let here = max(clip.start, audioTime ?? clip.start)
        defer { anchor = narrating ? (clip.audioResource, here, now) : nil }
        guard narrating, !isSeek, audioTime == nil, let anchor, anchor.audio == clip.audioResource else { return }
        let wall = now - anchor.wall
        let audio = clip.start - anchor.time
        guard wall >= configuration.minimumRateSample, audio > 0 else { return }
        let sample = min(configuration.rateRange.upperBound, max(configuration.rateRange.lowerBound, audio / wall))
        rate += (sample - rate) * configuration.rateSmoothing
    }

    private func enqueueReading(_ tracker: MoodTracker, _ position: SentencePosition, isSeek: Bool) {
        let current = lock.withLock { generation }
        enqueue(.reading(tracker, position, isSeek: isSeek, generation: current))
    }

    private func enqueue(_ job: Job) {
        lock.withLock { outstanding += 1 }
        jobs.yield(job)
    }

    private func run(_ job: Job) async {
        switch job {
        case let .reset(tracker):
            await tracker.reset()
        case let .reading(tracker, position, isSeek, jobGeneration):
            if let observation = await tracker.sentenceStarted(position, isSeek: isSeek) {
                deliver(observation, generation: jobGeneration)
            }
        }
        let waiters: [CheckedContinuation<Void, Never>] = lock.withLock {
            outstanding -= 1
            guard outstanding == 0 else { return [] }
            defer { idleWaiters.removeAll() }
            return idleWaiters
        }
        waiters.forEach { $0.resume() }
    }

    private func deliver(_ observation: MoodObservation, generation jobGeneration: Int) {
        scheduler.perform { [self] in
            // The book may have changed while the engine ran.
            guard lock.withLock({ generation }) == jobGeneration, text != nil else { return }
            lock.withLock { delivered += 1 }
            sink?.receive(observation)
        }
    }
}
