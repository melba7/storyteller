import XCTest

@testable import PodcastAds

/// A remembered ad's exact edges win over a looser span that overlaps it.
final class AdJoinExactEdgesTests: XCTestCase {
  private func span(_ start: Double, _ end: Double, _ kind: AdKind = .ad) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: kind, advertiser: "", confidence: .sure, firstWords: "")
  }

  private func match(_ start: Double, _ end: Double, _ kind: AdKind = .ad) -> FoundAd {
    var ad = span(start, end, kind)
    ad.source = KnownAds.source
    ad.advertiser = "Acme"
    return ad
  }

  func testAnOverhangOnBothSidesIsCutBackToTheMatch() {
    let joined = AdJoin.join([span(90, 230), match(100, 220)])
    XCTAssertEqual(joined.map(\.start), [100])
    XCTAssertEqual(joined.map(\.end), [220])
  }

  func testAnOverhangOfExactlyFifteenSecondsIsCutAndOneLongerStays() {
    XCTAssertEqual(AdJoin.join([span(85, 120), match(100, 200)]).map(\.start), [100])
    XCTAssertEqual(AdJoin.join([span(84.9, 120), match(100, 200)]).map(\.start), [84.9])
    XCTAssertEqual(AdJoin.join([span(150, 215), match(100, 200)]).map(\.end), [200])
    XCTAssertEqual(AdJoin.join([span(150, 215.1), match(100, 200)]).map(\.end), [215.1])
  }

  func testEachEndIsJudgedOnItsOwn() {
    let joined = AdJoin.join([span(60, 210), match(100, 200)])
    XCTAssertEqual(joined.map(\.start), [60], "40 seconds before is probably another ad")
    XCTAssertEqual(joined.map(\.end), [200])
  }

  func testMatchesWithinTwoSecondsOfEachOtherAreOneBlock() {
    // The span starts in the gap between two matches. Within two seconds the gap is part of the
    // block, which begins before the span, so the start stays; farther apart the span's start is
    // cut back to the second match.
    let near = AdJoin.join([span(150.2, 330), match(100, 150), match(151.5, 320)])
    XCTAssertEqual(near.map(\.start), [100])
    XCTAssertEqual(near.map(\.end), [320])
    let apart = AdJoin.join([span(150.5, 330), match(100, 150), match(153, 320)])
    XCTAssertEqual(apart.map(\.start), [100, 153])
  }

  func testASpanThatOnlyTouchesOrMissesAMatchIsLeftAlone() {
    let joined = AdJoin.join([span(20, 100), match(100, 150)])
    XCTAssertEqual(joined.map(\.start), [20])
    XCTAssertEqual(joined.map(\.end), [150], "they touch, so they are one ad")
    let far = AdJoin.join([span(20, 98), match(100, 150)])
    XCTAssertEqual(far.map(\.end), [98, 150])
  }

  func testOnlyAMatchOfARememberedAdSetsEdges() {
    var other = span(100, 220)
    other.source = "meaning"
    let joined = AdJoin.join([span(90, 230), other])
    XCTAssertEqual(joined.map(\.start), [90])
    XCTAssertEqual(joined.map(\.end), [230])
  }

  func testTheMatchItselfIsNeverChanged() {
    let joined = AdJoin.join([match(100, 220), span(0, 400)])
    XCTAssertEqual(joined.map(\.start), [0])
    XCTAssertEqual(AdJoin.join([match(100, 220)]).map(\.start), [100])
    XCTAssertEqual(AdJoin.join([match(100, 220)]).map(\.end), [220])
  }

  func testAMatchOfAnotherKindStillSetsTheSpansEdgesBeforeTheKindsAreJoined() {
    let joined = AdJoin.join([span(90, 230, .promo), match(100, 220, .ad)])
    XCTAssertEqual(joined.map(\.kind), [.ad])
    XCTAssertEqual(joined.map(\.start), [100])
  }
}
