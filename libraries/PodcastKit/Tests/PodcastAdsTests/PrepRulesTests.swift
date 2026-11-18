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

final class PrepStepTests: XCTestCase {
  private let base = Date(timeIntervalSince1970: 1_000_000)

  private func work(
    _ id: String, daysOld: Double = 0, head: Bool = true, rest: Bool = true
  ) -> PrepWork {
    PrepWork(
      id: id, addedAt: base.addingTimeInterval(-daysOld * 86_400), headPending: head, restPending: rest)
  }

  /// Takes steps until nothing is left, as the queue does when each step finishes.
  private func steps(_ all: [PrepWork], playing: String? = nil, upNext: [String] = []) -> [String] {
    var left = all
    var result: [String] = []
    while let step = PrepOrder.nextStep(left, playing: playing, upNext: upNext) {
      result.append("\(step.id) \(step.stage == .head ? "head" : "rest")")
      guard let index = left.firstIndex(where: { $0.id == step.id }) else { break }
      if step.stage == .head { left[index].headPending = false } else { left.remove(at: index) }
    }
    return result
  }

  func testThreeWaitingEpisodesHaveAllThreeHeadsDoneBeforeTheRestOfTheFirst() {
    let all = [work("a", daysOld: 0), work("b", daysOld: 1), work("c", daysOld: 2)]
    XCTAssertEqual(
      steps(all), ["a head", "b head", "c head", "a rest", "b rest", "c rest"])
  }

  func testThePlayingEpisodeDoesItsHeadAndThenItsRestBeforeOtherHeads() {
    let all = [work("a", daysOld: 0), work("b", daysOld: 1), work("p", daysOld: 9)]
    XCTAssertEqual(
      steps(all, playing: "p"), ["p head", "p rest", "a head", "b head", "a rest", "b rest"])
  }

  func testTheHeadsFollowUpNextBeforeTheNewestDownloads() {
    let all = [work("new", daysOld: 0), work("q1", daysOld: 5), work("q2", daysOld: 3)]
    XCTAssertEqual(
      steps(all, upNext: ["q1", "q2"]),
      ["q1 head", "q2 head", "new head", "q1 rest", "q2 rest", "new rest"])
  }

  func testAnEpisodeWhoseHeadIsDoneGoesStraightToItsRestAndSettledOnesAreLeftOut() {
    let all = [work("a", head: false), work("b"), work("gone", head: false, rest: false)]
    XCTAssertEqual(steps(all), ["b head", "a rest", "b rest"])
  }

  func testNothingIsPendingMeansNoStep() {
    XCTAssertNil(PrepOrder.nextStep([work("a", head: false, rest: false)], playing: nil, upNext: []))
    XCTAssertNil(PrepOrder.nextStep([], playing: "x", upNext: []))
  }

  func testAnEpisodeAtItsRestMakesWayForAnotherHeadButNotForAnotherRest() {
    let rest = PrepStep(id: "a", stage: .rest)
    XCTAssertTrue(
      PrepOrder.shouldYield(working: rest, next: PrepStep(id: "b", stage: .head), playing: nil))
    XCTAssertFalse(
      PrepOrder.shouldYield(working: rest, next: PrepStep(id: "b", stage: .rest), playing: nil))
    XCTAssertFalse(PrepOrder.shouldYield(working: rest, next: PrepStep(id: "a", stage: .head), playing: nil))
    XCTAssertFalse(PrepOrder.shouldYield(working: rest, next: nil, playing: nil))
  }

  func testAHeadOnlyMakesWayForThePlayingEpisode() {
    let head = PrepStep(id: "a", stage: .head)
    XCTAssertFalse(
      PrepOrder.shouldYield(working: head, next: PrepStep(id: "b", stage: .head), playing: nil))
    XCTAssertTrue(
      PrepOrder.shouldYield(working: head, next: PrepStep(id: "p", stage: .rest), playing: "p"))
  }

  func testThePlayingEpisodesRestDoesNotStopForAnotherHeadAndTheOldEpisodeMakesWayForIt() {
    // V (an earlier episode) still wants its head; U was just started and has its rest to do.
    let works = [work("v", head: true, rest: false), work("u", head: false, rest: true)]
    XCTAssertEqual(
      PrepOrder.nextStep(works, playing: "u", upNext: []), PrepStep(id: "u", stage: .rest))
    XCTAssertFalse(
      PrepOrder.shouldYield(
        working: PrepStep(id: "u", stage: .rest), next: PrepStep(id: "v", stage: .head),
        playing: "u"))
    XCTAssertTrue(
      PrepOrder.shouldYield(
        working: PrepStep(id: "v", stage: .head), next: PrepStep(id: "u", stage: .rest),
        playing: "u"), "and V's stopped head is not taken again before U's rest")
  }

  func testTheHeadIsThreeMinutesWhichIsTheFirstTwoTranscriptPieces() {
    XCTAssertEqual(PrepRules.headSeconds, 180)
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
