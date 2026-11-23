import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// The two numbers "seconds of an ad heard before the skip" and "after the skip". The episode of
/// `scoreEpisode` is 100 seconds long.
final class AdScoreHeardTests: XCTestCase {
  private func score(
    _ truth: [(Double, Double, String)], _ found: [FoundAd], maybe: [(Double, Double, String)] = [],
    settings: AdSkipSettings = AdSkipSettings()
  ) -> EpisodeScore {
    AdScore.score(
      episode: scoreEpisode(truth: truth, maybe: maybe), found: found, settings: settings)
  }

  private func assertHeard(
    _ score: EpisodeScore, before: Double, after: Double, _ message: String = "",
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(score.heardBeforeSeconds, before, accuracy: 1e-9, "before. \(message)", file: file, line: line)
    XCTAssertEqual(score.heardAfterSeconds, after, accuracy: 1e-9, "after. \(message)", file: file, line: line)
  }

  func testASkipThatStartsBeforeTheAdHearsNothingBeforeIt() {
    let early = score([(20, 40, "sponsor")], [foundAd(15, 40)])
    assertHeard(early, before: 0, after: 0)
    XCTAssertEqual(early.cutSeconds, 5, accuracy: 1e-9)
  }

  func testASkipThatStartsLateLeavesTheStartOfTheAdHeard() {
    assertHeard(score([(20, 40, "sponsor")], [foundAd(27, 40)]), before: 7, after: 0)
  }

  func testASkipThatEndsEarlyLeavesTheEndOfTheAdHeard() {
    assertHeard(score([(20, 40, "sponsor")], [foundAd(20, 33)]), before: 0, after: 7)
    assertHeard(score([(20, 40, "sponsor")], [foundAd(27, 33)]), before: 7, after: 7)
  }

  func testAMissedAdIsNotCountedHereOnlyAsMissed() {
    let missed = score([(20, 40, "sponsor"), (60, 70, "sponsor")], [foundAd(62, 70)])
    // Only the stretch the skip touches counts: 2 seconds before it. The 20 seconds of the missed
    // stretch are in `heardSeconds`, not in the new numbers.
    assertHeard(missed, before: 2, after: 0)
    XCTAssertEqual(missed.heardSeconds, 22, accuracy: 1e-9)
    assertHeard(score([(20, 40, "sponsor")], []), before: 0, after: 0)
  }

  func testASkipThatOnlyTouchesTheEdgeOfAnAdDoesNotReachIt() {
    assertHeard(score([(20, 40, "sponsor")], [foundAd(10, 20), foundAd(40, 50)]), before: 0, after: 0)
  }

  func testOneSkipOverTwoMarkedStretchesIsCountedForEach() {
    let truth: [(Double, Double, String)] = [(20, 30, "sponsor"), (50, 60, "sponsor")]
    assertHeard(score(truth, [foundAd(25, 55)]), before: 5, after: 5, "starts inside the first, ends inside the second")
    assertHeard(score(truth, [foundAd(15, 65)]), before: 0, after: 0, "covers both")
    assertHeard(score(truth, [foundAd(22, 65)]), before: 2, after: 0)
    assertHeard(score(truth, [foundAd(15, 52)]), before: 0, after: 8)
  }

  func testSeveralSkipsOnOneAdCountFromTheFirstStartToTheLastEnd() {
    let split = score([(20, 40, "sponsor")], [foundAd(22, 26), foundAd(34, 38)])
    // The gap between the two skips is heard, but it is neither before nor after.
    assertHeard(split, before: 2, after: 2)
    XCTAssertEqual(split.heardSeconds, 12, accuracy: 1e-9)
    assertHeard(score([(20, 40, "sponsor")], [foundAd(27, 30), foundAd(29, 40)]), before: 7, after: 0)
    assertHeard(score([(20, 40, "sponsor")], [foundAd(27, 40), foundAd(27, 40)]), before: 7, after: 0)
  }

  func testASkipInsideAnAdHearsBothEnds() {
    assertHeard(score([(20, 40, "sponsor")], [foundAd(28, 30)]), before: 8, after: 10)
  }

  func testOnlySkipsThePlayerMakesCount() {
    let truth: [(Double, Double, String)] = [(20, 40, "sponsor")]
    assertHeard(score(truth, [foundAd(27, 40, .guess)]), before: 0, after: 0, "a guess is not skipped")
    assertHeard(score(truth, [foundAd(27, 40, .unsure)]), before: 7, after: 0, "an unsure ad is skipped")
    // A kind the settings do not skip is no skip.
    assertHeard(
      score(truth, [foundAd(27, 40, kind: .ownPlug)], settings: AdSkipSettings(skipOwnPlugs: false)),
      before: 0, after: 0)
  }

  func testOnlyStretchesTheSettingsSkipAreMeasured() {
    let plug: [(Double, Double, String)] = [(20, 40, "host_ask")]
    let off = AdSkipSettings(skipOwnPlugs: false)
    assertHeard(
      score(plug, [foundAd(27, 40, kind: .ownPlug)], settings: off), before: 0, after: 0)
    assertHeard(score(plug, [foundAd(27, 40, kind: .ownPlug)]), before: 7, after: 0)
    // A doubtful mark is neither ad nor show.
    assertHeard(score([], [foundAd(62, 70)], maybe: [(60, 70, "sponsor")]), before: 0, after: 0)
  }

  func testStretchesAreCutToTheEpisodeAndBadNumbersCountForNothing() {
    assertHeard(score([(90, 130, "sponsor")], [foundAd(95, 200)]), before: 5, after: 0)
    let odd = score(
      [(20, 40, "sponsor")],
      [foundAd(.nan, 40), foundAd(27, .infinity), foundAd(30, 30), foundAd(35, 25)])
    XCTAssertFalse(odd.heardBeforeSeconds.isNaN)
    XCTAssertFalse(odd.heardAfterSeconds.isNaN)
    // The skip to infinity is cut to the end of the episode and starts 7 seconds into the ad.
    assertHeard(odd, before: 7, after: 0)
  }

  func testTheRunAddsTheNumbersUpForEpisodesAndShows() {
    let one = scoreEpisode(id: "1", feed: "fa", show: "A", truth: [(20, 40, "sponsor")])
    let two = scoreEpisode(
      id: "2", feed: "fb", show: "B", truth: [(20, 30, "sponsor"), (50, 60, "sponsor")])
    let three = scoreEpisode(id: "3", feed: "fa", show: "A", truth: [(20, 40, "sponsor")])
    let card = AdScoreRun.run(episodes: [one, two, three], habits: ShowHabits()) { episode, _ in
      switch episode.id {
      case "1": return [foundAd(27, 40)]  // 7 before
      case "2": return [foundAd(25, 55)]  // 5 before, 5 after
      default: return [foundAd(20, 31)]  // 9 after
      }
    }
    XCTAssertEqual(card.episodes.map(\.heardBeforeSeconds), [7, 5, 0])
    XCTAssertEqual(card.episodes.map(\.heardAfterSeconds), [0, 5, 9])
    XCTAssertEqual(card.total.heardBeforeSeconds, 12, accuracy: 1e-9)
    XCTAssertEqual(card.total.heardAfterSeconds, 14, accuracy: 1e-9)
    let byFeed = Dictionary(uniqueKeysWithValues: card.shows.map { ($0.feed, $0.total) })
    XCTAssertEqual(byFeed["fa"]?.heardBeforeSeconds ?? -1, 7, accuracy: 1e-9)
    XCTAssertEqual(byFeed["fa"]?.heardAfterSeconds ?? -1, 9, accuracy: 1e-9)
    XCTAssertEqual(byFeed["fb"]?.heardBeforeSeconds ?? -1, 5, accuracy: 1e-9)
    XCTAssertEqual(byFeed["fb"]?.heardAfterSeconds ?? -1, 5, accuracy: 1e-9)
  }
}
