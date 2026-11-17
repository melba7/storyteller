import XCTest

@testable import PodcastChapters

final class ChapterRulesTests: XCTestCase {
  let chapters = [
    Chapter(start: 0, title: "Intro"), Chapter(start: 60, title: "Story"),
    Chapter(start: 600, title: "Ad"), Chapter(start: 660, title: "Outro"),
  ]

  func testCurrentChapterIsTheLastOneStarted() {
    XCTAssertEqual(ChapterRules.current(at: 0, in: chapters), 0)
    XCTAssertEqual(ChapterRules.current(at: 59.9, in: chapters), 0)
    XCTAssertEqual(ChapterRules.current(at: 60, in: chapters), 1)
    XCTAssertEqual(ChapterRules.current(at: 9999, in: chapters), 3)
    XCTAssertNil(ChapterRules.current(at: .nan, in: chapters))
    XCTAssertNil(ChapterRules.current(at: 5, in: []))
  }

  func testNoChapterBeforeTheFirstStarts() {
    let late = [Chapter(start: 30, title: "A")]
    XCTAssertNil(ChapterRules.current(at: 10, in: late))
  }

  func testAChapterWithAnEndAndAGapEnds() {
    let gap = [Chapter(start: 0, end: 10, title: "A"), Chapter(start: 20, title: "B")]
    XCTAssertEqual(ChapterRules.current(at: 9, in: gap), 0)
    XCTAssertNil(ChapterRules.current(at: 15, in: gap))
    XCTAssertEqual(ChapterRules.current(at: 20, in: gap), 1)
  }

  func testWhereAChapterEnds() {
    XCTAssertEqual(ChapterRules.end(of: 1, in: chapters, duration: 900), 600)
    XCTAssertEqual(ChapterRules.end(of: 3, in: chapters, duration: 900), 900)
    XCTAssertNil(ChapterRules.end(of: 3, in: chapters, duration: nil))
    XCTAssertNil(ChapterRules.end(of: 9, in: chapters, duration: 900))
    let own = [Chapter(start: 0, end: 5, title: "A"), Chapter(start: 10, title: "B")]
    XCTAssertEqual(ChapterRules.end(of: 0, in: own, duration: 100), 5)
  }

  func testPreviousGoesToTheStartOfThisChapterAfterThreeSeconds() {
    XCTAssertEqual(ChapterRules.previousTarget(at: 64, in: chapters), 60)
    XCTAssertEqual(ChapterRules.previousTarget(at: 63, in: chapters), 0)
    XCTAssertEqual(ChapterRules.previousTarget(at: 61, in: chapters), 0)
    XCTAssertEqual(ChapterRules.previousTarget(at: 2, in: chapters), 0)
    XCTAssertEqual(ChapterRules.previousTarget(at: 5, in: []), 0)
  }

  func testNextGoesToTheNextChapterAndNowhereFromTheLast() {
    XCTAssertEqual(ChapterRules.nextTarget(at: 0, in: chapters), 60)
    XCTAssertEqual(ChapterRules.nextTarget(at: 60, in: chapters), 600)
    XCTAssertNil(ChapterRules.nextTarget(at: 700, in: chapters))
    XCTAssertNil(ChapterRules.nextTarget(at: 5, in: []))
  }

  // MARK: Skipping

  func testASkippedChapterIsJumpedOver() {
    var skipper = ChapterSkipper(skipped: [600_000])
    XCTAssertNil(skipper.check(position: 599, in: chapters, duration: 900))
    XCTAssertEqual(skipper.check(position: 600.2, in: chapters, duration: 900), 660)
  }

  func testSeekingIntoASkippedChapterPlaysItUntilItIsLeft() {
    var skipper = ChapterSkipper(skipped: [600_000])
    skipper.seeked(to: 610, in: chapters)
    XCTAssertNil(skipper.check(position: 610.5, in: chapters, duration: 900))
    XCTAssertNil(skipper.check(position: 659, in: chapters, duration: 900))
    // Left it, and back again by playing (not by a seek): skipped.
    XCTAssertNil(skipper.check(position: 661, in: chapters, duration: 900))
    XCTAssertEqual(skipper.check(position: 600.1, in: chapters, duration: 900), 660)
  }

  func testSkippedChaptersInARowAreJumpedTogether() {
    var skipper = ChapterSkipper(skipped: [60_000, 600_000])
    XCTAssertEqual(skipper.check(position: 60.1, in: chapters, duration: 900), 660)
    skipper.set(660_000, skipped: true)
    XCTAssertEqual(skipper.check(position: 600.1, in: chapters, duration: 900), 899.95)
  }

  func testSwitchingASkipOffStopsIt() {
    var skipper = ChapterSkipper(skipped: [600_000])
    skipper.set(600_000, skipped: false)
    XCTAssertNil(skipper.check(position: 600.2, in: chapters, duration: 900))
  }
}
