import XCTest

@testable import PodcastAds

final class PrepOrderTests: XCTestCase {
  private let base = Date(timeIntervalSince1970: 1_000_000)

  private func item(_ id: String, daysOld: Double, _ state: PrepState = .needsWork) -> PrepCandidate {
    PrepCandidate(id: id, addedAt: base.addingTimeInterval(-daysOld * 86_400), state: state)
  }

  func testThePlayingEpisodeComesFirstEvenWhenOlder() {
    let all = [item("new", daysOld: 0), item("old", daysOld: 9), item("mid", daysOld: 3)]
    XCTAssertEqual(PrepOrder.order(all, playing: "old", upNext: []), ["old", "new", "mid"])
  }

  func testUpNextComesInItsOwnOrderBeforeTheNewestDownloads() {
    let all = [item("new", daysOld: 0), item("q1", daysOld: 8), item("q2", daysOld: 2), item("p", daysOld: 5)]
    XCTAssertEqual(
      PrepOrder.order(all, playing: "p", upNext: ["q2", "q1"]), ["p", "q2", "q1", "new"])
  }

  func testTheOtherDownloadsGoNewestFirstAndTiesByIdentifier() {
    let all = [item("b", daysOld: 1), item("c", daysOld: 4), item("a", daysOld: 1)]
    XCTAssertEqual(PrepOrder.order(all, playing: nil, upNext: []), ["a", "b", "c"])
  }

  func testDoneFailedAndUnsupportedEpisodesAreLeftOutEvenWhenPlayingOrQueued() {
    let all = [
      item("done", daysOld: 0, .done), item("failed", daysOld: 0, .failed),
      item("lang", daysOld: 0, .unsupported), item("ok", daysOld: 5),
    ]
    XCTAssertEqual(
      PrepOrder.order(all, playing: "done", upNext: ["failed", "lang"]), ["ok"])
  }

  func testUpNextNamesThatAreNotDownloadedAreIgnored() {
    let all = [item("a", daysOld: 1)]
    XCTAssertEqual(PrepOrder.order(all, playing: "gone", upNext: ["nope", "a"]), ["a"])
  }

  func testAnEpisodeInUpNextTwiceIsListedOnce() {
    let all = [item("a", daysOld: 1), item("b", daysOld: 2)]
    XCTAssertEqual(PrepOrder.order(all, playing: nil, upNext: ["b", "b", "a"]), ["b", "a"])
  }

  func testNextIsNilWhenNothingNeedsWork() {
    XCTAssertNil(PrepOrder.next([item("a", daysOld: 1, .done)], playing: nil, upNext: []))
  }

  func testStartingAnotherEpisodeTakesOverAtTheNextChoice() {
    let all = [item("a", daysOld: 0), item("b", daysOld: 5)]
    XCTAssertEqual(PrepOrder.next(all, playing: nil, upNext: []), "a")
    XCTAssertEqual(PrepOrder.next(all, playing: "b", upNext: []), "b")
  }

  func testAPlayingEpisodeThatIsDoneDoesNotTakeOver() {
    let all = [item("a", daysOld: 0), item("b", daysOld: 5, .done)]
    XCTAssertEqual(PrepOrder.next(all, playing: "b", upNext: []), "a")
  }

  func testWhenPlayingEndsTheOrderFallsBackToUpNextThenNewest() {
    let all = [item("a", daysOld: 0), item("b", daysOld: 5), item("c", daysOld: 9)]
    XCTAssertEqual(PrepOrder.order(all, playing: "c", upNext: ["b"]), ["c", "b", "a"])
    XCTAssertEqual(PrepOrder.order(all, playing: nil, upNext: ["b"]), ["b", "a", "c"])
  }
}

final class BackgroundPowerTests: XCTestCase {
  func testChargingAlwaysMayRun() {
    XCTAssertTrue(BackgroundPower.mayRun(charging: true, batteryLevel: 0.05, lowPowerMode: true))
    XCTAssertTrue(BackgroundPower.mayRun(charging: true, batteryLevel: nil, lowPowerMode: false))
  }

  func testOnBatteryItNeedsThirtyPercentAndLowPowerModeOff() {
    XCTAssertTrue(BackgroundPower.mayRun(charging: false, batteryLevel: 0.30, lowPowerMode: false))
    XCTAssertTrue(BackgroundPower.mayRun(charging: false, batteryLevel: 0.9, lowPowerMode: false))
    XCTAssertFalse(BackgroundPower.mayRun(charging: false, batteryLevel: 0.29, lowPowerMode: false))
    XCTAssertFalse(BackgroundPower.mayRun(charging: false, batteryLevel: 0.9, lowPowerMode: true))
  }

  func testAnUnknownBatteryLevelOffTheChargerDoesNotRun() {
    XCTAssertFalse(BackgroundPower.mayRun(charging: false, batteryLevel: nil, lowPowerMode: false))
  }

  func testNeitherTaskRequiresTheCharger() {
    XCTAssertFalse(BackgroundPower.requiresExternalPower)
  }
}

final class PrepRetryTests: XCTestCase {
  func testTheWaitGrowsAndThenStops() {
    XCTAssertEqual(PrepRetry.delay(afterFailures: 1), 60)
    XCTAssertEqual(PrepRetry.delay(afterFailures: 2), 300)
    XCTAssertEqual(PrepRetry.delay(afterFailures: 3), 900)
    XCTAssertNil(PrepRetry.delay(afterFailures: 4))
    XCTAssertNil(PrepRetry.delay(afterFailures: 0))
  }
}
