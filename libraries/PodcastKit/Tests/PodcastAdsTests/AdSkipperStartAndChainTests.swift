import XCTest

@testable import PodcastAds

/// An episode that starts inside an ad, and an ad followed at once by another.
final class AdSkipperStartAndChainTests: XCTestCase {
  private func ad(_ start: Double, _ end: Double, kind: AdKind = .ad) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: kind, advertiser: "Acme", confidence: .sure, firstWords: "x")
  }

  private func skipper(_ ads: [FoundAd], settings: AdSkipSettings = AdSkipSettings()) -> AdSkipper {
    let file = AdsFile(
      sha256: "aa", detector: "fake", detectorVersion: "1", osVersion: "26.0", duration: 1000,
      ads: ads, undone: [])
    return AdSkipper(file: file, settings: settings)
  }

  // MARK: Starting an episode

  func testStartingInsideAnAdSkipsToItsEndAtOnce() {
    var skipper = skipper([ad(0, 90)])
    let skip = skipper.started(at: 30, duration: 1000, now: 0)
    XCTAssertEqual(skip?.target, 90)
  }

  func testAnAdAtExactlyZeroIsSkippedWhenTheEpisodeStartsAtZero() {
    var skipper = skipper([ad(0, 40)])
    XCTAssertEqual(skipper.started(at: 0, duration: 1000, now: 0)?.target, 40)
  }

  func testStartingBeforeAnAdLeavesItToBeSkippedWhenReached() {
    var skipper = skipper([ad(100, 160)])
    XCTAssertNil(skipper.started(at: 0, duration: 1000, now: 0))
    XCTAssertNotNil(skipper.reached(position: 100.1, rate: 1, duration: 1000, now: 1))
  }

  func testStartingAfterAnAdLeavesItAlone() {
    var skipper = skipper([ad(100, 160)])
    XCTAssertNil(skipper.started(at: 160, duration: 1000, now: 0))
  }

  func testStartingInsideAnAdWhoseSwitchIsOffPlaysIt() {
    var skipper = skipper([ad(0, 90, kind: .ownPlug)], settings: AdSkipSettings(skipOwnPlugs: false))
    XCTAssertNil(skipper.started(at: 30, duration: 1000, now: 0))
  }

  func testTheSkipAtStartCanBeUndone() {
    var skipper = skipper([ad(0, 90)])
    _ = skipper.started(at: 30, duration: 1000, now: 10)
    XCTAssertEqual(skipper.undo(now: 11)?.start, 0)
  }

  // MARK: Ads in a row

  func testAnAdFollowedAtOnceByAPlugIsSkippedTogether() {
    var skipper = skipper([ad(100, 160), ad(160, 200, kind: .ownPlug)])
    let skip = skipper.reached(position: 100.1, rate: 1, duration: 1000, now: 0)
    XCTAssertEqual(skip?.target, 200)
    XCTAssertEqual(skip?.ad.start, 100)
    XCTAssertEqual(skip?.end, 200)
  }

  func testAShortGapStillChains() {
    var skipper = skipper([ad(100, 160), ad(160.4, 200)])
    XCTAssertEqual(skipper.reached(position: 100.1, rate: 1, duration: 1000, now: 0)?.target, 200)
  }

  func testALongerGapDoesNotChain() {
    var skipper = skipper([ad(100, 160), ad(165, 200)])
    XCTAssertEqual(skipper.reached(position: 100.1, rate: 1, duration: 1000, now: 0)?.target, 160)
  }

  func testThreeInARowChain() {
    var skipper = skipper([ad(100, 160), ad(160, 200), ad(200, 230)])
    XCTAssertEqual(skipper.reached(position: 100.1, rate: 1, duration: 1000, now: 0)?.target, 230)
  }

  func testAPlugWhoseSwitchIsOffEndsTheChain() {
    var skipper = skipper(
      [ad(100, 160), ad(160, 200, kind: .ownPlug)], settings: AdSkipSettings(skipOwnPlugs: false))
    XCTAssertEqual(skipper.reached(position: 100.1, rate: 1, duration: 1000, now: 0)?.target, 160)
  }

  func testAChainToTheEndOfTheEpisodeLandsJustBeforeIt() {
    var skipper = skipper([ad(900, 950), ad(950, 1000)])
    let target = skipper.reached(position: 900.1, rate: 1, duration: 1000, now: 0)?.target ?? 0
    XCTAssertEqual(target, 999.95, accuracy: 0.001)
  }

  func testUndoingAChainBringsBackTheWholeStretch() {
    var skipper = skipper([ad(100, 160), ad(160, 200)])
    _ = skipper.reached(position: 100.1, rate: 1, duration: 1000, now: 0)
    XCTAssertEqual(skipper.undo(now: 1)?.start, 100)
    XCTAssertTrue(skipper.ads.isEmpty)
  }
}
