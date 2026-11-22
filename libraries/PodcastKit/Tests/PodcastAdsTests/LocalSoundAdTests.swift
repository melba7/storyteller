import XCTest

@testable import PodcastAds

/// A taught sound found in a file, as an ad of the episode's ads file.
final class LocalSoundAdTests: XCTestCase {
  func testASoundIsASureAdOfItsKind() {
    XCTAssertEqual(
      LocalAdsFile.soundAd(sort: "sponsor", who: "Acme", start: 12, end: 42),
      FoundAd(start: 12, end: 42, kind: .ad, advertiser: "Acme", confidence: .sure, firstWords: ""))
    XCTAssertEqual(LocalAdsFile.soundAd(sort: "network_promo", who: "", start: 0, end: 20)?.kind, .promo)
    XCTAssertEqual(LocalAdsFile.soundAd(sort: "host_ask", who: "", start: 0, end: 20)?.kind, .ownPlug)
    XCTAssertEqual(LocalAdsFile.soundAd(sort: "intro_credits", who: "", start: 0, end: 20)?.kind, .credits)
  }

  func testASortThatIsNotKnownOrAStretchThatIsNotOneIsLeftOut() {
    XCTAssertNil(LocalAdsFile.soundAd(sort: "weather", who: "", start: 0, end: 20))
    XCTAssertNil(LocalAdsFile.soundAd(sort: "sponsor", who: "", start: 20, end: 20))
    XCTAssertNil(LocalAdsFile.soundAd(sort: "sponsor", who: "", start: 30, end: 20))
    XCTAssertNil(LocalAdsFile.soundAd(sort: "sponsor", who: "", start: -1, end: 20))
    XCTAssertNil(LocalAdsFile.soundAd(sort: "sponsor", who: "", start: 0, end: .infinity))
    XCTAssertNil(LocalAdsFile.soundAd(sort: "sponsor", who: "", start: .nan, end: 20))
  }
}
