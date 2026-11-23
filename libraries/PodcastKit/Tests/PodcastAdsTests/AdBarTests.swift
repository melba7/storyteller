import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// The owner's bar with tiny made-up episodes (100 seconds long, see `scoreEpisode`).
final class AdBarTests: XCTestCase {
  private func bar(
    _ truth: [(Double, Double)], found: [(Double, Double)], maybe: [(Double, Double)] = []
  ) -> BarTotals {
    let episode = scoreEpisode(
      truth: truth.map { ($0.0, $0.1, "sponsor") }, maybe: maybe.map { ($0.0, $0.1, "sponsor") })
    return AdBar.score(episode: episode, found: found.map { foundAd($0.0, $0.1) })
  }

  func testCleanSkipPasses() {
    let result = bar([(20, 40)], found: [(20, 40)])
    XCTAssertEqual(result.breaks, 1)
    XCTAssertEqual(result.passed, 1)
    XCTAssertTrue(result.causes.isEmpty)
    XCTAssertEqual(result.episodeSeconds, 100)
  }

  func testAdsWithinOneSecondAreOneBreak() {
    XCTAssertEqual(bar([(20, 30), (31, 41)], found: []).breaks, 1)
    XCTAssertEqual(bar([(20, 30), (30.5, 40)], found: []).breaks, 1)
    XCTAssertEqual(bar([(20, 30), (31.5, 41.5)], found: []).breaks, 2)
  }

  func testJoinedBreakIsCountedOnceAndTheSmallGapIsNotCounted() {
    // One skip over both ads and the half second between them: the gap is neither before nor after.
    let result = bar([(20, 30), (30.5, 40)], found: [(20, 40)])
    XCTAssertEqual(result.breaks, 1)
    XCTAssertEqual(result.passed, 1)
  }

  func testBreaksUnderTenSecondsAreNotScored() {
    XCTAssertEqual(bar([(20, 29.9)], found: []).breaks, 0)
    XCTAssertEqual(bar([(20, 30)], found: []).breaks, 1)
    // Two short ads that join into a long break do count.
    XCTAssertEqual(bar([(20, 25), (25.5, 31)], found: []).breaks, 1)
  }

  func testEachCause() {
    func cause(_ found: [(Double, Double)]) -> [String: Int] {
      bar([(20, 40)], found: found).causes
    }
    XCTAssertEqual(cause([]), ["missed": 1])
    XCTAssertEqual(cause([(60, 70)]), ["missed": 1])
    XCTAssertEqual(cause([(27, 40)]), ["startsLate": 1])
    XCTAssertEqual(cause([(20, 33)]), ["stopsEarly": 1])
    XCTAssertEqual(cause([(20, 26), (34, 40)]), ["gapInside": 1])
    XCTAssertEqual(cause([(10, 40)]), ["startsEarly": 1])
    XCTAssertEqual(cause([(20, 50)]), ["landsTooFar": 1])
  }

  func testOnlyTheFirstCauseCounts() {
    func cause(_ found: [(Double, Double)]) -> [String: Int] {
      bar([(20, 40)], found: found).causes
    }
    // Late and early at the same time: starts late wins. Stops early and lands too far, too.
    XCTAssertEqual(cause([(28, 34)]), ["startsLate": 1])
    XCTAssertEqual(cause([(20, 30), (60, 70)]), ["stopsEarly": 1])
    // The gap comes after late and early ends; cutting before beats cutting after.
    XCTAssertEqual(cause([(10, 26), (34, 50)]), ["gapInside": 1])
    XCTAssertEqual(cause([(10, 50)]), ["startsEarly": 1])
  }

  func testFiveSecondsExactlyPassesAndMoreFails() {
    XCTAssertEqual(bar([(20, 40)], found: [(25, 40)]).passed, 1)
    XCTAssertEqual(bar([(20, 40)], found: [(20, 35)]).passed, 1)
    XCTAssertEqual(bar([(20, 40)], found: [(15, 40)]).passed, 1)
    XCTAssertEqual(bar([(20, 40)], found: [(20, 45)]).passed, 1)
    XCTAssertEqual(bar([(20, 40)], found: [(20, 26), (31, 40)]).passed, 1)
    XCTAssertEqual(bar([(20, 40)], found: [(25.01, 40)]).passed, 0)
    XCTAssertEqual(bar([(20, 40)], found: [(14.99, 40)]).causes, ["startsEarly": 1])
    XCTAssertEqual(bar([(20, 40)], found: [(20, 45.01)]).causes, ["landsTooFar": 1])
  }

  func testOneSkipOverTwoBreaksAndTheShowBetween() {
    let result = bar([(20, 30), (40, 50)], found: [(20, 50)])
    XCTAssertEqual(result.breaks, 2)
    XCTAssertEqual(result.passed, 0)
    XCTAssertEqual(result.causes, ["landsTooFar": 1, "startsEarly": 1])
  }

  func testNeutralStretchesAreNeitherAdNorShow() {
    XCTAssertEqual(bar([(20, 30)], found: [(20, 40)], maybe: [(30, 40)]).passed, 1)
    XCTAssertEqual(bar([(20, 30)], found: [(20, 40)]).causes, ["landsTooFar": 1])
    // Neutral stretches do not make a break of their own.
    XCTAssertEqual(bar([], found: [], maybe: [(20, 40)]).breaks, 0)
    XCTAssertEqual(bar([], found: [(20, 40)], maybe: [(20, 40)]).noAdSkips, 0)
  }

  func testSkipsWithNoAd() {
    let alone = bar([(20, 40)], found: [(20, 40), (60, 70)])
    XCTAssertEqual(alone.noAdSkips, 1)
    XCTAssertEqual(alone.noAdSeconds, 10, accuracy: 1e-9)
    // Half a second is not enough; a little more is.
    XCTAssertEqual(bar([], found: [(60, 60.5)]).noAdSkips, 0)
    XCTAssertEqual(bar([], found: [(60, 60.6)]).noAdSkips, 1)
    // Overlapping skips are one.
    XCTAssertEqual(bar([], found: [(60, 70), (65, 75)]).noAdSkips, 1)
  }

  func testSkipOverAShortAdIsNotASkipWithNoAd() {
    let result = bar([(20, 25)], found: [(15, 30)])
    XCTAssertEqual(result.breaks, 0)
    XCTAssertEqual(result.noAdSkips, 0)
  }

  func testFirstThreeMinutesAreCountedApart() {
    let result = bar(
      [(170, 180), (185, 200), (230, 250)], found: [(170, 180), (230, 250)])
    XCTAssertEqual(result.breaks, 3)
    XCTAssertEqual(result.earlyBreaks, 1)
    XCTAssertEqual(result.earlyPassed, 1)
    let late = bar([(179, 200), (230, 250)], found: [(230, 250)])
    XCTAssertEqual(late.breaks, 2)
    XCTAssertEqual(late.earlyBreaks, 1)
    XCTAssertEqual(late.earlyPassed, 0)
    XCTAssertEqual(late.passed, 1)
  }

  func testUnsureSkipsCountAndGuessesDoNot() {
    let episode = scoreEpisode(truth: [(20, 40, "sponsor")])
    XCTAssertEqual(AdBar.score(episode: episode, found: [foundAd(20, 40, .unsure)]).passed, 1)
    XCTAssertEqual(AdBar.score(episode: episode, found: [foundAd(20, 40, .guess)]).passed, 0)
  }

  func testTotalsAddUp() {
    var total = bar([(20, 40)], found: [(20, 40), (60, 70)])
    total += bar([(20, 40)], found: [])
    XCTAssertEqual(total.breaks, 2)
    XCTAssertEqual(total.passed, 1)
    XCTAssertEqual(total.count(.missed), 1)
    XCTAssertEqual(total.noAdSkips, 1)
    XCTAssertEqual(total.episodeSeconds, 200)
    XCTAssertEqual(total.noAdPerHour, 1 / (200.0 / 3600), accuracy: 1e-9)
    XCTAssertEqual(total.rate, 0.5, accuracy: 1e-9)
  }
}
