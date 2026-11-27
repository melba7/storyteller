import XCTest

@testable import PodcastAds

/// Which ads an Undo takes back when the skip holds stretches of the opening lines or the filled
/// holes next to the ads of other finders.
final class AdSkipUndoTests: XCTestCase {
  private func ad(_ start: Double, _ end: Double, by source: String? = nil) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "", confidence: source == nil ? .sure : .unsure,
      firstWords: "x", source: source)
  }

  private func skipper(_ ads: [FoundAd]) -> AdSkipper {
    let file = AdsFile(
      sha256: "aa", detector: "fake", detectorVersion: "1", osVersion: "26.0", duration: 1000,
      ads: ads, undone: [])
    return AdSkipper(file: file, settings: AdSkipSettings())
  }

  func testASkipWithNoCueStretchIsTakenBackWhole() {
    let skip = AdSkip(ad: ad(100, 160), target: 200, chained: [ad(160, 200, by: "repeat-words")])
    XCTAssertEqual(skip.takenBack.map(\.start), [100, 160])
  }

  func testOnlyThePullIsTakenBackWhenItStandsBeforeAnAd() {
    let pull = ad(100, 150, by: ShowTuning.openingLines)
    let skip = AdSkip(ad: pull, target: 200, chained: [ad(150, 200)])
    XCTAssertEqual(skip.takenBack, [pull])
  }

  func testOnlyTheHoleIsTakenBackBetweenTwoAds() {
    let hole = ad(160, 180, by: ShowTuning.filledHoles)
    let skip = AdSkip(ad: ad(100, 160), target: 240, chained: [hole, ad(180, 240)])
    XCTAssertEqual(skip.takenBack, [hole])
  }

  func testASkipOfCueStretchesAloneIsTakenBackWhole() {
    let pull = ad(100, 150, by: ShowTuning.openingLines)
    XCTAssertEqual(AdSkip(ad: pull, target: 150).takenBack, [pull])
  }

  func testAfterTheUndoOfAPullTheAdBehindItIsSkippedAgain() {
    var skipper = skipper([ad(100, 150, by: ShowTuning.openingLines), ad(150, 200)])
    let first = skipper.reached(position: 100.1, rate: 1, duration: 1000, now: 0)
    XCTAssertEqual(first?.target, 200, "the pull and the ad are one skip")
    XCTAssertEqual(skipper.undoSkip(now: 1)?.takenBack.map(\.start), [100])
    XCTAssertEqual(skipper.ads.map(\.start), [150], "the ad is still skipped, the pull is not")
    // The Undo puts the playhead at the start of the pull; the pull plays and the ad is skipped.
    skipper.seeked(to: 100)
    XCTAssertNil(skipper.reached(position: 100.1, rate: 1, duration: 1000, now: 2))
    XCTAssertEqual(skipper.reached(position: 150.1, rate: 1, duration: 1000, now: 52)?.target, 200)
  }
}
