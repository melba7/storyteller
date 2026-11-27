import XCTest

@testable import PodcastAds

/// What a tap on Skip ad does: nothing, a skip of a known ad, or a jump that notes a miss.
final class AdSkipNowDecideTests: XCTestCase {
  private func ad(
    _ start: Double, _ end: Double, kind: AdKind = .ad, _ confidence: AdConfidence = .sure
  ) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: kind, advertiser: "A", confidence: confidence, firstWords: "")
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

  func testTheButtonCarriesOverHolesOfFifteenSecondsOrLess() {
    let first = ad(100, 130)
    let second = ad(145, 170)
    let third = ad(180, 200)
    XCTAssertEqual(
      decide(110, file([first, second, third])),
      .skip(AdSkip(ad: first, target: 200, chained: [second, third])))
    XCTAssertEqual(
      decide(110, file([first, ad(145.5, 170)])), .skip(AdSkip(ad: first, target: 130)))
    // A hole with an undone stretch in it stops the carry.
    let stretch = [UndoneAd(start: 135, end: 140)]
    XCTAssertEqual(
      decide(110, file([first, second], undone: stretch)), .skip(AdSkip(ad: first, target: 130)))
  }

  func testTheButtonDoesNotCarryIntoAnUndoneAdButMayStartInOne() {
    let first = ad(100, 130)
    let second = ad(140, 170)
    let undoneSecond = file([first, second], undone: [UndoneAd(start: 140, end: 170)])
    XCTAssertEqual(decide(110, undoneSecond), .skip(AdSkip(ad: first, target: 130)))
    // The ad the playhead is in may itself be an undone one, as before.
    let undoneFirst = file([first, second], undone: [UndoneAd(start: 100, end: 130)])
    XCTAssertEqual(
      decide(110, undoneFirst), .skip(AdSkip(ad: first, target: 170, chained: [second])))
  }

  func testTheButtonCarriesOnlyIntoAdsTheSwitchesSkip() {
    let first = ad(100, 130)
    let plug = ad(140, 170, kind: .ownPlug)
    let keepsPlugs = AdSkipSettings(skipOwnPlugs: false)
    XCTAssertEqual(
      decide(110, file([first, plug]), settings: keepsPlugs), .skip(AdSkip(ad: first, target: 130)))
    XCTAssertEqual(
      decide(110, file([first, plug])), .skip(AdSkip(ad: first, target: 170, chained: [plug])))
    XCTAssertEqual(
      decide(110, file([first, ad(140, 170, .guess)])), .skip(AdSkip(ad: first, target: 130)))
    // A plug the listener keeps, in the hole before the next ad, stops the carry.
    XCTAssertEqual(
      decide(
        110, file([first, ad(132, 140, kind: .ownPlug), ad(141, 170)]), settings: keepsPlugs),
      .skip(AdSkip(ad: first, target: 130)))
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
