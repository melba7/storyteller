import Foundation
import LofiAudio
import LofiDirector
import LofiScoreCore

/// Something that can say a sentence out loud (text to speech in the app).
public protocol SentenceSpeaker: AnyObject {
    /// Speaks `text` and calls `completion` once, when it has finished. Not called after ``stop()``.
    func speak(_ text: String, rate: Double, completion: @escaping () -> Void)
    func stop()
}

/// A pretend narrator for the demo: it steps through the story sentence by sentence and
/// tells the player everything Storyteller's narrator would (play, pause, seek, sentence
/// starts), while a ``ScriptedMoodSource`` plays the part of the text side.
///
/// Pure logic on a ``LofiScheduler``: the app runs it on the main queue, the tests on a
/// manual clock together with the player.
public final class StoryNarrator {
    public struct Settings: Sendable, Hashable {
        /// Narration speed. The music never follows it.
        public var rate = 1.0
        /// Speaking time per word at rate 1, when no speaker is attached.
        public var secondsPerWord = 0.36
        public var sentencePause = 0.3
        /// The pause after a paragraph: long enough for the music to rise a little.
        public var paragraphPause = 2.6
        /// How long the pretend engine takes to produce a reading after play or a seek.
        public var readingDelay = 0.4
        /// Sentences between regular readings. nil: the mood source's own cadence (every
        /// sentence for a mood track, every other sentence for live readings).
        public var readingCadence: Int?
        /// A new chapter's first reading comes this many sentences in.
        public var chapterStartDelay = 2

        public init() {}
    }

    public let story: DemoStory
    public private(set) var index = 0
    public private(set) var isPlaying = false
    public private(set) var isBookOpen = false
    public private(set) var isFinished = false
    public var settings = Settings()
    public var speaker: SentenceSpeaker?
    public var moodSource: ScriptedMoodSource
    /// Called after any change worth redrawing.
    public var onChange: (() -> Void)?
    public var onReading: ((MoodObservation) -> Void)?
    /// Called just before the player hears that the narrator started playing, so the host
    /// can activate its audio session first.
    public var willStartPlaying: (() -> Void)?

    private let player: LofiScorePlayer
    private let scheduler: LofiScheduler
    private var generation = 0
    private var stepTimer: LofiCancellable?
    private var readingTimer: LofiCancellable?
    private var sleepTimer: LofiCancellable?
    private var lastReadingIndex: Int?

    public init(story: DemoStory, player: LofiScorePlayer, scheduler: LofiScheduler, moodSource: ScriptedMoodSource = ScriptedMoodSource()) {
        self.story = story
        self.player = player
        self.scheduler = scheduler
        self.moodSource = moodSource
    }

    public var currentSentence: DemoSentence { story.sentences[index] }

    // MARK: - Controls

    public func openBook() {
        guard !isBookOpen else { return }
        isBookOpen = true
        player.openBook(id: story.title)
        onChange?()
    }

    public func closeBook() {
        pause()
        guard isBookOpen else { return }
        isBookOpen = false
        lastReadingIndex = nil
        player.closeBook()
        onChange?()
    }

    public func play() {
        guard !isPlaying else { return }
        if isFinished {
            isFinished = false
            seek(to: 0)
        }
        openBook()
        isPlaying = true
        willStartPlaying?()
        player.narratorDidPlay()
        if lastReadingIndex == nil, readingTimer == nil {
            // A fresh start: the engine reads the opening window right away.
            scheduleReading(.start, at: index)
        }
        startSentence()
    }

    public func pause() {
        guard isPlaying else { return }
        isPlaying = false
        generation += 1
        cancel(&stepTimer)
        cancel(&sleepTimer)
        speaker?.stop()
        player.narratorDidPause()
        onChange?()
    }

    public func togglePlay() {
        isPlaying ? pause() : play()
    }

    /// Jumps to sentence `target`, as a seek, skip or chapter jump would.
    public func seek(to target: Int) {
        let clamped = min(max(0, target), story.sentences.count - 1)
        generation += 1
        cancel(&stepTimer)
        speaker?.stop()
        index = clamped
        isFinished = false
        lastReadingIndex = nil
        player.narratorDidSeek(toGlobalSentenceIndex: clamped)
        if isBookOpen {
            scheduleReading(.seek, at: clamped)
        }
        if isPlaying {
            startSentence()
        }
        onChange?()
    }

    /// Moves by about `seconds` of narration (the ±30 s buttons).
    public func skip(seconds: Double) {
        var remaining = abs(seconds)
        var target = index
        let step = seconds < 0 ? -1 : 1
        while remaining > 0, target + step >= 0, target + step < story.sentences.count {
            target += step
            remaining -= duration(of: story.sentences[target]) + settings.sentencePause / settings.rate
        }
        seek(to: target)
    }

    public func nextChapter() {
        let chapter = currentSentence.chapter
        if chapter + 1 < story.chapters.count {
            seek(to: story.chapters[chapter + 1].firstIndex)
        }
    }

    public func previousChapter() {
        let chapter = story.chapter(containing: index)
        // Like most players: back to this chapter's start, or the previous one if already there.
        if index - chapter.firstIndex > 2 || currentSentence.chapter == 0 {
            seek(to: chapter.firstIndex)
        } else {
            seek(to: story.chapters[currentSentence.chapter - 1].firstIndex)
        }
    }

    /// Pauses after `seconds`, like a sleep timer.
    public func sleep(after seconds: TimeInterval) {
        cancel(&sleepTimer)
        sleepTimer = scheduler.schedule(after: seconds) { [weak self] in
            self?.sleepTimer = nil
            self?.pause()
        }
    }

    public var sleepTimerRunning: Bool { sleepTimer != nil }

    // MARK: - Narration

    /// Speaking time of `sentence` at the current rate, without a speaker.
    public func duration(of sentence: DemoSentence) -> TimeInterval {
        Double(max(1, sentence.wordCount)) * settings.secondsPerWord / max(0.25, settings.rate)
    }

    private func startSentence() {
        generation += 1
        let token = generation
        let sentence = currentSentence
        if let speaker {
            player.sentenceDidStart(globalSentenceIndex: sentence.globalIndex, duration: nil)
            speaker.speak(sentence.text, rate: settings.rate) { [weak self] in
                guard let self else { return }
                self.scheduler.perform { self.sentenceEnded(token) }
            }
        } else {
            let duration = duration(of: sentence)
            player.sentenceDidStart(globalSentenceIndex: sentence.globalIndex, duration: duration)
            stepTimer = scheduler.schedule(after: duration) { [weak self] in
                self?.sentenceEnded(token)
            }
        }
        readingIfDue(for: sentence)
        onChange?()
    }

    private func sentenceEnded(_ token: Int) {
        guard token == generation, isPlaying else { return }
        if speaker != nil {
            player.sentenceDidEnd()
        }
        let pause = (currentSentence.endsParagraph ? settings.paragraphPause : settings.sentencePause) / max(0.25, settings.rate)
        stepTimer = scheduler.schedule(after: pause) { [weak self] in
            self?.advance(token)
        }
    }

    private func advance(_ token: Int) {
        guard token == generation, isPlaying else { return }
        stepTimer = nil
        guard index + 1 < story.sentences.count else {
            isPlaying = false
            isFinished = true
            player.narratorDidPause()
            onChange?()
            return
        }
        index += 1
        startSentence()
    }

    /// Regular readings every few sentences, and a chapter-start reading a few sentences
    /// into each new chapter (with no regular readings before it).
    private func readingIfDue(for sentence: DemoSentence) {
        guard isBookOpen, readingTimer == nil, let last = lastReadingIndex else { return }
        let chapterStart = story.chapters[sentence.chapter].firstIndex
        if sentence.chapter > 0, last < chapterStart {
            if sentence.indexInChapter >= settings.chapterStartDelay {
                emitReading(.chapterStart, at: sentence.globalIndex)
            }
            return
        }
        if sentence.globalIndex - last >= settings.readingCadence ?? moodSource.readingCadence {
            emitReading(.cadence, at: sentence.globalIndex)
        }
    }

    private func scheduleReading(_ trigger: ReadingTrigger, at target: Int) {
        cancel(&readingTimer)
        readingTimer = scheduler.schedule(after: settings.readingDelay) { [weak self] in
            guard let self else { return }
            self.readingTimer = nil
            guard self.isBookOpen else { return }
            self.emitReading(trigger, at: min(target, self.index))
        }
    }

    private func emitReading(_ trigger: ReadingTrigger, at target: Int) {
        let observation = moodSource.observation(at: target, trigger: trigger, in: story)
        lastReadingIndex = target
        player.receive(observation)
        onReading?(observation)
        onChange?()
    }

    private func cancel(_ timer: inout LofiCancellable?) {
        timer?.cancel()
        timer = nil
    }
}
