import Foundation
import LofiAudio
import LofiDirector
import LofiMood
import LofiScoreCore
import LofiText
import XCTest
@testable import LofiScoreHost

/// Records what the follower asks of the music player.
final class RecordingSink: NarrationMusicSink, @unchecked Sendable {
    enum Call: Equatable {
        case open(String)
        case close
        case play
        case pause
        case seek(Int?)
        case sentence(Int?, duration: TimeInterval?)
        case reading(Int, ReadingTrigger)
    }

    private let lock = NSLock()
    private var log: [Call] = []

    var calls: [Call] { lock.withLock { log } }
    func clear() { lock.withLock { log.removeAll() } }
    private func add(_ call: Call) { lock.withLock { log.append(call) } }

    var readings: [Call] { calls.filter { if case .reading = $0 { return true } else { return false } } }
    var sentences: [Int] { calls.compactMap { if case let .sentence(index, _) = $0 { return index } else { return nil } } }
    var seeks: [Int?] { calls.compactMap { if case let .seek(index) = $0 { return index } else { return nil } } }
    /// Sentence durations as reported (0 when the follower gave none).
    var durations: [TimeInterval] { calls.compactMap { if case let .sentence(_, duration) = $0 { return duration ?? 0 } else { return nil } } }

    func openBook(id: String) { add(.open(id)) }
    func closeBook() { add(.close) }
    func narratorDidPlay() { add(.play) }
    func narratorDidPause() { add(.pause) }
    func narratorDidSeek(toGlobalSentenceIndex index: Int?) { add(.seek(index)) }
    func sentenceDidStart(globalSentenceIndex: Int?, duration: TimeInterval?) { add(.sentence(globalSentenceIndex, duration: duration)) }
    func receive(_ observation: MoodObservation) { add(.reading(observation.globalSentenceIndex, observation.trigger)) }
}

/// An engine that waits until told to answer, to test readings overtaken by events.
final class GatedEngine: MoodEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var open = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private let inner = LexiconMoodEngine()

    var id: String { "gated/1" }

    func release() {
        let continuations: [CheckedContinuation<Void, Never>] = lock.withLock {
            open = true
            defer { waiting.removeAll() }
            return waiting
        }
        continuations.forEach { $0.resume() }
    }

    func reading(for window: CausalWindow) async throws -> MoodReading {
        await withCheckedContinuation { continuation in
            let proceed: Bool = lock.withLock {
                if open { return true }
                waiting.append(continuation)
                return false
            }
            if proceed { continuation.resume() }
        }
        return try await inner.reading(for: window)
    }
}

/// Lets the mood tracker read a test's manual clock. Tests only read it while the follower
/// is idle or from the same thread.
final class UncheckedClock: @unchecked Sendable {
    private let scheduler: ManualScheduler
    init(_ scheduler: ManualScheduler) { self.scheduler = scheduler }
    var now: Double { scheduler.now }
}

enum Books {
    /// Two chapters of plain sentences: "c0-s0" … in "memory/c0.xhtml", and so on.
    static func text(engine: any MoodEngine = LexiconMoodEngine(), clock: ManualScheduler? = nil, sentences: Int = 30) throws -> BookText {
        let chapter0 = (0..<sentences).map { "The quiet morning light fell on the garden, sentence \($0)." }
        let chapter1 = (0..<sentences).map { "Footsteps echoed in the dark hall as the danger grew, sentence \($0)." }
        let guardian = try SpoilerGuard(chapters: [chapter0, chapter1])
        guard let clock else { return BookText(spoilerGuard: guardian, engine: engine) }
        let time = UncheckedClock(clock)
        return BookText(spoilerGuard: guardian, engine: engine, clock: { time.now })
    }

    /// The clip for sentence `index` of chapter `chapter`, three seconds each in one file per chapter.
    static func clip(_ chapter: Int, _ index: Int, length: Double = 3) -> NarratorClip {
        NarratorClip(
            textResource: "memory/c\(chapter).xhtml",
            fragmentId: "c\(chapter)-s\(index)",
            audioResource: "audio/c\(chapter).mp3",
            start: Double(index) * length,
            end: Double(index + 1) * length
        )
    }
}

final class NarrationFollowerTests: XCTestCase {
    private var scheduler: ManualScheduler!
    private var follower: NarrationFollower!
    private var sink: RecordingSink!

    override func setUp() {
        scheduler = ManualScheduler()
        follower = NarrationFollower(scheduler: scheduler)
        sink = RecordingSink()
        follower.attach(sink)
    }

    /// One clip, then let its reading finish, then let `seconds` pass.
    private func narrate(_ clip: NarratorClip, then seconds: TimeInterval = 3) async {
        follower.clipStarted(clip)
        await follower.waitUntilIdle()
        scheduler.advance(by: seconds)
    }

    private func status() -> NarrationFollower.Status {
        var result: NarrationFollower.Status?
        follower.status { result = $0 }
        return result!
    }

    func testWaitsForTheTextThenStartsWithTheSentenceBeingRead() async throws {
        follower.bookOpened(id: "book")
        follower.playingChanged(true)
        follower.clipStarted(Books.clip(0, 0))
        follower.clipStarted(Books.clip(0, 1))
        XCTAssertEqual(sink.calls, [.play], "no book is opened in the player before its text is ready")

        follower.attachText(try Books.text(), toBook: "book")
        await follower.waitUntilIdle()
        // Only the latest clip is replayed: the music starts from where the narrator is.
        XCTAssertEqual(sink.calls.first, .play)
        XCTAssertEqual(sink.calls[1], .open("book"))
        XCTAssertEqual(sink.sentences, [1])
        XCTAssertEqual(sink.readings, [.reading(1, .start)])
        XCTAssertTrue(status().hasText)
    }

    func testTextForABookThatIsNoLongerOpenIsIgnored() throws {
        follower.bookOpened(id: "a")
        follower.bookOpened(id: "b")
        follower.attachText(try Books.text(), toBook: "a")
        XCTAssertEqual(sink.calls, [])
        XCTAssertFalse(status().hasText)
    }

    func testFollowsSentencesAndRecognisesSeeks() async throws {
        follower.bookOpened(id: "book")
        follower.attachText(try Books.text(), toBook: "book")
        follower.playingChanged(true)
        for index in 0...3 {
            await narrate(Books.clip(0, index))
        }
        XCTAssertEqual(sink.seeks, [], "steady narration is not a seek")

        await narrate(Books.clip(0, 4), then: 1) // a gap clip may repeat the sentence
        await narrate(Books.clip(0, 4))
        await narrate(Books.clip(0, 6)) // one missed boundary is still steady
        XCTAssertEqual(sink.seeks, [])

        await narrate(Books.clip(0, 20)) // skip forward
        await narrate(Books.clip(0, 5)) // skip back
        await narrate(Books.clip(1, 0)) // into the next chapter: a jump from #5 to #30
        XCTAssertEqual(sink.seeks, [20, 5, 30])

        let triggers = sink.readings.compactMap { call -> ReadingTrigger? in
            if case let .reading(_, trigger) = call { return trigger } else { return nil }
        }
        XCTAssertEqual(triggers.first, .start)
        XCTAssertEqual(triggers.filter { $0 == .seek }.count, 3, "each seek gets its own reading")
        XCTAssertEqual(sink.sentences.filter { $0 == 4 }.count, 2, "every clip moves the bed level, even a repeated one")
    }

    func testAShortRewindReplaysWithoutChangingTheMusic() async throws {
        follower.bookOpened(id: "book")
        follower.attachText(try Books.text(clock: scheduler), toBook: "book")
        follower.playingChanged(true)
        for index in 0...10 {
            await narrate(Books.clip(0, index))
        }
        let readingsBefore = sink.readings.count

        // The app rewinds a few seconds when playback resumes, or the listener skips back.
        await narrate(Books.clip(0, 7))
        for index in 8...10 {
            await narrate(Books.clip(0, index))
        }
        XCTAssertEqual(sink.seeks, [], "a short rewind is not a seek")
        XCTAssertEqual(sink.readings.count, readingsBefore, "sentences heard again bring no new reading")
        XCTAssertEqual(sink.sentences.suffix(4), [7, 8, 9, 10], "the bed level still follows the voice")

        // Past the furthest sentence, readings carry on as before.
        for index in 11...20 {
            await narrate(Books.clip(0, index), then: 5)
        }
        XCTAssertGreaterThan(sink.readings.count, readingsBefore)
        XCTAssertFalse(sink.readings.contains(.reading(11, .seek)))

        // A long jump back is a seek.
        await narrate(Books.clip(0, 2))
        XCTAssertEqual(sink.seeks, [2])
    }

    func testEveryReadingIsForASentenceThatHasStarted() async throws {
        follower.bookOpened(id: "book")
        follower.attachText(try Books.text(clock: scheduler), toBook: "book")
        follower.playingChanged(true)
        for chapter in 0...1 {
            for index in 0..<30 {
                await narrate(Books.clip(chapter, index))
            }
        }
        var started = Set<Int>()
        for call in sink.calls {
            switch call {
            case let .sentence(index?, _):
                started.insert(index)
            case let .reading(index, _):
                XCTAssertTrue(started.contains(index), "reading for #\(index) before it started")
                XCTAssertEqual(index, started.max(), "a reading only ever describes the newest sentence")
            default:
                break
            }
        }
        XCTAssertGreaterThan(sink.readings.count, 5)
    }

    func testEstimatesTheSpeedFromTheClips() throws {
        follower.bookOpened(id: "book")
        follower.attachText(try Books.text(), toBook: "book")
        follower.playingChanged(true)
        // Three seconds of audio every two seconds: 1.5×.
        for index in 0..<12 {
            follower.clipStarted(Books.clip(0, index))
            scheduler.advance(by: 2)
        }
        XCTAssertEqual(status().estimatedRate, 1.5, accuracy: 0.02)
        XCTAssertEqual(sink.durations.last ?? -1, 2, accuracy: 0.05, "a sentence lasts its clip length over the speed")

        // A pause and a jump do not count as fast listening.
        follower.playingChanged(false)
        scheduler.advance(by: 30)
        follower.playingChanged(true)
        follower.clipStarted(Books.clip(0, 25))
        scheduler.advance(by: 2)
        follower.clipStarted(Books.clip(0, 26))
        XCTAssertEqual(status().estimatedRate, 1.5, accuracy: 0.02)
    }

    func testResumingInsideASentenceUsesWhatIsLeftOfIt() throws {
        follower.bookOpened(id: "book")
        follower.attachText(try Books.text(), toBook: "book")
        follower.playingChanged(true)
        follower.clipStarted(Books.clip(0, 2), audioTime: 7.5)
        XCTAssertEqual(sink.durations.last ?? -1, 1.5, accuracy: 0.001)
    }

    func testBriefStallsAreNotPauses() throws {
        follower.bookOpened(id: "book")
        follower.attachText(try Books.text(), toBook: "book")
        follower.playingChanged(true)
        sink.clear()

        follower.playingChanged(false)
        scheduler.advance(by: 0.3)
        follower.playingChanged(true)
        scheduler.advance(by: 5)
        XCTAssertEqual(sink.calls, [.play], "a seek's stall does not stop the music; the resume is passed on for players that stopped on their own (headphones pulled)")
        sink.clear()

        follower.playingChanged(false)
        scheduler.advance(by: 1)
        XCTAssertEqual(sink.calls, [.pause])
        follower.playingChanged(true)
        XCTAssertEqual(sink.calls, [.pause, .play])
    }

    func testALongPauseStartsAFreshStretch() async throws {
        follower.bookOpened(id: "book")
        follower.attachText(try Books.text(clock: scheduler), toBook: "book")
        follower.playingChanged(true)
        for index in 0..<8 {
            await narrate(Books.clip(0, index))
        }
        follower.playingChanged(false)
        scheduler.advance(by: 600)
        follower.playingChanged(true)
        follower.clipStarted(Books.clip(0, 8))
        await follower.waitUntilIdle()
        XCTAssertEqual(sink.readings.last, .reading(8, .start))
    }

    func testReadingsForAClosedBookAreDropped() async throws {
        let engine = GatedEngine()
        follower.bookOpened(id: "a")
        follower.attachText(try Books.text(engine: engine), toBook: "a")
        follower.playingChanged(true)
        follower.clipStarted(Books.clip(0, 0))
        follower.bookOpened(id: "b")
        engine.release()
        await follower.waitUntilIdle()
        XCTAssertEqual(sink.readings, [])
        XCTAssertEqual(sink.calls.suffix(1), [.close], "the old book's music is closed")
    }

    func testANewPlayerCatchesUp() async throws {
        follower.bookOpened(id: "book")
        follower.attachText(try Books.text(), toBook: "book")
        follower.playingChanged(true)
        for index in 0..<5 {
            await narrate(Books.clip(0, index))
        }

        let replacement = RecordingSink()
        follower.attach(replacement)
        await follower.waitUntilIdle()
        XCTAssertEqual(sink.calls.suffix(2), [.pause, .close], "the old player fades out")
        XCTAssertEqual(Array(replacement.calls.prefix(4)), [.play, .open("book"), .seek(4), .sentence(4, duration: nil)])
        XCTAssertEqual(replacement.readings, [.reading(4, .seek)], "and the new one gets a reading for where the narrator is")
    }

    func testAPlayerAddedBesideTheOthersCatchesUpAlone() async throws {
        follower.bookOpened(id: "book")
        follower.attachText(try Books.text(), toBook: "book")
        follower.playingChanged(true)
        for index in 0..<5 {
            await narrate(Books.clip(0, index))
        }
        let before = sink.calls.count
        let readingsBefore = sink.readings.count

        let added = RecordingSink()
        follower.catchUp(added, reading: false) {}
        await follower.waitUntilIdle()
        XCTAssertEqual(added.calls, [.play, .open("book"), .seek(4), .sentence(4, duration: nil)])
        XCTAssertEqual(sink.calls.count, before, "the players already there are not reopened")
        XCTAssertEqual(sink.readings.count, readingsBefore, "and get no extra reading")

        follower.catchUp(RecordingSink(), reading: true) {}
        await follower.waitUntilIdle()
        XCTAssertEqual(sink.readings.suffix(1), [.reading(4, .seek)], "a new music player behind the fan-out gets a reading")
    }

    func testFrontMatterIsNotASeek() throws {
        follower.bookOpened(id: "book")
        follower.attachText(try Books.text(), toBook: "book")
        follower.playingChanged(true)
        follower.clipStarted(NarratorClip(textResource: "memory/cover.xhtml", fragmentId: "title", audioResource: "audio/intro.mp3", start: 0, end: 4))
        XCTAssertEqual(sink.sentences, [])
        XCTAssertEqual(status().unmatchedClips, 1)
    }
}
