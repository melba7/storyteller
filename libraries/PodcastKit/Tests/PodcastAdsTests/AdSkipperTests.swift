import XCTest

@testable import PodcastAds

final class AdSkipperTests: XCTestCase {
  private func ad(
    _ start: Double, _ end: Double, kind: AdKind = .ad, _ confidence: AdConfidence = .sure
  ) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: kind, advertiser: "Acme", confidence: confidence, firstWords: "x")
  }

  private func file(_ ads: [FoundAd], undone: [UndoneAd] = []) -> AdsFile {
    AdsFile(
      sha256: "aa", detector: "fake", detectorVersion: "1", osVersion: "26.0", duration: 1000,
      ads: ads, undone: undone)
  }

  private func skipper(
    _ ads: [FoundAd], settings: AdSkipSettings = AdSkipSettings(), undone: [UndoneAd] = []
  ) -> AdSkipper {
    AdSkipper(file: file(ads, undone: undone), settings: settings)
  }

  func testBothSwitchesAreOnByDefault() {
    XCTAssertEqual(AdSkipSettings(), AdSkipSettings(skipAds: true, skipOwnPlugs: true))
  }

  func testAShowsOwnSwitchesWinOverTheListeners() {
    let listener = AdSkipSettings(skipAds: true, skipOwnPlugs: false)
    XCTAssertEqual(
      listener.overridden(skipAds: nil, skipOwnPlugs: nil), listener)
    XCTAssertEqual(
      listener.overridden(skipAds: false, skipOwnPlugs: nil),
      AdSkipSettings(skipAds: false, skipOwnPlugs: false))
    XCTAssertEqual(
      listener.overridden(skipAds: nil, skipOwnPlugs: true),
      AdSkipSettings(skipAds: true, skipOwnPlugs: true))
  }


  // MARK: Reaching an ad

  func testReachingTheStartOfASureAdSkipsToItsEnd() {
    var skipper = skipper([ad(100, 160)])
    let skip = skipper.reached(position: 100.2, rate: 1, duration: 1000, now: 0)
    XCTAssertEqual(skip, AdSkip(ad: ad(100, 160), target: 160))
  }

  func testMarkersSitAtEachAdsStartInOrder() {
    XCTAssertEqual(skipper([ad(300, 360), ad(100, 160)]).boundaryTimes, [100, 300])
  }

  func testAnAdAtTheVeryStartGetsAMarkerJustAfterZero() {
    var skipper = skipper([ad(0, 40)])
    XCTAssertEqual(skipper.boundaryTimes, [0.05])
    XCTAssertNotNil(skipper.reached(position: 0.1, rate: 1, duration: 1000, now: 0))
  }

  func testTheRightAdIsPickedWhenThereAreSeveral() {
    var skipper = skipper([ad(100, 160), ad(300, 360)])
    let skip = skipper.reached(position: 300.3, rate: 1, duration: 1000, now: 0)
    XCTAssertEqual(skip?.ad.start, 300)
    XCTAssertEqual(skip?.target, 360)
  }

  func testNothingHappensAwayFromAnAdsStart() {
    var skipper = skipper([ad(100, 160)])
    XCTAssertNil(skipper.reached(position: 50, rate: 1, duration: 1000, now: 0))
    XCTAssertNil(skipper.reached(position: 400, rate: 1, duration: 1000, now: 0))
  }

  // MARK: Seeking

  func testSeekingIntoAnAdDoesNotSkipIt() {
    var skipper = skipper([ad(100, 160)])
    skipper.seeked(to: 130)
    // Playback was far into the ad when the marker was reported.
    XCTAssertNil(skipper.reached(position: 130.1, rate: 1, duration: 1000, now: 0))
  }

  func testSeekingToTheStartOfAnAdPlaysIt() {
    // The "play from here" button in the ads list seeks to exactly the start.
    var skipper = skipper([ad(100, 160)])
    skipper.seeked(to: 100)
    XCTAssertNil(skipper.reached(position: 100.0, rate: 1, duration: 1000, now: 0))
    XCTAssertNil(skipper.reached(position: 100.4, rate: 1, duration: 1000, now: 0))
  }

  func testSeekingJustBeforeAnAdStillSkipsIt() {
    var skipper = skipper([ad(100, 160)])
    skipper.seeked(to: 95)
    XCTAssertNotNil(skipper.reached(position: 100.1, rate: 1, duration: 1000, now: 0))
  }

  func testSeekingBackBeforeAnAdAfterPlayingIntoItSkipsItAgain() {
    var skipper = skipper([ad(100, 160)])
    skipper.seeked(to: 130)
    skipper.seeked(to: 20)
    XCTAssertNotNil(skipper.reached(position: 100.1, rate: 1, duration: 1000, now: 0))
  }

  func testSeekingPastAnAdLeavesItAlone() {
    var skipper = skipper([ad(100, 160)])
    skipper.seeked(to: 500)
    XCTAssertNil(skipper.reached(position: 500, rate: 1, duration: 1000, now: 0))
  }

  // MARK: Speed

  func testTheDelayThatCountsAsReachingGrowsWithTheSpeed() {
    XCTAssertEqual(AdSkipper.reachWindow(rate: 1), 2)
    XCTAssertEqual(AdSkipper.reachWindow(rate: 3), 4)
    XCTAssertEqual(AdSkipper.reachWindow(rate: 0.5), 2)
    XCTAssertEqual(AdSkipper.reachWindow(rate: 0), 2)
    XCTAssertEqual(AdSkipper.reachWindow(rate: .nan), 2)
  }

  func testAMarkerReportedLateAtHighSpeedStillSkips() {
    var fast = skipper([ad(100, 160)])
    XCTAssertNotNil(fast.reached(position: 103.5, rate: 3, duration: 1000, now: 0))
    var slow = skipper([ad(100, 160)])
    XCTAssertNil(slow.reached(position: 103.5, rate: 1, duration: 1000, now: 0))
  }

  func testTheTargetDoesNotDependOnTheSpeed() {
    var skipper = skipper([ad(100, 160)])
    XCTAssertEqual(skipper.reached(position: 100.1, rate: 2.5, duration: 1000, now: 0)?.target, 160)
  }

  // MARK: What is skipped

  func testSureAndUnsureAdsAreSkippedButNotGuesses() {
    let skipper = skipper([ad(100, 160, .unsure), ad(200, 260, .guess), ad(300, 360, .sure)])
    XCTAssertEqual(skipper.ads.map(\.start), [100, 300])
  }

  func testAnUnsureAdIsSkippedWhenReached() {
    var skipper = skipper([ad(100, 160, .unsure)])
    XCTAssertEqual(skipper.boundaryTimes, [100])
    XCTAssertEqual(skipper.reached(position: 100.1, rate: 1, duration: 1000, now: 0)?.target, 160)
  }

  func testAnUndoneUnsureAdIsNotSkippedAgain() {
    let undone = [UndoneAd(start: 100, end: 160)]
    var skipper = skipper([ad(100, 160, .unsure)], undone: undone)
    XCTAssertTrue(skipper.boundaryTimes.isEmpty)
    XCTAssertNil(skipper.reached(position: 100.1, rate: 1, duration: 1000, now: 0))
  }

  func testAPlugIsSkippedOnlyWithItsSwitchOn() {
    let plug = ad(100, 160, kind: .ownPlug)
    var on = skipper([plug], settings: AdSkipSettings(skipAds: true, skipOwnPlugs: true))
    XCTAssertNotNil(on.reached(position: 100.1, rate: 1, duration: 1000, now: 0))
    var off = skipper([plug], settings: AdSkipSettings(skipAds: true, skipOwnPlugs: false))
    XCTAssertNil(off.reached(position: 100.1, rate: 1, duration: 1000, now: 0))
    XCTAssertTrue(off.boundaryTimes.isEmpty)
  }

  func testTheSwitchesAreIndependent() {
    let ads = [ad(100, 160), ad(300, 360, kind: .ownPlug)]
    XCTAssertEqual(
      skipper(ads, settings: AdSkipSettings(skipAds: false, skipOwnPlugs: true)).ads.map(\.start), [300])
    XCTAssertEqual(
      skipper(ads, settings: AdSkipSettings(skipAds: true, skipOwnPlugs: false)).ads.map(\.start), [100])
    XCTAssertTrue(
      skipper(ads, settings: AdSkipSettings(skipAds: false, skipOwnPlugs: false)).ads.isEmpty)
  }

  func testChangingASwitchWhilePlayingTakesEffectAndKeepsWhatWasSeeked() {
    var skipper = skipper([ad(100, 160), ad(300, 360)], settings: AdSkipSettings(skipAds: false))
    XCTAssertTrue(skipper.ads.isEmpty)
    skipper.seeked(to: 310)
    skipper.apply(settings: AdSkipSettings(skipAds: true))
    XCTAssertEqual(skipper.ads.count, 2)
    XCTAssertNil(skipper.reached(position: 310.2, rate: 1, duration: 1000, now: 0))
  }

  func testAdsFoundWhilePlayingAreSkippedWhenReachedButNotWhenTheListenerSeekedIntoThem() {
    var skipper = AdSkipper(file: nil, settings: AdSkipSettings())
    skipper.seeked(to: 130)
    skipper.replace(file: file([ad(100, 160), ad(300, 360)]))
    XCTAssertEqual(skipper.ads.map(\.start), [100, 300])
    XCTAssertNil(skipper.reached(position: 130.1, rate: 1, duration: 1000, now: 0))
    XCTAssertNotNil(skipper.reached(position: 300.2, rate: 1, duration: 1000, now: 0))
  }

  func testAnAdTheListenerUndidBeforeIsNotSkipped() {
    let skipper = skipper([ad(100, 160)], undone: [UndoneAd(start: 100, end: 160)])
    XCTAssertTrue(skipper.ads.isEmpty)
  }

  func testNoFileMeansNothingToSkip() {
    let skipper = AdSkipper(file: nil, settings: AdSkipSettings())
    XCTAssertTrue(skipper.boundaryTimes.isEmpty)
  }

  // MARK: The end of the episode

  func testAnAdAtTheVeryEndLandsJustBeforeTheEnd() {
    var skipper = skipper([ad(940, 1000)])
    let skip = skipper.reached(position: 940.1, rate: 1, duration: 1000, now: 0)
    XCTAssertEqual(skip?.target ?? 0, 999.95, accuracy: 0.001)
  }

  func testAnAdThatEndsALittleBeforeTheEndLandsOnItsEnd() {
    var skipper = skipper([ad(900, 990)])
    XCTAssertEqual(skipper.reached(position: 900.1, rate: 1, duration: 1000, now: 0)?.target, 990)
  }

  func testAnAdPastTheEndOfTheAudioStillLandsInsideIt() {
    // The transcript can be a little longer than the audio the player measures.
    var skipper = skipper([ad(940, 1003)])
    let target = skipper.reached(position: 940.1, rate: 1, duration: 1000, now: 0)?.target ?? 0
    XCTAssertLessThan(target, 1000)
    XCTAssertGreaterThan(target, 940)
  }

  func testWithoutAKnownDurationTheTargetIsTheAdsEnd() {
    var skipper = skipper([ad(940, 1000)])
    XCTAssertEqual(skipper.reached(position: 940.1, rate: 1, duration: nil, now: 0)?.target, 1000)
  }

  // MARK: Undo

  func testUndoGivesBackTheAdJustSkippedAndItIsNotSkippedAgain() throws {
    var skipper = skipper([ad(100, 160)])
    XCTAssertNotNil(skipper.reached(position: 100.1, rate: 1, duration: 1000, now: 10))
    XCTAssertEqual(skipper.undo(now: 14), ad(100, 160))
    // The player seeks back to the start, which is a seek into the ad.
    skipper.seeked(to: 100)
    XCTAssertNil(skipper.reached(position: 100.2, rate: 1, duration: 1000, now: 15))
    // And it stays unskipped later in the same episode, even when played from before it.
    skipper.seeked(to: 50)
    XCTAssertNil(skipper.reached(position: 100.2, rate: 1, duration: 1000, now: 60))
    XCTAssertTrue(skipper.ads.isEmpty)
  }

  func testUndoCanGiveBackTheWholeSkipSoAChainedAdIsSavedToo() {
    var skipper = skipper([ad(100, 160), ad(160.2, 190, kind: .ownPlug)])
    XCTAssertNotNil(skipper.reached(position: 100.1, rate: 1, duration: 1000, now: 10))
    let skip = skipper.undoSkip(now: 11)
    XCTAssertEqual(skip?.ad, ad(100, 160))
    XCTAssertEqual(skip?.chained.map(\.start), [160.2])
    XCTAssertNil(skipper.undoSkip(now: 12))
  }

  func testUndoComesTooLateAfterTheNoteIsGone() {
    var skipper = skipper([ad(100, 160)])
    _ = skipper.reached(position: 100.1, rate: 1, duration: 1000, now: 10)
    XCTAssertNil(skipper.undo(now: 10 + AdSkipper.undoSeconds + AdSkipper.undoGrace + 1))
  }

  func testUndoWithNothingSkippedDoesNothing() {
    var skipper = skipper([ad(100, 160)])
    XCTAssertNil(skipper.undo(now: 5))
  }

  func testUndoWorksOnce() {
    var skipper = skipper([ad(100, 160)])
    _ = skipper.reached(position: 100.1, rate: 1, duration: 1000, now: 10)
    XCTAssertNotNil(skipper.undo(now: 11))
    XCTAssertNil(skipper.undo(now: 12))
  }

  func testUndoingOneAdLeavesTheOthers() {
    var skipper = skipper([ad(100, 160), ad(300, 360)])
    _ = skipper.reached(position: 100.1, rate: 1, duration: 1000, now: 10)
    _ = skipper.undo(now: 11)
    XCTAssertEqual(skipper.ads.map(\.start), [300])
  }

  // MARK: An ad found while it plays

  /// A fresh skipper with no ads, told of `file` while the playhead is at `playhead`.
  private func found(
    _ ads: [FoundAd], at playhead: Double?, settings: AdSkipSettings = AdSkipSettings()
  ) -> AdSkip? {
    var skipper = AdSkipper(file: nil, settings: settings)
    return skipper.replace(file: file(ads), playhead: playhead, duration: 1000, now: 5)
  }

  func testAnAdFoundAroundThePlayheadWithTwentySecondsLeftIsLeftAtOnce() {
    var skipper = AdSkipper(file: nil, settings: AdSkipSettings())
    let skip = skipper.replace(
      file: file([ad(100, 160)]), playhead: 140, duration: 1000, now: 5)
    XCTAssertEqual(skip, AdSkip(ad: ad(100, 160), target: 160))
    XCTAssertEqual(skipper.undo(now: 6), ad(100, 160), "the skip can be undone")
  }

  func testAnAdWithTwoSecondsLeftIsNotLeft() {
    XCTAssertNil(found([ad(100, 160)], at: 158))
    XCTAssertNotNil(found([ad(100, 160)], at: 157), "three seconds left is enough")
  }

  func testAnUndoneAdIsNotLeft() {
    var skipper = AdSkipper(file: nil, settings: AdSkipSettings())
    let undone = [UndoneAd(start: 100, end: 160)]
    XCTAssertNil(
      skipper.replace(file: file([ad(100, 160)], undone: undone), playhead: 120, duration: 1000, now: 5))
    // Undone by the Undo button while this episode plays.
    var undoing = AdSkipper(file: file([ad(100, 160)]), settings: AdSkipSettings())
    _ = undoing.reached(position: 100.1, rate: 1, duration: 1000, now: 10)
    _ = undoing.undo(now: 11)
    XCTAssertNil(
      undoing.replace(file: file([ad(100, 160)]), playhead: 120, duration: 1000, now: 12))
  }

  func testAfterAManualSeekIntoAnAdItIsNotLeftWhenTheAdIsFoundOrFoundAgain() {
    var skipper = AdSkipper(file: nil, settings: AdSkipSettings())
    skipper.seeked(to: 110)
    XCTAssertNil(
      skipper.replace(file: file([ad(100, 160)]), playhead: 115, duration: 1000, now: 5))
    XCTAssertNil(
      skipper.replace(file: file([ad(100, 160)]), playhead: 120, duration: 1000, now: 6))
  }

  func testAnAdTheSeekDidNotLandInIsLeftWhenPlaybackRanIntoIt() {
    var skipper = AdSkipper(file: nil, settings: AdSkipSettings())
    skipper.seeked(to: 50)
    XCTAssertNotNil(
      skipper.replace(file: file([ad(100, 160)]), playhead: 120, duration: 1000, now: 5))
  }

  func testAnAdIsLeftOnlyOnceAndNotWhenThePlayheadIsOutsideIt() {
    var skipper = AdSkipper(file: nil, settings: AdSkipSettings())
    XCTAssertNotNil(
      skipper.replace(file: file([ad(100, 160)]), playhead: 120, duration: 1000, now: 5))
    XCTAssertNil(
      skipper.replace(file: file([ad(100, 160)]), playhead: 120.2, duration: 1000, now: 5.1),
      "the same ad found again before the jump has landed")
    XCTAssertNil(found([ad(100, 160)], at: 60))
    XCTAssertNil(found([ad(100, 160)], at: 160), "the end of an ad is outside it")
    XCTAssertNil(found([ad(100, 160)], at: nil), "not playing")
  }

  func testAnAdCutShortAtThePassEdgeIsLeftAgainWhenItIsFoundLonger() {
    var skipper = AdSkipper(file: nil, settings: AdSkipSettings())
    XCTAssertEqual(
      skipper.replace(file: file([ad(100, 130)]), playhead: 110, duration: 1000, now: 5)?.target, 130)
    XCTAssertEqual(
      skipper.replace(file: file([ad(100, 160)]), playhead: 131, duration: 1000, now: 6)?.target,
      160, "the longer range holds the playhead where the jump landed")
    XCTAssertNil(
      skipper.replace(file: file([ad(100, 160)]), playhead: 131.1, duration: 1000, now: 6.1))
  }

  func testAnAdWithASwitchOffIsNotLeftAndAChainedPlugIsLeftWithIt() {
    XCTAssertNil(
      found([ad(100, 160)], at: 120, settings: AdSkipSettings(skipAds: false, skipOwnPlugs: true)))
    let skip = found([ad(100, 160), ad(160.2, 190, kind: .ownPlug)], at: 158)
    XCTAssertEqual(skip?.target, 190, "two seconds of the ad and a plug after it: worth leaving")
  }
}
