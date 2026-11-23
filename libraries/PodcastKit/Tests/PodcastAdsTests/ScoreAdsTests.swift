import XCTest

@testable import PodcastAds

/// The pure helpers of the scorecard's new rows: trimming a new finder's ads to what the older
/// ones left, turning sound stretches into ads, and what the phone's own sounds may learn from.
final class ScoreAdsTests: XCTestCase {
  private func ad(
    _ start: Double, _ end: Double, _ kind: AdKind = .ad, _ confidence: AdConfidence = .unsure,
    source: String? = nil
  ) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: kind, advertiser: "", confidence: confidence, firstWords: "",
      source: source)
  }

  private func spans(_ ads: [FoundAd]) -> [[Double]] { ads.map { [$0.start, $0.end] } }

  // MARK: outside

  func testANewAdThatOverlapsAnOldOneKeepsOnlyTheParts() {
    let old = [ad(100, 130, .ad, .sure)]
    let new = [ad(80, 160, source: "x")]
    // The old ad and one second beyond it on each side are left alone: 80 to 99 and 131 to 160.
    XCTAssertEqual(spans(ScoreAds.outside(new, of: old)), [[80, 99], [131, 160]])
    XCTAssertTrue(ScoreAds.outside(new, of: old).allSatisfy { $0.source == "x" })
  }

  func testAPartShorterThanAnAdIsDropped() {
    let old = [ad(100, 130, .ad, .sure)]
    // 90 to 99 is nine seconds, 131 to 135 is four.
    XCTAssertEqual(ScoreAds.outside([ad(90, 135)], of: old), [])
    XCTAssertEqual(spans(ScoreAds.outside([ad(89, 135)], of: old)), [[89, 99]])
  }

  func testAnAdInsideAnOldOneIsGoneAndOneApartIsKept() {
    let old = [ad(100, 200, .ad, .sure)]
    XCTAssertEqual(ScoreAds.outside([ad(120, 150)], of: old), [])
    XCTAssertEqual(spans(ScoreAds.outside([ad(300, 320)], of: old)), [[300, 320]])
    XCTAssertEqual(ScoreAds.outside([ad(300, 320)], of: []).count, 1)
  }

  func testSeveralOldAdsCutSeveralParts() {
    let old = [ad(150, 160, .ad, .sure), ad(100, 120, .ad, .sure), ad(158, 170, .ad, .sure)]
    let found = ScoreAds.outside([ad(90, 400)], of: old)
    // 90 to 99 is nine seconds and is dropped. Between 100-120 and 150-170 a second is left off
    // each side: 121 to 149. The two old ads that overlap are one hole.
    XCTAssertEqual(spans(found), [[121, 149], [171, 400]])
  }

  func testNothingAddedIsEverCloserToAnOldAdThanTheJoinTouches() {
    let old = [ad(100, 130, .ad, .sure)]
    let joined = AdJoin.join(old + ScoreAds.outside([ad(60, 300, source: "meaning")], of: old))
    // The old ad was not lengthened or upgraded, and the new parts keep their name.
    XCTAssertEqual(joined.first { $0.confidence == .sure }.map { [$0.start, $0.end] }, [100, 130])
    XCTAssertEqual(joined.filter { $0.source == "meaning" }.count, 2)
    XCTAssertEqual(joined.count, 3)
  }

  func testBadInputIsDroppedNotTrapped() {
    let bad = [ad(.nan, 50), ad(10, .infinity), ad(50, 40), ad(60, 60)]
    XCTAssertEqual(ScoreAds.outside(bad, of: [ad(.nan, 3)]), [])
    XCTAssertEqual(ScoreAds.outside([], of: [ad(1, 100)]), [])
  }

  // MARK: ads

  func testStretchesBecomeUnsureAdsOfTheirKindWithTheFindersName() {
    let made = ScoreAds.ads(
      [ScoreSpan(start: 20, end: 50, sort: "network_promo"), ScoreSpan(start: 60, end: 80)],
      source: ShowTuning.ownSound)
    XCTAssertEqual(made.map(\.kind), [.promo, .ad])
    XCTAssertTrue(made.allSatisfy { $0.confidence == .unsure && $0.source == "own-sound" })
    XCTAssertTrue(made.allSatisfy { $0.advertiser.isEmpty })
  }

  func testOnlyStretchesTheLengthOfAnAdAreKept() {
    let made = ScoreAds.ads(
      [
        ScoreSpan(start: 0, end: 9.9), ScoreSpan(start: 0, end: 10), ScoreSpan(start: 5, end: 305),
        ScoreSpan(start: 5, end: 305.5), ScoreSpan(start: -1, end: 30),
        ScoreSpan(start: .nan, end: 30), ScoreSpan(start: 10, end: .infinity),
        ScoreSpan(start: 10, end: 40, sort: "nonsense"),
      ], source: "x")
    XCTAssertEqual(spans(made), [[0, 10], [5, 305], [10, 40]])
    XCTAssertEqual(made.last?.kind, .ad)
  }

  // MARK: learnable

  func testOnlySureAdsOfTheOlderFindersAndOfTheListenerAreLearned() {
    let ads = [
      ad(10, 40, .ad, .sure), ad(50, 80, .promo, .sure), ad(90, 120, .ownPlug, .sure),
      ad(130, 160, .ad, .unsure), ad(170, 200, .ad, .sure, source: "own-sound"),
      ad(210, 240, .credits, .sure, source: "tap"), ad(.nan, 5, .ad, .sure),
    ]
    let learned = ScoreAds.learnable(ads)
    XCTAssertEqual(learned.map { [$0.start, $0.end] }, [[10, 40], [50, 80], [210, 240]])
    XCTAssertEqual(learned.map(\.sort), ["sponsor", "network_promo", "intro_credits"])
  }

  // MARK: moved

  func testMovedGivesTheStretchesInOrderAndKeepsTheRestOfTheAd() {
    let ads = [ad(200, 230, .promo, .unsure, source: "x"), ad(50, 80, .ad, .sure)]
    var asked: [ScoreSpan] = []
    let result = ScoreAds.moved(ads) { given in
      asked = given
      return given.map { ScoreSpan(start: $0.start - 1, end: $0.end + 2, sort: $0.sort) }
    }
    XCTAssertEqual(asked.map(\.start), [50, 200])
    XCTAssertEqual(asked.map(\.sort), ["sponsor", "network_promo"])
    XCTAssertEqual(spans(result), [[49, 82], [199, 232]])
    XCTAssertEqual(result[1].source, "x")
    XCTAssertEqual(result[1].kind, .promo)
    XCTAssertEqual(result[0].confidence, .sure)
  }

  func testMovedKeepsAnAdWhenTheMoveGivesNonsenseOrTheWrongCount() {
    let ads = [ad(50, 80), ad(100, 130)]
    let wrong = ScoreAds.moved(ads) { _ in [] }
    XCTAssertEqual(spans(wrong), [[50, 80], [100, 130]])
    let nonsense = ScoreAds.moved(ads) { given in
      [ScoreSpan(start: .nan, end: 5), ScoreSpan(start: given[1].end, end: given[1].start)]
    }
    XCTAssertEqual(spans(nonsense), [[50, 80], [100, 130]])
    XCTAssertEqual(ScoreAds.moved([]) { $0 }, [])
  }

  // MARK: ScoreEpisodeAds

  func testTheBoxKeepsAnEpisodesAdsAndKnowsWhatItNeverSaw() {
    let box = ScoreEpisodeAds()
    XCTAssertNil(box.ads(for: "e1"))
    box.put([ad(10, 30)], for: "e1")
    XCTAssertEqual(box.ads(for: "e1")?.count, 1)
    box.put([], for: "e1")
    XCTAssertEqual(box.ads(for: "e1"), [])
    XCTAssertNil(box.ads(for: "e2"))
  }
}
