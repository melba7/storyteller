import Foundation
import LofiAudioCore
import LofiText

/// What the follower drives: the atmosphere player, or a recorder in tests.
public protocol NarrationSink: AnyObject {
    func openBook(id: String)
    func closeBook()
    func narratorDidPlay()
    func narratorDidPause()
    func narratorDidSeek(toGlobalSentenceIndex index: Int?)
    func sentenceDidStart(globalSentenceIndex: Int?, duration: TimeInterval?)
}

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

/// The text side of one open book: the guard that maps the narrator's clips to sentences and
/// never reads past the one being narrated. The atmosphere track's entries are matched to the
/// book through it, and nothing ahead of the narration is ever looked at.
public struct BookText: Sendable {
    public let spoilerGuard: SpoilerGuard

    public init(spoilerGuard: SpoilerGuard) {
        self.spoilerGuard = spoilerGuard
    }
}

/// Turns the app's narrator events into the atmosphere player's calls.
///
/// The audiobook player reports three things: a clip started (each sentence of a readaloud
/// book is a clip), playback started or stopped, and a book's track was loaded. From those
/// the follower works out what the sounds need:
///
/// - which sentence is playing, through the book's ``SpoilerGuard``, so the scene never
///   runs ahead of the voice;
/// - seeks: any jump backwards, or forwards by more than a sentence or two;
/// - how long each sentence lasts at the current speed, estimated from the clip times
///   (the speed itself is not reported), so the sounds can lift in long silences;
/// - real pauses, ignoring the brief stalls the player reports while it seeks or loads
///   the next file.
///
/// Thread safety: every method may be called from any thread. State lives on the
/// scheduler's context (one serial queue in the app).
public final class NarrationFollower: @unchecked Sendable {
    public struct Configuration: Sendable, Hashable {
        /// A stop shorter than this is a stall (seeking, loading the next file), not a pause.
        public var pauseDebounce: TimeInterval = 0.6
        /// A forward jump of more than this many sentences is a seek. One missed clip
        /// boundary (a gap clip, a sentence the overlay skips) is still steady narration.
        public var maxContinuousStep: Int = 2
        /// A jump back of up to this many sentences (the app's automatic rewind after a
        /// pause, a skip-back button) replays what was just heard: the scene stays as it is.
        public var rewindTolerance: Int = 8
        /// Plausible playback speeds; estimates outside are clamped.
        public var rateRange: ClosedRange<Double> = 0.5...3.5
        /// Weight of the newest speed estimate.
        public var rateSmoothing: Double = 0.35
        /// Ignore speed samples over less wall-clock time than this (timer jitter).
        public var minimumRateSample: TimeInterval = 1.0
        /// Reading on screen with the narrator stopped: a page turn of up to this many
        /// sentences either way is reading on (or paging back); a bigger one is a jump.
        public var readerMaxPageStep: Int = 150
        /// Reading on screen: after this long with no page turn, the sounds fade out.
        public var readerIdleTimeout: TimeInterval = 300

        public init() {}
    }

    /// What the follower knows, for the settings screen and tests.
    public struct Status: Sendable, Hashable {
        public var bookID: String?
        /// The book's text is open and the sentences are being followed.
        public var hasText: Bool
        public var isNarrating: Bool
        /// The listener is reading the text on screen with the narrator stopped, and the
        /// sounds follow the pages (``readerReached(_:)``).
        public var isReading: Bool = false
        public var position: SentencePosition?
        public var estimatedRate: Double
        /// Clips that did not match a narrated sentence (front matter, audio-only parts).
        public var unmatchedClips: Int
    }

    public let configuration: Configuration
    private let scheduler: LofiScheduler

    // State on the scheduler's context.
    private var sink: NarrationSink?
    private var bookID: String?
    private var text: BookText?
    /// The latest clip that arrived before the book's text was ready.
    private var waitingClip: (clip: NarratorClip, audioTime: Double?)?
    private var narrating = false
    /// Following the pages of a silent reader (``readerReached(_:)``).
    private var reading = false
    private var readerIdleTimer: LofiCancellable?
    private var pauseTimer: LofiCancellable?
    private var position: SentencePosition?
    /// The furthest sentence narrated since the last seek.
    private var furthest: SentencePosition?
    /// The last clip start seen while playing steadily: (file, seconds into it, wall time).
    private var anchor: (audio: String, time: Double, wall: TimeInterval)?
    private var rate: Double = 1
    private var unmatchedClips = 0

    public init(scheduler: LofiScheduler, configuration: Configuration = Configuration()) {
        self.scheduler = scheduler
        self.configuration = configuration
    }

    deinit {
        pauseTimer?.cancel()
        readerIdleTimer?.cancel()
    }

    // MARK: - The player

    /// Sets (or replaces) the player. The old one fades out; a new one is brought up to
    /// date: the open book, whether the narrator is playing, and where it is.
    public func attach(_ newSink: NarrationSink?) {
        scheduler.perform { [self] in
            if let old = sink, old !== newSink {
                old.narratorDidPause()
                old.closeBook()
            }
            sink = newSink
            guard let newSink else { return }
            if narrating || reading { newSink.narratorDidPlay() }
            guard let bookID, text != nil else { return }
            newSink.openBook(id: bookID)
            if let position {
                newSink.narratorDidSeek(toGlobalSentenceIndex: position.globalIndex)
                newSink.sentenceDidStart(globalSentenceIndex: position.globalIndex, duration: nil)
            }
        }
    }

    // MARK: - Narrator events

    /// The narrator loaded a book (or the next file of the same book). Only a new `id`
    /// changes anything. The sounds stay off until ``attachText(_:toBook:)`` gives the
    /// book's text: a scene with nothing to follow would only be a guess.
    public func bookOpened(id: String) {
        scheduler.perform { [self] in
            guard id != bookID else { return }
            stopReading()
            if bookID != nil, text != nil { sink?.closeBook() }
            bookID = id
            text = nil
            waitingClip = nil
            position = nil
            furthest = nil
            anchor = nil
            unmatchedClips = 0
        }
    }

    /// The narrator closed the book.
    public func bookClosed() {
        scheduler.perform { [self] in
            guard bookID != nil else { return }
            stopReading()
            if text != nil { sink?.closeBook() }
            bookID = nil
            text = nil
            waitingClip = nil
            position = nil
            furthest = nil
            anchor = nil
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

    /// The open book's text, read again (its score arrived, or the book was re-synced). The
    /// book stays open and the sounds play on; the sentences are matched through the new
    /// text from here.
    public func replaceText(_ bookText: BookText, toBook id: String) {
        scheduler.perform { [self] in
            guard id == bookID else { return }
            guard text != nil else {
                attachNow(bookText, toBook: id)
                return
            }
            text = bookText
        }
    }

    private func attachNow(_ bookText: BookText, toBook id: String) {
        text = bookText
        sink?.openBook(id: id)
        if let waiting = waitingClip {
            waitingClip = nil
            handle(waiting.clip, audioTime: waiting.audioTime)
        }
    }

    public func playingChanged(_ isPlaying: Bool) {
        scheduler.perform { [self] in
            if isPlaying {
                let wasPausing = pauseTimer != nil
                pauseTimer?.cancel()
                pauseTimer = nil
                if narrating {
                    // A pause too short to count, as far as the follower is concerned. The
                    // player may have stopped on its own in the meantime (headphones
                    // pulled: the narrator pauses itself and may be resumed at once), so
                    // the resume is passed on; it treats a repeated play as nothing new.
                    if wasPausing { sink?.narratorDidPlay() }
                    return
                }
                // The narrator takes over from the pages: the sounds carry on.
                readerIdleTimer?.cancel()
                readerIdleTimer = nil
                reading = false
                narrating = true
                anchor = nil
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

    // MARK: - Reading on screen

    /// The listener is reading the book's text on screen with the narrator stopped, and the
    /// page now begins with `clip`'s sentence (the app's own page-to-audio sync finds it).
    /// The sounds play as if the narrator were reading:
    ///
    /// - placed at the top of the page, never further into it, so nothing on the page the
    ///   listener has not reached yet can show in the sounds;
    /// - paging back keeps the scene, as a short rewind does; a jump of more than
    ///   ``Configuration/readerMaxPageStep`` sentences (the table of contents, a bookmark)
    ///   is a seek;
    /// - after ``Configuration/readerIdleTimeout`` without a page turn, or with
    ///   ``readerStopped()``, the sounds fade out as on a pause.
    ///
    /// Ignored while the narrator plays: it leads then.
    public func readerReached(_ clip: NarratorClip) {
        scheduler.perform { [self] in
            guard bookID != nil, let text, !narrating else { return }
            let found = try? text.spoilerGuard.position(
                textResource: clip.textResource,
                fragmentId: clip.fragmentId,
                audioResource: clip.audioResource,
                clipBegin: clip.start
            )
            guard let found else {
                unmatchedClips += 1
                return
            }
            if !reading {
                reading = true
                anchor = nil
                sink?.narratorDidPlay()
            }
            armReaderIdle()
            follow(page: found)
        }
    }

    /// The listener stopped reading on screen (left the book, or the app went to the
    /// background). The sounds fade out as on a pause.
    public func readerStopped() {
        scheduler.perform { [self] in
            stopReading()
        }
    }

    private func stopReading() {
        readerIdleTimer?.cancel()
        readerIdleTimer = nil
        guard reading else { return }
        reading = false
        if !narrating { sink?.narratorDidPause() }
    }

    private func armReaderIdle() {
        readerIdleTimer?.cancel()
        readerIdleTimer = scheduler.schedule(after: configuration.readerIdleTimeout) { [weak self] in
            self?.stopReading()
        }
    }

    private func follow(page found: SentencePosition) {
        let previous = position
        let step = previous.map { found.globalIndex - $0.globalIndex }
        guard let previous, let step, abs(step) <= configuration.readerMaxPageStep else {
            // The first page, or a jump: the scene is decided afresh from here.
            sink?.narratorDidSeek(toGlobalSentenceIndex: found.globalIndex)
            sink?.sentenceDidStart(globalSentenceIndex: found.globalIndex, duration: 0)
            position = found
            furthest = found
            return
        }
        guard step != 0 else { return }
        // No voice: a duration of 0 lets the sounds rise a little, as in a pause.
        sink?.sentenceDidStart(globalSentenceIndex: found.globalIndex, duration: 0)
        position = found
        let reached = max(previous, furthest ?? previous)
        if found > reached { furthest = found }
    }

    // MARK: - Status

    public func status(_ completion: @escaping (Status) -> Void) {
        scheduler.perform { [self] in
            completion(Status(
                bookID: bookID,
                hasText: text != nil,
                isNarrating: narrating,
                isReading: reading,
                position: position,
                estimatedRate: rate,
                unmatchedClips: unmatchedClips
            ))
        }
    }

    // MARK: - Internals

    private func pauseNow() {
        pauseTimer = nil
        guard narrating else { return }
        narrating = false
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
            // Front matter or audio the book's text does not cover: no seek.
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
}
