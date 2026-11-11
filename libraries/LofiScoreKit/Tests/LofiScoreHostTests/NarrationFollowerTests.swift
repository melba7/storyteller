import Foundation
import LofiAudioCore
import LofiText
import XCTest
@testable import LofiScoreHost

/// Records what the follower asks of the player.
final class RecordingSink: NarrationSink, @unchecked Sendable {
    enum Call: Equatable {
        case open(String)
        case close
        case play
        case pause
        case seek(Int?)
        case sentence(Int?, duration: TimeInterval?)
    }

    private let lock = NSLock()
    private var log: [Call] = []

    var calls: [Call] { lock.withLock { log } }
    func clear() { lock.withLock { log.removeAll() } }
    private func add(_ call: Call) { lock.withLock { log.append(call) } }

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
}

enum Books {
    /// Two chapters of plain sentences: "c0-s0" … in "memory/c0.xhtml", and so on.
    static func text(sentences: Int = 30) throws -> BookText {
        let chapter0 = (0..<sentences).map { "The quiet morning light fell on the garden, sentence \($0)." }
        let chapter1 = (0..<sentences).map { "Footsteps echoed in the dark hall as the danger grew, sentence \($0)." }
        return BookText(spoilerGuard: try SpoilerGuard(chapters: [chapter0, chapter1]))
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

    /// One clip, then let `seconds` pass.
    private func narrate(_ clip: NarratorClip, then seconds: TimeInterval = 3) {
        follower.clipStarted(clip)
        scheduler.advance(by: seconds)
    }

    private func status() -> NarrationFollower.Status {
        var result: NarrationFollower.Status?
        follower.status { result = $0 }
        return result!
    }

    func testWaitsForTheTextThenStartsWithTheSentenceBeingRead() throws {
        follower.bookOpened(id: "book")
        follower.playingChanged(true)
        follower.clipStarted(Books.clip(0, 0))
        follower.clipStarted(Books.clip(0, 1))
        XCTAssertEqual(sink.calls, [.play], "no book is opened in the player before its text is ready")

        follower.attachText(try Books.text(), toBook: "book")
        // Only the latest clip is replayed: the sounds start from where the narrator is.
        XCTAssertEqual(sink.calls.first, .play)
        XCTAssertEqual(sink.calls[1], .open("book"))
        XCTAssertEqual(sink.sentences, [1])
        XCTAssertTrue(status().hasText)
    }

    func testTextForABookThatIsNoLongerOpenIsIgnored() throws {
        follower.bookOpened(id: "a")
        follower.bookOpened(id: "b")
        follower.attachText(try Books.text(), toBook: "a")
        XCTAssertEqual(sink.calls, [])
        XCTAssertFalse(status().hasText)
    }

    func testFollowsSentencesAndRecognisesSeeks() throws {
        follower.bookOpened(id: "book")
        follower.attachText(try Books.text(), toBook: "book")
        follower.playingChanged(true)
        for index in 0...3 {
            narrate(Books.clip(0, index))
        }
        XCTAssertEqual(sink.seeks, [], "steady narration is not a seek")

        narrate(Books.clip(0, 4), then: 1) // a gap clip may repeat the sentence
        narrate(Books.clip(0, 4))
        narrate(Books.clip(0, 6)) // one missed boundary is still steady
        XCTAssertEqual(sink.seeks, [])

        narrate(Books.clip(0, 20)) // skip forward
        narrate(Books.clip(0, 5)) // skip back
        narrate(Books.clip(1, 0)) // into the next chapter: a jump from #5 to #30
        XCTAssertEqual(sink.seeks, [20, 5, 30])
        XCTAssertEqual(sink.sentences.filter { $0 == 4 }.count, 2, "every clip moves the bed level, even a repeated one")
        XCTAssertEqual(status().position?.globalIndex, 30)
    }

    func testAShortRewindReplaysWithoutASeek() throws {
        follower.bookOpened(id: "book")
        follower.attachText(try Books.text(), toBook: "book")
        follower.playingChanged(true)
        for index in 0...10 {
            narrate(Books.clip(0, index))
        }

        // The app rewinds a few seconds when playback resumes, or the listener skips back.
        narrate(Books.clip(0, 7))
        for index in 8...10 {
            narrate(Books.clip(0, index))
        }
        XCTAssertEqual(sink.seeks, [], "a short rewind is not a seek")
        XCTAssertEqual(sink.sentences.suffix(4), [7, 8, 9, 10], "the bed level still follows the voice")

        // Past the furthest sentence, the narration carries on as before.
        for index in 11...20 {
            narrate(Books.clip(0, index))
        }
        XCTAssertEqual(sink.seeks, [])

        // A long jump back is a seek.
        narrate(Books.clip(0, 2))
        XCTAssertEqual(sink.seeks, [2])
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
        XCTAssertEqual(sink.calls, [.play], "a seek's stall does not stop the sounds; the resume is passed on for a player that stopped on its own (headphones pulled)")
        sink.clear()

        follower.playingChanged(false)
        scheduler.advance(by: 1)
        XCTAssertEqual(sink.calls, [.pause])
        follower.playingChanged(true)
        XCTAssertEqual(sink.calls, [.pause, .play])
    }

    func testAClosedBookIsClosedInThePlayer() throws {
        follower.bookOpened(id: "a")
        follower.attachText(try Books.text(), toBook: "a")
        follower.playingChanged(true)
        follower.clipStarted(Books.clip(0, 0))
        follower.bookOpened(id: "b")
        XCTAssertEqual(sink.calls.suffix(1), [.close], "the old book's sounds are closed")
        follower.clipStarted(Books.clip(0, 1))
        XCTAssertEqual(sink.calls.suffix(1), [.close], "and nothing plays until the new book's text is ready")
    }

    func testANewTextForTheOpenBookKeepsItOpen() throws {
        follower.bookOpened(id: "book")
        follower.attachText(try Books.text(), toBook: "book")
        follower.playingChanged(true)
        narrate(Books.clip(0, 3))
        let before = sink.calls
        follower.replaceText(try Books.text(), toBook: "book")
        XCTAssertEqual(sink.calls, before, "the book is not reopened for the player")
        narrate(Books.clip(0, 4))
        XCTAssertEqual(sink.sentences.last, 4)
    }

    func testANewPlayerCatchesUp() throws {
        follower.bookOpened(id: "book")
        follower.attachText(try Books.text(), toBook: "book")
        follower.playingChanged(true)
        for index in 0..<5 {
            narrate(Books.clip(0, index))
        }

        let replacement = RecordingSink()
        follower.attach(replacement)
        XCTAssertEqual(sink.calls.suffix(2), [.pause, .close], "the old player fades out")
        XCTAssertEqual(replacement.calls, [.play, .open("book"), .seek(4), .sentence(4, duration: nil)])

        follower.attach(nil)
        XCTAssertEqual(replacement.calls.suffix(2), [.pause, .close])
        narrate(Books.clip(0, 5))
        XCTAssertEqual(replacement.calls.count, 6, "nothing reaches a detached player")
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
