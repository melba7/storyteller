import XCTest

@testable import PodcastAds

/// The Skip ad button: where it takes the listener.
final class AdSkipNowTests: XCTestCase {
  private func ad(_ start: Double, _ end: Double, kind: AdKind = .ad) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: kind, advertiser: "A", confidence: .sure, firstWords: "")
  }

  func testInsideAnAdItGoesToItsEnd() {
    let found = ad(100, 160)
    let result = AdSkipNow.target(position: 120, duration: 3000, ads: [found])
    XCTAssertEqual(result.to, 160)
    XCTAssertEqual(result.known, found)
  }

  func testTwoSecondsBeforeAnAdCountsAsInsideIt() {
    let found = ad(100, 160)
    XCTAssertEqual(AdSkipNow.target(position: 98, duration: 3000, ads: [found]).to, 160)
    XCTAssertNil(AdSkipNow.target(position: 97.9, duration: 3000, ads: [found]).known)
    XCTAssertNil(AdSkipNow.target(position: 160, duration: 3000, ads: [found]).known)
  }

  func testAdsThatFollowWithinHalfASecondAreSkippedToo() {
    let first = ad(100, 160)
    let plug = ad(160.4, 175, kind: .ownPlug)
    let later = ad(176, 190)
    let result = AdSkipNow.target(position: 110, duration: 3000, ads: [later, plug, first])
    XCTAssertEqual(result.to, 175)
    XCTAssertEqual(result.known, first)
  }

  func testOutsideAnyAdItGoesThirtySecondsAhead() {
    let result = AdSkipNow.target(position: 500, duration: 3000, ads: [ad(100, 160)])
    XCTAssertEqual(result.to, 530)
    XCTAssertNil(result.known)
    XCTAssertEqual(AdSkipNow.target(position: 10, duration: nil, ads: []).to, 40)
  }

  func testItNeverGoesPastOneSecondBeforeTheEnd() {
    XCTAssertEqual(AdSkipNow.target(position: 990, duration: 1000, ads: []).to, 999)
    XCTAssertEqual(AdSkipNow.target(position: 980, duration: 1000, ads: []).to, 999)
  }

  func testItNeverGoesBehindThePlayhead() {
    XCTAssertEqual(AdSkipNow.target(position: 999.5, duration: 1000, ads: []).to, 999.5)
    XCTAssertEqual(AdSkipNow.target(position: 1200, duration: 1000, ads: []).to, 1200)
  }

  func testAnAdAtTheEndLandsJustBeforeTheEnd() {
    let result = AdSkipNow.target(position: 950, duration: 1000, ads: [ad(940, 1000)])
    XCTAssertEqual(result.to, 999.95, accuracy: 0.001)
    XCTAssertNotNil(result.known)
  }

  func testAFileGivesItsAdsWithTheTrimsAndWhateverWasUndone() {
    let file = AdsFile(
      sha256: "x", detector: "d", detectorVersion: "1", osVersion: "26", duration: 3000,
      ads: [ad(100, 160), ad(200, 260)], undone: [UndoneAd(start: 200, end: 260)],
      trims: [AdTrim(adStart: 100, end: 140)])
    // The first ad ends where the listener trimmed it, and the undone one is still an ad here.
    XCTAssertEqual(AdSkipNow.target(position: 110, duration: 3000, file: file).to, 140)
    let undone = AdSkipNow.target(position: 210, duration: 3000, file: file)
    XCTAssertEqual(undone.to, 260)
    XCTAssertNotNil(undone.known)
    XCTAssertEqual(AdSkipNow.target(position: 500, duration: 3000, file: nil).to, 530)
  }

  func testAnUnreadablePlayheadIsTreatedAsTheStart() {
    XCTAssertEqual(AdSkipNow.target(position: .nan, duration: 1000, ads: []).to, 30)
  }
}
