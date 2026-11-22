import XCTest

@testable import PodcastAds

/// What the Skip ad button and the player's own moves ask of the skipper.
final class AdSkipperLastSkipTests: XCTestCase {
  private func ad(_ start: Double, _ end: Double, kind: AdKind = .ad) -> FoundAd {
    FoundAd(start: start, end: end, kind: kind, advertiser: "A", confidence: .sure, firstWords: "")
  }

  private func skipper(_ ads: [FoundAd], settings: AdSkipSettings = AdSkipSettings()) -> AdSkipper {
    let file = AdsFile(
      sha256: "x", detector: "d", detectorVersion: "1", osVersion: "26", duration: 3000, ads: ads)
    return AdSkipper(file: file, settings: settings)
  }

  func testTheLastSkipAndWhenItWasMadeCanBeRead() {
    var skipper = skipper([ad(100, 130)])
    XCTAssertNil(skipper.lastSkip)
    let skip = skipper.reached(position: 100, rate: 1, duration: 3000, now: 50)
    XCTAssertNotNil(skip)
    XCTAssertEqual(skipper.lastSkip?.skip, skip)
    XCTAssertEqual(skipper.lastSkip?.at, 50)
  }

  func testASkipFromTheButtonCanBeUndone() {
    var skipper = skipper([ad(100, 130)])
    skipper.noteSkip(AdSkip(ad: ad(100, 130), target: 130), now: 10)
    XCTAssertEqual(skipper.undo(now: 12)?.start, 100)
    XCTAssertNil(skipper.lastSkip)
  }

  func testLandingGivesTheEndOfTheSkippedAdThatHoldsAPlace() {
    let skipper = skipper([ad(100, 130), ad(130.2, 140, kind: .ownPlug)])
    XCTAssertEqual(skipper.landing(for: 110, duration: 3000), 140)
    XCTAssertEqual(skipper.landing(for: 100, duration: 3000), 140)
    XCTAssertEqual(skipper.landing(for: 99, duration: 3000), 99)
    XCTAssertEqual(skipper.landing(for: 140, duration: 3000), 140)
  }

  func testLandingLeavesAnAdThatIsNotSkipped() {
    let skipper = skipper([ad(100, 130, kind: .promo)], settings: AdSkipSettings(skipPromos: false))
    XCTAssertEqual(skipper.landing(for: 110, duration: 3000), 110)
  }
}
