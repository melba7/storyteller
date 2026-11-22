import XCTest

@testable import PodcastAds

/// The kind-aware joining of ads from several finders.
final class AdJoinTests: XCTestCase {
  private func ad(
    _ start: Double, _ end: Double, _ kind: AdKind = .ad, _ name: String = "",
    _ sure: AdConfidence = .sure, words: String = ""
  ) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: kind, advertiser: name, confidence: sure, firstWords: words)
  }

  func testAdsOfOneKindThatOverlapOrTouchBecomeOne() {
    let joined = AdJoin.join([
      ad(40, 70, .ad, "", .unsure, words: "later"), ad(0, 45, .ad, "Ridge", .sure, words: "first"),
      ad(70.4, 90, .ad, "Casper", .guess), ad(200, 230),
    ])
    XCTAssertEqual(joined.map(\.start), [0, 200])
    XCTAssertEqual(joined[0].end, 90)
    XCTAssertEqual(joined[0].confidence, .sure)
    XCTAssertEqual(joined[0].advertiser, "Ridge", "the longer one's name stands")
    XCTAssertEqual(joined[0].firstWords, "first", "the earlier one's first words stand")
  }

  func testAnEmptyNameTakesTheOthers() {
    let joined = AdJoin.join([ad(0, 60, .ad, ""), ad(50, 70, .ad, "Casper")])
    XCTAssertEqual(joined.first?.advertiser, "Casper")
  }

  func testANegativeTouchingJoinsOnlyRealOverlaps() {
    XCTAssertEqual(AdJoin.join([ad(0, 20), ad(20, 40)], touching: -0.001).count, 2)
    XCTAssertEqual(AdJoin.join([ad(0, 20), ad(19, 40)], touching: -0.001).count, 1)
  }

  func testAnAdTouchingLongerCreditsStaysAnAdAndTheCreditsStayCredits() {
    let joined = AdJoin.join([ad(100, 130), ad(130, 190, .credits)])
    XCTAssertEqual(joined.map(\.kind), [.ad, .credits])
    XCTAssertEqual(joined.map(\.start), [100, 130])
    XCTAssertEqual(joined.map(\.end), [130, 190])
  }

  func testAnAdOverlappingLongerCreditsKeepsItsWholeStretch() {
    let joined = AdJoin.join([ad(100, 130), ad(120, 200, .credits, "C", .unsure, words: "cr")])
    XCTAssertEqual(joined.map(\.kind), [.ad, .credits])
    XCTAssertEqual(joined.map(\.start), [100, 130])
    XCTAssertEqual(joined.map(\.end), [130, 200])
    XCTAssertEqual(joined[1].advertiser, "C")
    XCTAssertEqual(joined[1].confidence, .unsure)
    XCTAssertEqual(joined[1].firstWords, "cr")
  }

  func testAPromoInsideALongerAdIsDropped() {
    XCTAssertEqual(AdJoin.join([ad(100, 200), ad(120, 160, .promo)]).map(\.kind), [.ad])
  }

  func testAPromoStickingOutBy20SecondsKeepsThatPart() {
    let joined = AdJoin.join([ad(100, 200), ad(150, 220, .promo, "P")])
    XCTAssertEqual(joined.map(\.kind), [.ad, .promo])
    XCTAssertEqual(joined.map(\.start), [100, 200])
    XCTAssertEqual(joined.map(\.end), [200, 220])
    XCTAssertEqual(joined[1].advertiser, "P")
  }

  func testACutCanLeaveAPartBeforeAndAfter() {
    let joined = AdJoin.join([ad(100, 130, .promo), ad(0, 300, .credits), ad(150, 170)])
    XCTAssertEqual(joined.map(\.kind), [.credits, .promo, .credits, .ad, .credits])
    XCTAssertEqual(joined.map(\.start), [0, 100, 130, 150, 170])
    XCTAssertEqual(joined.map(\.end), [100, 130, 150, 170, 300])
  }

  func testALeftOverPartShorterThanTheMinimumIsDropped() {
    // The promo's 5 seconds before the ad are too short to keep.
    let joined = AdJoin.join([ad(100, 200), ad(95, 150, .promo)])
    XCTAssertEqual(joined.map(\.kind), [.ad])
    // An ad nothing cuts is kept as it is even when it is short.
    XCTAssertEqual(AdJoin.join([ad(100, 105)]).count, 1)
  }

  func testTheKindsRankAdPromoOwnPlugCredits() {
    let joined = AdJoin.join([
      ad(0, 100, .credits), ad(0, 100, .ownPlug), ad(0, 100, .promo),
    ])
    XCTAssertEqual(joined.map(\.kind), [.promo])
    XCTAssertEqual(
      AdJoin.join([ad(0, 100, .credits), ad(0, 100, .ownPlug)]).map(\.kind), [.ownPlug])
    XCTAssertEqual(
      AdJoin.join([ad(0, 100, .promo), ad(0, 100, .ad)]).map(\.kind), [.ad])
  }

  func testTheResultIsInOrderAndNothingOverlaps() {
    let joined = AdJoin.join([
      ad(300, 400, .credits), ad(0, 320, .promo), ad(50, 80), ad(500, 520, .ownPlug), ad(510, 560),
    ])
    XCTAssertEqual(joined.map(\.start), joined.map(\.start).sorted())
    for (a, b) in zip(joined, joined.dropFirst()) { XCTAssertLessThanOrEqual(a.end, b.start) }
  }

  func testMergeIsJoin() {
    let ads = [ad(100, 130), ad(120, 200, .credits)]
    XCTAssertEqual(AdHeadRules.merge(ads), AdJoin.join(ads))
    XCTAssertEqual(AdHeadRules.merge(ads, touching: -0.001), AdJoin.join(ads, touching: -0.001))
  }
}
