import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// An episode of ten lines (100 seconds) with the marked stretches given as (start, end, sort).
func scoreEpisode(
  id: String = "e1", feed: String = "feed1", show: String = "Show One",
  truth: [(Double, Double, String)] = [], maybe: [(Double, Double, String)] = []
) -> TeachingEpisode {
  TeachingEpisode(
    id: id, feed: feed, show: show, title: "Title", transcript: makeTranscript(talk(10)),
    truth: truth.map { TeachingTruth(start: $0.0, end: $0.1, sort: $0.2) },
    maybe: maybe.map { TeachingTruth(start: $0.0, end: $0.1, sort: $0.2) }, onShelf: true)
}

func foundAd(
  _ start: Double, _ end: Double, kind: AdKind = .ad, _ confidence: AdConfidence = .sure
) -> FoundAd {
  FoundAd(
    start: start, end: end, kind: kind, advertiser: "X", confidence: confidence, firstWords: "")
}

final class AdScoreTests: XCTestCase {
  func testAdCaughtAtExactlyHalfAndNotBelow() {
    let episode = scoreEpisode(truth: [(10, 20, "sponsor")])
    let half = AdScore.score(episode: episode, found: [foundAd(10, 15)])
    XCTAssertEqual(half.ads, 1)
    XCTAssertEqual(half.caught, 1)
    XCTAssertEqual(half.adSeconds, 10, accuracy: 1e-9)
    XCTAssertEqual(half.heardSeconds, 5, accuracy: 1e-9)
    XCTAssertEqual(half.cutSeconds, 0, accuracy: 1e-9)
    XCTAssertEqual(half.wrongSkips, 0)
    let less = AdScore.score(episode: episode, found: [foundAd(10, 14.9)])
    XCTAssertEqual(less.caught, 0)
  }

  func testNothingFoundLeavesAllAdTimeHeard() {
    let score = AdScore.score(episode: scoreEpisode(truth: [(10, 20, "sponsor")]), found: [])
    XCTAssertEqual(score.caught, 0)
    XCTAssertEqual(score.heardSeconds, 10, accuracy: 1e-9)
    XCTAssertEqual(score.duration, 100)
  }

  func testNeutralStretchesAreNeitherAdNorShow() {
    let episode = scoreEpisode(truth: [(10, 20, "sponsor")], maybe: [(30, 40, "sponsor")])
    let score = AdScore.score(episode: episode, found: [foundAd(30, 40)])
    XCTAssertEqual(score.ads, 1)
    XCTAssertEqual(score.cutSeconds, 0, accuracy: 1e-9)
    XCTAssertEqual(score.wrongSkips, 0)
    XCTAssertEqual(AdScore.showSeconds(episode, AdSkipSettings()), 80, accuracy: 1e-9)
  }

  func testCreditsAreNotCountedByDefaultButNeutral() {
    let episode = scoreEpisode(truth: [(0, 10, "intro_credits")])
    let found = [foundAd(0, 10, kind: .credits)]
    let off = AdScore.score(episode: episode, found: found)
    XCTAssertEqual(off.ads, 0)
    XCTAssertEqual(off.cutSeconds, 0, accuracy: 1e-9)
    XCTAssertEqual(off.openingAds, 0)
    XCTAssertEqual(off.bySort["intro_credits"]?.ads, 1)
    XCTAssertEqual(off.bySort["intro_credits"]?.caught, 1)
    // A sponsor-kind skip over the credits is not a mistake: the stretch is neutral.
    let over = AdScore.score(episode: episode, found: [foundAd(0, 10)])
    XCTAssertEqual(over.cutSeconds, 0, accuracy: 1e-9)
    XCTAssertEqual(over.wrongSkips, 0)

    let on = AdScore.score(
      episode: episode, found: found, settings: AdSkipSettings(skipCredits: true))
    XCTAssertEqual(on.ads, 1)
    XCTAssertEqual(on.caught, 1)
    XCTAssertEqual(on.heardSeconds, 0, accuracy: 1e-9)
    XCTAssertEqual(on.openingAds, 1)
  }

  func testAnAdFoundTwiceCountsOnce() {
    let episode = scoreEpisode(truth: [(10, 20, "sponsor")])
    let score = AdScore.score(episode: episode, found: [foundAd(10, 20), foundAd(10, 20)])
    XCTAssertEqual(score.caught, 1)
    XCTAssertEqual(score.heardSeconds, 0, accuracy: 1e-9)
    XCTAssertEqual(score.cutSeconds, 0, accuracy: 1e-9)
    XCTAssertEqual(score.wrongSkips, 0)
  }

  func testOverlappingFoundAdsAreJoinedForCutSeconds() {
    let episode = scoreEpisode(truth: [(10, 20, "sponsor")])
    let score = AdScore.score(episode: episode, found: [foundAd(10, 16), foundAd(14, 22)])
    XCTAssertEqual(score.cutSeconds, 2, accuracy: 1e-9)
    XCTAssertEqual(score.wrongSkips, 0)
    XCTAssertEqual(score.heardSeconds, 0, accuracy: 1e-9)
  }

  func testAGuessIsNotSkipped() {
    let episode = scoreEpisode(truth: [(10, 20, "sponsor")])
    let score = AdScore.score(episode: episode, found: [foundAd(10, 20, .guess)])
    XCTAssertEqual(score.caught, 0)
    XCTAssertEqual(score.heardSeconds, 10, accuracy: 1e-9)
    XCTAssertEqual(score.bySort["sponsor"]?.caught, 0)
    let unsure = AdScore.score(episode: episode, found: [foundAd(10, 20, .unsure)])
    XCTAssertEqual(unsure.caught, 1)
  }

  func testCutSecondsAndWrongSkips() {
    let episode = scoreEpisode(truth: [(10, 20, "sponsor")])
    let show = AdScore.score(episode: episode, found: [foundAd(50, 60)])
    XCTAssertEqual(show.cutSeconds, 10, accuracy: 1e-9)
    XCTAssertEqual(show.wrongSkips, 1)
    // Only 2 of its 10 seconds are inside the marked ad: a wrong skip, and 8 seconds are cut.
    let mostly = AdScore.score(episode: episode, found: [foundAd(18, 28)])
    XCTAssertEqual(mostly.wrongSkips, 1)
    XCTAssertEqual(mostly.cutSeconds, 8, accuracy: 1e-9)
    // Half inside is not a wrong skip.
    let half = AdScore.score(episode: episode, found: [foundAd(15, 25)])
    XCTAssertEqual(half.wrongSkips, 0)
    XCTAssertEqual(half.cutSeconds, 5, accuracy: 1e-9)
  }

  func testAFoundAdOfAKindThatIsOffIsNotSkipped() {
    let episode = scoreEpisode(truth: [(40, 50, "host_ask")])
    let settings = AdSkipSettings(skipOwnPlugs: false)
    let score = AdScore.score(
      episode: episode, found: [foundAd(40, 50, kind: .ownPlug)], settings: settings)
    XCTAssertEqual(score.ads, 0)
    XCTAssertEqual(score.cutSeconds, 0, accuracy: 1e-9)
    XCTAssertEqual(score.bySort["host_ask"]?.ads, 1)
    XCTAssertEqual(score.bySort["host_ask"]?.caught, 1)
  }

  func testBySortUsesAnyFoundAdWhateverItsKind() {
    let episode = scoreEpisode(truth: [
      (10, 20, "sponsor"), (30, 40, "network_promo"), (50, 60, "host_ask"), (70, 80, "sponsor"),
    ])
    let score = AdScore.score(
      episode: episode, found: [foundAd(30, 36, kind: .ad), foundAd(70, 74, kind: .promo)])
    XCTAssertEqual(score.bySort.count, 4)
    XCTAssertEqual(score.bySort["sponsor"], SortScore(ads: 2, caught: 0, seconds: 20, heardSeconds: 16))
    XCTAssertEqual(
      score.bySort["network_promo"], SortScore(ads: 1, caught: 1, seconds: 10, heardSeconds: 4))
    XCTAssertEqual(
      score.bySort["host_ask"], SortScore(ads: 1, caught: 0, seconds: 10, heardSeconds: 10))
    XCTAssertEqual(score.bySort["intro_credits"], SortScore())
  }

  func testOpeningAdsStartWithinThirtySeconds() {
    let early = scoreEpisode(truth: [(5, 15, "sponsor"), (30, 40, "sponsor"), (31, 41, "sponsor")])
    let score = AdScore.score(episode: early, found: [])
    XCTAssertEqual(score.openingAds, 2)
    XCTAssertEqual(score.openingKnown, 0)
  }

  func testStretchesAreCutToTheEpisode() {
    let episode = scoreEpisode(truth: [(90, 130, "sponsor")])
    let score = AdScore.score(episode: episode, found: [foundAd(95, 200)])
    XCTAssertEqual(score.adSeconds, 10, accuracy: 1e-9)
    XCTAssertEqual(score.caught, 1)
    XCTAssertEqual(score.cutSeconds, 0, accuracy: 1e-9)
  }
}
