import XCTest

@testable import PodcastAds

/// A skip that went too far: the listener goes back into the ad that was just skipped.
final class AdSkipperTooFarTests: XCTestCase {
  private func ad(_ start: Double, _ end: Double) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "Acme", confidence: .sure, firstWords: "x")
  }

  private func file(_ ads: [FoundAd], trims: [AdTrim]? = nil) -> AdsFile {
    AdsFile(
      sha256: "aa", detector: "fake", detectorVersion: "1", osVersion: "26.0", duration: 1000,
      ads: ads, trims: trims)
  }

  /// A skipper that has just skipped the ads at `now` 100 (the playhead crossed the first one's start).
  private func skipped(_ ads: [FoundAd]) -> AdSkipper {
    var skipper = AdSkipper(file: file(ads), settings: AdSkipSettings())
    _ = skipper.reached(position: ads[0].start + 0.1, rate: 1, duration: 1000, now: 100)
    return skipper
  }

  func testGoingBackIntoTheSkippedAdTrimsItToThere() {
    var skipper = skipped([ad(60, 120)])
    let trim = skipper.backSeek(to: 110, now: 105)
    XCTAssertEqual(trim, AdTrim(adStart: 60, end: 110))
    XCTAssertEqual(skipper.ads, [ad(60, 110)])
  }

  func testNotMoreThanTwentySecondsAfterTheSkip() {
    var late = skipped([ad(60, 120)])
    XCTAssertNil(late.backSeek(to: 110, now: 130))
    XCTAssertEqual(late.ads, [ad(60, 120)])
    var justInTime = skipped([ad(60, 120)])
    XCTAssertNotNil(justInTime.backSeek(to: 110, now: 120))
    var justLate = skipped([ad(60, 120)])
    XCTAssertNil(justLate.backSeek(to: 110, now: 120.5))
  }

  func testNotBeforeTheAd() {
    var skipper = skipped([ad(60, 120)])
    XCTAssertNil(skipper.backSeek(to: 30, now: 105))
  }

  func testNotAtTheAdsStartWhichIsWhatUndoDoes() {
    var skipper = skipped([ad(60, 120)])
    XCTAssertNil(skipper.backSeek(to: 60, now: 105))
  }

  func testNotAtOrAfterTheLanding() {
    var skipper = skipped([ad(60, 120)])
    XCTAssertNil(skipper.backSeek(to: 120, now: 105))
    XCTAssertNil(skipper.backSeek(to: 125, now: 105))
  }

  func testNotMoreThanSixtySecondsBeforeTheLanding() {
    var far = skipped([ad(60, 200)])
    XCTAssertNil(far.backSeek(to: 139, now: 105))
    var near = skipped([ad(60, 200)])
    XCTAssertEqual(near.backSeek(to: 140, now: 105), AdTrim(adStart: 60, end: 140))
  }

  func testNothingToTrimWhenNothingWasSkipped() {
    var skipper = AdSkipper(file: file([ad(60, 120)]), settings: AdSkipSettings())
    XCTAssertNil(skipper.backSeek(to: 110, now: 105))
  }

  func testUndoThenAGoBackIsNotTooFar() {
    var skipper = skipped([ad(60, 120)])
    XCTAssertNotNil(skipper.undoSkip(now: 103))
    XCTAssertNil(skipper.backSeek(to: 110, now: 105))
  }

  func testASecondGoBackTrimsAgainButAScrubForwardDoesNot() {
    var skipper = skipped([ad(60, 120)])
    XCTAssertEqual(skipper.backSeek(to: 110, now: 105)?.end, 110)
    XCTAssertEqual(skipper.backSeek(to: 100, now: 107)?.end, 100)
    XCTAssertEqual(skipper.ads, [ad(60, 100)])
    // 115 is past where the ad ends now: nothing is shortened.
    XCTAssertNil(skipper.backSeek(to: 115, now: 108))
    XCTAssertEqual(skipper.ads, [ad(60, 100)])
  }

  func testTheGoBackIsNotASeekIntoTheAd() {
    var skipper = skipped([ad(60, 120)])
    skipper.backSeek(to: 110, now: 105)
    skipper.seeked(to: 110)
    // The trimmed ad ends at 110, so the playhead is not inside it, and the next marker skips it.
    XCTAssertNotNil(skipper.reached(position: 60.1, rate: 1, duration: 1000, now: 200))
  }

  func testTheTrimmedAdIsSkippedToTheTrimNextTime() {
    var skipper = AdSkipper(
      file: file([ad(60, 120)], trims: [AdTrim(adStart: 60, end: 110)]), settings: AdSkipSettings())
    XCTAssertEqual(skipper.ads, [ad(60, 110)])
    XCTAssertEqual(skipper.reached(position: 60.1, rate: 1, duration: 1000, now: 0)?.target, 110)
  }

  func testATrimOnlyShortensAndOnlyItsOwnAd() {
    let skipper = AdSkipper(
      file: file(
        [ad(60, 120), ad(300, 360)],
        trims: [AdTrim(adStart: 60, end: 150), AdTrim(adStart: 700, end: 710)]),
      settings: AdSkipSettings())
    XCTAssertEqual(skipper.ads, [ad(60, 120), ad(300, 360)])
  }

  func testTheTrimStillFitsTheSameAdFoundAgainALittleDifferently() {
    // Found again starting 0.3 s earlier and running longer: it is the same ad.
    let skipper = AdSkipper(
      file: file([ad(59.7, 130)], trims: [AdTrim(adStart: 60, end: 110)]),
      settings: AdSkipSettings())
    XCTAssertEqual(skipper.ads, [ad(59.7, 110)])
  }

  func testATrimStaysWhenTheFileIsReadAgain() {
    var skipper = skipped([ad(60, 120)])
    skipper.backSeek(to: 110, now: 105)
    // Ads were found meanwhile and the file was saved without knowing the trim.
    skipper.replace(file: file([ad(60, 120), ad(300, 360)]))
    XCTAssertEqual(skipper.ads, [ad(60, 110), ad(300, 360)])
  }

  func testInAChainTheAdThatHoldsTheSpotIsTrimmed() {
    var skipper = skipped([ad(60, 100), ad(100.2, 120)])
    let trim = skipper.backSeek(to: 110, now: 105)
    XCTAssertEqual(trim, AdTrim(adStart: 100.2, end: 110))
    XCTAssertEqual(skipper.ads, [ad(60, 100), ad(100.2, 110)])
    // Between the two ads of the chain nothing is shortened.
    var between = skipped([ad(60, 100), ad(100.2, 120)])
    XCTAssertNil(between.backSeek(to: 100.1, now: 105))
  }
}
