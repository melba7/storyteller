import Foundation
import LofiAudioCore
import LofiText
import XCTest
@testable import LofiScoreHost

/// The sounds while the listener reads on screen with the narrator stopped.
final class ReaderFollowTests: XCTestCase {
    private var scheduler: ManualScheduler!
    private var follower: NarrationFollower!
    private var sink: RecordingSink!

    override func setUp() {
        scheduler = ManualScheduler()
        follower = NarrationFollower(scheduler: scheduler)
        sink = RecordingSink()
        follower.attach(sink)
    }

    private func opened() throws {
        follower.bookOpened(id: "book")
        follower.attachText(try Books.text(), toBook: "book")
    }

    private func page(_ chapter: Int, _ index: Int, then seconds: TimeInterval = 60) {
        follower.readerReached(Books.clip(chapter, index))
        scheduler.advance(by: seconds)
    }

    private func status() -> NarrationFollower.Status {
        var result: NarrationFollower.Status?
        follower.status { result = $0 }
        return result!
    }

    func testTheFirstPageStartsTheSoundsFromItsTopSentence() throws {
        try opened()
        sink.clear()
        page(0, 5)
        XCTAssertEqual(sink.calls.first, .play)
        XCTAssertTrue(sink.calls.contains(.seek(5)))
        XCTAssertEqual(sink.sentences, [5])
        XCTAssertTrue(status().isReading)
        XCTAssertFalse(status().isNarrating)
    }

    func testTurningThePageMovesToItsTop() throws {
        try opened()
        page(0, 0)
        sink.clear()
        page(0, 12)
        XCTAssertEqual(sink.sentences, [12], "the playhead is the top of the page")
        XCTAssertTrue(sink.seeks.isEmpty, "turning a page is reading on, not a jump")
        XCTAssertEqual(sink.durations, [0], "no voice: the sounds may rise a little")
    }

    func testPagingBackKeepsTheScene() throws {
        try opened()
        page(0, 0)
        page(0, 12)
        sink.clear()
        page(0, 4)
        XCTAssertEqual(sink.sentences, [4])
        XCTAssertTrue(sink.seeks.isEmpty)
        XCTAssertEqual(status().position?.globalIndex, 4)
    }

    func testABigJumpIsASeek() throws {
        var configuration = NarrationFollower.Configuration()
        configuration.readerMaxPageStep = 20
        follower = NarrationFollower(scheduler: scheduler, configuration: configuration)
        follower.attach(sink)
        try opened()
        page(0, 0)
        sink.clear()
        page(1, 10)
        XCTAssertEqual(sink.seeks, [40])
    }

    func testTheSoundsStopAfterAWhileWithoutAPageTurn() throws {
        try opened()
        page(0, 0, then: 0)
        sink.clear()
        scheduler.advance(by: 299)
        XCTAssertFalse(sink.calls.contains(.pause))
        scheduler.advance(by: 2)
        XCTAssertEqual(sink.calls, [.pause])
        XCTAssertFalse(status().isReading)
        // The next page starts them again.
        page(0, 8)
        XCTAssertEqual(sink.calls.filter { $0 == .play }.count, 1)
    }

    func testStoppingAndChangingBookPauseTheSounds() throws {
        try opened()
        page(0, 0)
        sink.clear()
        follower.readerStopped()
        XCTAssertEqual(sink.calls, [.pause])
        follower.readerStopped()
        XCTAssertEqual(sink.calls, [.pause], "only once")

        page(0, 3)
        sink.clear()
        follower.bookOpened(id: "other")
        XCTAssertEqual(sink.calls.first, .pause, "the old book's sounds do not carry on into the next")
    }

    func testTheNarratorLeadsWhileItPlays() throws {
        try opened()
        follower.playingChanged(true)
        follower.clipStarted(Books.clip(0, 2))
        sink.clear()
        page(0, 20)
        XCTAssertTrue(sink.calls.isEmpty, "pages are ignored while the narrator reads")
    }

    func testPressingPlayHandsOverWithoutAPause() throws {
        try opened()
        page(0, 0)
        sink.clear()
        follower.playingChanged(true)
        follower.clipStarted(Books.clip(0, 1))
        XCTAssertFalse(sink.calls.contains(.pause))
        XCTAssertTrue(status().isNarrating)
        XCTAssertFalse(status().isReading)
        scheduler.advance(by: 400)
        XCTAssertFalse(sink.calls.contains(.pause), "the reader's idle timer is gone")
    }

    func testANewPlayerCatchesUpWhileReading() throws {
        try opened()
        page(0, 6)
        let fresh = RecordingSink()
        follower.attach(fresh)
        XCTAssertEqual(fresh.calls.first, .play)
        XCTAssertTrue(fresh.calls.contains(.open("book")))
    }
}
