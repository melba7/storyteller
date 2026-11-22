import XCTest

@testable import PodcastAds

/// What a tap on Skip ad does: nothing, a skip of a known ad, or a jump that notes a miss.
final class AdSkipNowDecideTests: XCTestCase {
  private func ad(_ start: Double, _ end: Double, kind: AdKind = .ad) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: kind, advertiser: "A", confidence: .sure, firstWords: "")
  }

  private func file(_ ads: [FoundAd], undone: [UndoneAd] = []) -> AdsFile {
    AdsFile(
      sha256: "x", detector: "d", detectorVersion: "1", osVersion: "26", duration: 3000, ads: ads,
      undone: undone, trims: [])
  }

  private func decide(
    _ position: Double, _ file: AdsFile?, settings: AdSkipSettings = AdSkipSettings(),
    last: AdSkip? = nil, age: Double = 100
  ) -> AdSkipNow.Action {
    AdSkipNow.decide(
      position: position, duration: 3000, file: file, settings: settings, lastSkip: last,
      lastSkipAge: age)
  }

  func testJustAfterAnAutomaticSkipNothingIsDone() {
    let skipped = AdSkip(ad: ad(100, 130), target: 130)
    XCTAssertEqual(
      decide(130.4, file([ad(100, 130)]), last: skipped, age: 1.5), .nothing(at: 130.4))
    // Three seconds past the target is no longer "just after".
    XCTAssertEqual(decide(133.5, file([]), last: skipped, age: 1.5), .miss(to: 163.5))
    // An old skip is no excuse either.
    XCTAssertEqual(decide(130.4, file([]), last: skipped, age: 3.5), .miss(to: 160.4))
  }

  func testATapWellBeforeTheLastSkipsTargetStillJumps() {
    let skipped = AdSkip(ad: ad(100, 130), target: 130)
    // The listener went back to 20 two seconds after the skip: the tap is a real one.
    XCTAssertEqual(decide(20, file([]), last: skipped, age: 2), .miss(to: 50))
    // Half a second before the target is still the listener catching up with the skip.
    XCTAssertEqual(decide(129.6, file([]), last: skipped, age: 2), .nothing(at: 129.6))
    XCTAssertEqual(decide(130.5, file([]), last: skipped, age: 2), .nothing(at: 130.5))
  }

  func testInsideAKnownAdItIsASkipOfThatAd() {
    let first = ad(100, 160)
    let plug = ad(160.4, 175, kind: .ownPlug)
    let result = decide(110, file([first, plug]))
    XCTAssertEqual(result, .skip(AdSkip(ad: first, target: 175, chained: [plug])))
  }

  func testAKnownAdIsSkippedWhateverTheSwitchesSay() {
    let off = AdSkipSettings(skipAds: false, skipOwnPlugs: false, skipPromos: false)
    let found = ad(100, 160)
    XCTAssertEqual(decide(110, file([found]), settings: off), .skip(AdSkip(ad: found, target: 160)))
  }

  func testWithNoAdKnownItJumpsAheadAndNotesAMiss() {
    XCTAssertEqual(decide(500, file([ad(100, 160)])), .miss(to: 530))
    XCTAssertEqual(decide(500, nil), .miss(to: 530))
  }

  func testALandingInsideASkippedAdMovesToItsEnd() {
    // 500 + 30 = 530 is inside the ad from 520 to 560.
    XCTAssertEqual(decide(500, file([ad(520, 560)])), .miss(to: 560))
    // Two ads that follow at once.
    XCTAssertEqual(
      decide(500, file([ad(520, 560), ad(560.2, 575, kind: .ownPlug)])), .miss(to: 575))
  }

  func testALandingInsideAnAdThatIsNotSkippedStaysWhereItIs() {
    let promo = ad(520, 560, kind: .promo)
    let promosOff = AdSkipSettings(skipPromos: false)
    XCTAssertEqual(decide(500, file([promo]), settings: promosOff), .miss(to: 530))
    let undone = file([ad(520, 560)], undone: [UndoneAd(start: 520, end: 560)])
    XCTAssertEqual(decide(500, undone), .miss(to: 530))
  }

  func testALandingAtTheEndOfTheEpisodeStaysBeforeIt() {
    XCTAssertEqual(decide(2990, file([])), .miss(to: 2999))
  }
}
