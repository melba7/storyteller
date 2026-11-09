import Foundation
import LofiAudio
import LofiMood
import LofiScoreCore
import LofiText
import XCTest
@testable import LofiScoreHost

/// Music while the listener reads on screen with the narrator stopped.
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
        follower.attachText(try Books.text(clock: scheduler), toBook: "book")
    }

    private func page(_ chapter: Int, _ index: Int, then seconds: TimeInterval = 60) async {
        follower.readerReached(Books.clip(chapter, index))
        await follower.waitUntilIdle()
        scheduler.advance(by: seconds)
    }

    private func status() -> NarrationFollower.Status {
        var result: NarrationFollower.Status?
        follower.status { result = $0 }
        return result!
    }

    private var readingIndices: [Int] {
        sink.readings.compactMap { if case let .reading(index, _) = $0 { return index } else { return nil } }
    }

    func testTheFirstPageStartsTheMusicFromItsTopSentence() async throws {
        try opened()
        sink.clear()
        await page(0, 5)
        XCTAssertEqual(sink.calls.first, .play)
        XCTAssertTrue(sink.calls.contains(.seek(5)))
        XCTAssertEqual(sink.sentences, [5])
        XCTAssertEqual(readingIndices, [5])
        XCTAssertTrue(status().isReading)
        XCTAssertFalse(status().isNarrating)
    }

    func testTurningOnReadsEverySentenceUpToTheNewTopOfThePage() async throws {
        try opened()
        await page(0, 0)
        sink.clear()
        await page(0, 12)
        XCTAssertEqual(sink.sentences, [12], "the playhead is the top of the page")
        XCTAssertTrue(sink.seeks.isEmpty, "turning a page is reading on, not a jump")
        // Every reading is for a sentence at or above the top of the page: never below it.
        XCTAssertFalse(readingIndices.isEmpty)
        XCTAssertTrue(readingIndices.allSatisfy { $0 > 0 && $0 <= 12 })
        XCTAssertEqual(readingIndices, readingIndices.sorted())
    }

    func testPagingBackKeepsTheMoodAndNothingIsReadAgain() async throws {
        try opened()
        await page(0, 0)
        await page(0, 12)
        sink.clear()
        await page(0, 4)
        XCTAssertEqual(sink.sentences, [4])
        XCTAssertTrue(sink.seeks.isEmpty)
        XCTAssertTrue(sink.readings.isEmpty)
        // Forward again: nothing new until the pages pass sentence 12.
        await page(0, 12)
        XCTAssertTrue(sink.readings.isEmpty)
        await page(0, 20)
        XCTAssertTrue(readingIndices.allSatisfy { $0 > 12 && $0 <= 20 })
    }

    func testABigJumpIsASeek() async throws {
        var configuration = NarrationFollower.Configuration()
        configuration.readerMaxPageStep = 20
        follower = NarrationFollower(scheduler: scheduler, configuration: configuration)
        follower.attach(sink)
        try opened()
        await page(0, 0)
        sink.clear()
        await page(1, 10)
        XCTAssertEqual(sink.seeks, [40])
        XCTAssertEqual(readingIndices, [40])
    }

    func testTheMusicStopsAfterAWhileWithoutAPageTurn() async throws {
        try opened()
        await page(0, 0, then: 0)
        sink.clear()
        scheduler.advance(by: 299)
        XCTAssertFalse(sink.calls.contains(.pause))
        scheduler.advance(by: 2)
        XCTAssertEqual(sink.calls, [.pause])
        XCTAssertFalse(status().isReading)
        // The next page starts it again.
        await page(0, 8)
        XCTAssertEqual(sink.calls.filter { $0 == .play }.count, 1)
    }

    func testStoppingAndChangingBookPauseTheMusic() async throws {
        try opened()
        await page(0, 0)
        sink.clear()
        follower.readerStopped()
        XCTAssertEqual(sink.calls, [.pause])
        follower.readerStopped()
        XCTAssertEqual(sink.calls, [.pause], "only once")

        await page(0, 3)
        sink.clear()
        follower.bookOpened(id: "other")
        XCTAssertEqual(sink.calls.first, .pause, "the old book's music does not carry on into the next")
    }

    func testTheNarratorLeadsWhileItPlays() async throws {
        try opened()
        follower.playingChanged(true)
        follower.clipStarted(Books.clip(0, 2))
        await follower.waitUntilIdle()
        sink.clear()
        await page(0, 20)
        XCTAssertTrue(sink.calls.isEmpty, "pages are ignored while the narrator reads")
    }

    func testPressingPlayHandsOverWithoutAPause() async throws {
        try opened()
        await page(0, 0)
        sink.clear()
        follower.playingChanged(true)
        follower.clipStarted(Books.clip(0, 1))
        await follower.waitUntilIdle()
        XCTAssertFalse(sink.calls.contains(.pause))
        XCTAssertTrue(status().isNarrating)
        XCTAssertFalse(status().isReading)
        scheduler.advance(by: 400)
        XCTAssertFalse(sink.calls.contains(.pause), "the reader's idle timer is gone")
    }

    func testANewPlayerCatchesUpWhileReading() async throws {
        try opened()
        await page(0, 6)
        let fresh = RecordingSink()
        follower.attach(fresh)
        await follower.waitUntilIdle()
        XCTAssertEqual(fresh.calls.first, .play)
        XCTAssertTrue(fresh.calls.contains(.open("book")))
    }
}
