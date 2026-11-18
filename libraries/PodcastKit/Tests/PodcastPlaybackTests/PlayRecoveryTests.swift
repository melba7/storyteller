import XCTest

@testable import PodcastPlayback

final class PlayRecoveryTests: XCTestCase {
  func testPlayAfterAFailureStartsAgainAtTheLastGoodPlace() {
    var recovery = PlayRecovery()
    recovery.loaded(startingAt: 0)
    recovery.noted(1200)
    recovery.itemFailed()
    // A failed item's clock reads 0. It must never become the place.
    recovery.noted(0)
    XCTAssertEqual(recovery.reloadPlace, 1200)
    XCTAssertEqual(recovery.place(reported: 0), 1200)
  }

  func testNothingIsReloadedWhileTheItemIsFine() {
    var recovery = PlayRecovery()
    recovery.loaded(startingAt: 0)
    recovery.noted(30)
    XCTAssertNil(recovery.reloadPlace)
    XCTAssertEqual(recovery.place(reported: 30), 30)
  }

  func testAFailureBeforeAnythingPlayedStartsAtTheStartPlace() {
    var recovery = PlayRecovery()
    recovery.loaded(startingAt: 900)
    recovery.itemFailed()
    XCTAssertEqual(recovery.reloadPlace, 900)
    XCTAssertEqual(recovery.place(reported: 0), 900)
  }

  func testANewItemForgetsTheFailure() {
    var recovery = PlayRecovery()
    recovery.loaded(startingAt: 0)
    recovery.noted(1200)
    recovery.itemFailed()
    recovery.loaded(startingAt: 1200)
    XCTAssertNil(recovery.reloadPlace)
    XCTAssertEqual(recovery.place(reported: 1210), 1210)
    // The new item can fail too, and then it is its own places that count.
    recovery.noted(1500)
    recovery.itemFailed()
    XCTAssertEqual(recovery.reloadPlace, 1500)
  }

  func testAPlaceThatIsNotANumberIsIgnored() {
    var recovery = PlayRecovery()
    recovery.loaded(startingAt: 0)
    recovery.noted(500)
    recovery.noted(.nan)
    recovery.noted(.infinity)
    recovery.itemFailed()
    XCTAssertEqual(recovery.reloadPlace, 500)
    var broken = PlayRecovery()
    broken.loaded(startingAt: .nan)
    broken.itemFailed()
    XCTAssertEqual(broken.reloadPlace, 0)
  }

  func testAPlaceNeverGoesBelowZero() {
    var recovery = PlayRecovery()
    recovery.loaded(startingAt: -20)
    recovery.itemFailed()
    XCTAssertEqual(recovery.reloadPlace, 0)
    recovery.moved(to: -5)
    XCTAssertEqual(recovery.reloadPlace, 0)
  }

  func testALaterPlaceReplacesAnEarlierOne() {
    // The listener scrubs back, so the latest place counts, not the furthest.
    var recovery = PlayRecovery()
    recovery.loaded(startingAt: 0)
    recovery.noted(1200)
    recovery.noted(300)
    recovery.itemFailed()
    XCTAssertEqual(recovery.reloadPlace, 300)
  }

  func testAScrubOnAFailedEpisodeMovesTheReloadPlace() {
    var recovery = PlayRecovery()
    recovery.loaded(startingAt: 0)
    recovery.noted(1200)
    recovery.itemFailed()
    recovery.moved(to: 2000)
    XCTAssertEqual(recovery.reloadPlace, 2000)
    XCTAssertEqual(recovery.place(reported: 0), 2000)
    // A seek that is not a number changes nothing.
    recovery.moved(to: .nan)
    XCTAssertEqual(recovery.reloadPlace, 2000)
  }

  func testTheReportedPlaceIsUsedAsItIsWhileTheItemIsFine() {
    var recovery = PlayRecovery()
    recovery.loaded(startingAt: 100)
    XCTAssertEqual(recovery.place(reported: 0), 0)
    XCTAssertEqual(recovery.place(reported: 250), 250)
  }
}
