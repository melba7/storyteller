import XCTest

@testable import PodcastAds

/// The skip tap: the six cases, in order.
final class AdSkipTapTests: XCTestCase {
  private func ad(
    _ start: Double, _ end: Double, kind: AdKind = .ad, _ confidence: AdConfidence = .sure
  ) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: kind, advertiser: "A", confidence: confidence, firstWords: "")
  }

  private func file(
    _ ads: [FoundAd], asks: [FoundAd]? = nil, maybes: [FoundAd]? = nil,
    undone: [UndoneAd] = [], denied: [UndoneAd]? = nil, trims: [AdTrim]? = nil
  ) -> AdsFile {
    AdsFile(
      sha256: "x", detector: "d", detectorVersion: "1", osVersion: "26", duration: 3000, ads: ads,
      undone: undone, trims: trims, asks: asks, denied: denied, maybes: maybes)
  }

  private func decide(
    _ position: Double, plain: Double? = nil, _ file: AdsFile?,
    settings: AdSkipSettings = AdSkipSettings(), last: AdSkip? = nil, age: Double = 100
  ) -> AdSkipTap.Action {
    AdSkipTap.decide(
      position: position, plain: plain ?? position + 30, duration: 3000, file: file,
      settings: settings, lastSkip: last, lastSkipAge: age)
  }

  // MARK: Case 2, a known ad

  func testNoFileIsThePlainMove() {
    XCTAssertEqual(decide(100, nil), .plain(to: 130))
  }

  func testInsideAKnownAdItIsLeftWithTheAdsThatFollow() {
    let first = ad(100, 160)
    let plug = ad(160.4, 175, kind: .ownPlug)
    XCTAssertEqual(
      decide(110, file([first, plug])), .skip(AdSkip(ad: first, target: 175, chained: [plug])))
  }

  func testTheLeadBeforeAnAdsStartCounts() {
    let one = ad(100, 130)
    XCTAssertEqual(decide(98.5, file([one])), .skip(AdSkip(ad: one, target: 130)))
    XCTAssertEqual(decide(97.5, plain: 99, file([one])), .plain(to: 99))
  }

  func testAKnownAdOfAnyKindAndConfidenceIsLeft() {
    let credits = ad(100, 130, kind: .credits, .guess)
    XCTAssertEqual(decide(110, file([credits])), .skip(AdSkip(ad: credits, target: 130)))
    let off = AdSkipSettings(skipAds: false)
    let one = ad(100, 130)
    XCTAssertEqual(decide(110, file([one]), settings: off), .skip(AdSkip(ad: one, target: 130)))
  }

  func testATrimCutsTheAdAndAnUndoneAdIsNotLeft() {
    let one = ad(100, 160)
    let trimmed = file([one], trims: [AdTrim(adStart: 100, end: 130)])
    XCTAssertEqual(decide(110, trimmed), .skip(AdSkip(ad: ad(100, 130), target: 130)))
    // After the trim the ad is over: the playhead is past it and the move is plain.
    XCTAssertEqual(decide(140, trimmed), .plain(to: 170))
    let undone = file([one], undone: [UndoneAd(start: 100, end: 160)])
    XCTAssertEqual(decide(110, undone), .plain(to: 140))
  }

  func testAnUndoneAdDoesNotJoinTheChain() {
    let first = ad(100, 130)
    let next = ad(130.2, 150)
    let undone = file([first, next], undone: [UndoneAd(start: 130.2, end: 150)])
    XCTAssertEqual(decide(110, undone), .skip(AdSkip(ad: first, target: 130)))
  }

  // MARK: Case 1, just skipped

  func testJustAfterAnAutomaticSkipTheTapIsPlain() {
    let skipped = AdSkip(ad: ad(100, 130), target: 130)
    let two = file([ad(100, 130), ad(131, 160)], asks: [ad(130, 200, .guess)])
    // The playhead at the target is not in the next ad's lead or the question's start.
    XCTAssertEqual(decide(130.2, plain: 160.2, two, last: skipped, age: 1), .plain(to: 160.2))
    // A move that would land in a skipped ad still goes to its end.
    XCTAssertEqual(decide(130.2, plain: 140, two, last: skipped, age: 1), .plain(to: 160))
    // An old skip does not count: the ad ahead (in its lead) is a case 2 skip.
    XCTAssertEqual(
      decide(130.2, plain: 160.2, two, last: skipped, age: 4),
      .skip(AdSkip(ad: ad(131, 160), target: 160)))
  }

  // MARK: Cases 3 and 4, a question and a maybe

  func testAnOpenQuestionIsAnsweredYes() {
    let question = ad(200, 230, .guess)
    XCTAssertEqual(decide(210, file([], asks: [question])), .answer(start: 200))
    XCTAssertEqual(decide(199, file([], asks: [question])), .plain(to: 229))
    // An answered question is not asked again.
    var answered = question
    answered.confidence = .sure
    XCTAssertEqual(decide(210, file([], asks: [answered])), .plain(to: 240))
  }

  func testAMaybeIsConfirmedFromItsLead() {
    let maybe = ad(300, 340, .guess)
    XCTAssertEqual(decide(310, file([], maybes: [maybe])), .confirm(start: 300))
    XCTAssertEqual(decide(298.5, file([], maybes: [maybe])), .confirm(start: 300))
    XCTAssertEqual(decide(297, file([], maybes: [maybe])), .plain(to: 327))
    XCTAssertEqual(decide(340, file([], maybes: [maybe])), .plain(to: 370))
  }

  func testTheCasesComeInOrder() {
    let known = ad(100, 130)
    let question = ad(110, 140, .guess)
    let maybe = ad(110, 150, .guess)
    // A known ad beats a question and a maybe over the same place.
    XCTAssertEqual(
      decide(105, file([known], asks: [question], maybes: [maybe])),
      .skip(AdSkip(ad: known, target: 130)))
    // A question and a maybe cannot both be open over the same stretch: the question wins.
    XCTAssertEqual(
      decide(120, file([ad(300, 310)], asks: [question], maybes: [maybe])), .answer(start: 110))
  }

  // MARK: Case 5, a hole between two skipped ads

  private func holeFile(_ gap: Double, extra: (undone: [UndoneAd], denied: [UndoneAd]?) = ([], nil))
    -> AdsFile
  {
    file(
      [ad(100, 130), ad(130 + gap, 200 + gap)], undone: extra.undone, denied: extra.denied)
  }

  func testAHoleOfSixtySecondsIsBridgedAndOneOfSixtyOneIsNot() {
    XCTAssertEqual(decide(150, holeFile(60)), .bridge(to: 260, holeEnd: 190))
    XCTAssertEqual(decide(150, holeFile(61)), .plain(to: 180))
  }

  func testAHoleNeedsASkippedAdOnBothSides() {
    XCTAssertEqual(decide(50, file([ad(100, 130)])), .plain(to: 80))
    XCTAssertEqual(decide(150, file([ad(100, 130)])), .plain(to: 180))
    XCTAssertEqual(decide(150, file([ad(200, 230)])), .plain(to: 180))
  }

  func testAHoleBetweenAdsThatAreChainedIsNoHole() {
    let chain = file([ad(100, 130), ad(130.3, 160), ad(200, 230)])
    XCTAssertEqual(decide(180, chain), .bridge(to: 230, holeEnd: 200))
  }

  func testAnUndoneOrDeniedStretchInTheHoleStopsTheBridge() {
    let undone = [UndoneAd(start: 140, end: 150)]
    XCTAssertEqual(decide(155, holeFile(60, extra: (undone, nil))), .plain(to: 185))
    let denied = [UndoneAd(start: 140, end: 150)]
    XCTAssertEqual(decide(155, holeFile(60, extra: ([], denied))), .plain(to: 185))
    // A stretch that is elsewhere does not.
    XCTAssertEqual(
      decide(155, holeFile(60, extra: ([], [UndoneAd(start: 5, end: 15)]))),
      .bridge(to: 260, holeEnd: 190))
  }

  func testAnAdWhoseSwitchIsOffIsNotBridgedTo() {
    let withPlug = file([ad(100, 130), ad(190, 220, kind: .ownPlug)])
    let off = AdSkipSettings(skipOwnPlugs: false)
    XCTAssertEqual(decide(150, withPlug, settings: off), .plain(to: 180))
    XCTAssertEqual(decide(150, withPlug), .bridge(to: 220, holeEnd: 190))
  }

  func testAnUnsureAdCountsAndAGuessDoesNot() {
    XCTAssertEqual(
      decide(150, file([ad(100, 130), ad(190, 220, .unsure)])), .bridge(to: 220, holeEnd: 190))
    XCTAssertEqual(decide(150, file([ad(100, 130), ad(190, 220, .guess)])), .plain(to: 180))
  }

  func testATrimMakesTheHoleLonger() {
    let trimmed = file(
      [ad(100, 130), ad(180, 210)], trims: [AdTrim(adStart: 100, end: 115)])
    // The first ad now ends at 115: the hole to 180 is 65 seconds.
    XCTAssertEqual(decide(150, plain: 160, trimmed), .plain(to: 160))
  }

  // MARK: Case 6, the plain move

  func testAPlainMoveThatLandsInASkippedAdGoesToItsEnd() {
    let ahead = file([ad(170, 200)])
    XCTAssertEqual(decide(150, ahead, last: nil), .plain(to: 200))
  }

  func testAPlainMoveThatLandsInAnAdWhoseSwitchIsOffStays() {
    let ahead = file([ad(170, 200, kind: .ownPlug)])
    XCTAssertEqual(decide(150, ahead, settings: AdSkipSettings(skipOwnPlugs: false)), .plain(to: 180))
  }

  func testAPlainMoveThatLandsInAnUndoneAdStays() {
    let ahead = file([ad(170, 200)], undone: [UndoneAd(start: 170, end: 200)])
    XCTAssertEqual(decide(150, ahead), .plain(to: 180))
  }

  func testBadTimesNeverTrapOrGoBack() {
    let one = file([ad(100, 130)])
    XCTAssertEqual(decide(.nan, plain: .nan, one), .plain(to: 0))
    XCTAssertEqual(decide(.infinity, plain: 5, one), .plain(to: 5))
    XCTAssertEqual(decide(150, plain: 100, one), .plain(to: 150))
    XCTAssertEqual(decide(150, plain: .infinity, one), .plain(to: 150))
    let strange = file([ad(.nan, 10), ad(5, .infinity)])
    if case .plain(let to) = decide(7, strange) { XCTAssertGreaterThanOrEqual(to, 7) }
  }
}
