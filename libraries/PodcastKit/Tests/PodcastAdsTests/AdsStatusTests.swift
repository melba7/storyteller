import XCTest

@testable import PodcastAds

final class AdsStatusTests: XCTestCase {
  private func file(ads: Int, version: String = "1") -> AdsFile {
    AdsFile(
      sha256: "aa", detector: "fake", detectorVersion: version, osVersion: "26.0", duration: 600,
      ads: (0..<ads).map {
        FoundAd(
          start: Double($0) * 100, end: Double($0) * 100 + 40, kind: .ad, advertiser: "A",
          confidence: .sure, firstWords: "x")
      })
  }

  private func status(
    file: AdsFile? = nil, partial: AdsFile? = nil, finding: Int? = nil,
    unavailable: AdUnavailable? = nil, failure: String? = nil
  ) -> AdsStatus {
    AdsRules.status(
      file: file, partial: partial, detectorVersion: "1", finding: finding, unavailable: unavailable,
      failure: failure)
  }

  func testAnEpisodeWithOnlyAPartialResultShowsItsAdsAndIsStillQueuedForTheFullPass() {
    let partial = status(partial: file(ads: 2))
    XCTAssertEqual(partial, .partialFound(count: 2))
    XCTAssertTrue(AdsRules.wantsRun(partial))
    // The final file wins, and a partial result with no ads or of another version says nothing.
    XCTAssertEqual(status(file: file(ads: 3), partial: file(ads: 2)), .found(count: 3))
    XCTAssertEqual(status(partial: file(ads: 0)), .waiting)
    XCTAssertEqual(status(partial: file(ads: 2, version: "0")), .waiting)
    XCTAssertEqual(status(partial: file(ads: 2), finding: 10), .finding(percent: 10))
    let failed = status(partial: file(ads: 2), failure: "Finding ads stopped")
    XCTAssertEqual(failed, .notPossible(reason: "Finding ads stopped"))
    XCTAssertFalse(AdsRules.wantsRun(failed))
  }

  func testAFreshEpisodeWaits() {
    XCTAssertEqual(status(), .waiting)
    XCTAssertTrue(AdsRules.wantsRun(.waiting))
  }

  func testARunningEpisodeIsFinding() {
    XCTAssertEqual(status(finding: 40), .finding(percent: 40))
    XCTAssertFalse(AdsRules.wantsRun(.finding(percent: 40)))
  }

  func testAResultSaysHowManyWereFound() {
    XCTAssertEqual(status(file: file(ads: 3)), .found(count: 3))
    XCTAssertEqual(status(file: file(ads: 0)), .noneFound)
    XCTAssertFalse(AdsRules.wantsRun(.found(count: 3)))
    XCTAssertFalse(AdsRules.wantsRun(.noneFound))
  }

  func testAResultOfAnotherDetectorVersionIsCheckedAgain() {
    XCTAssertEqual(status(file: file(ads: 3, version: "0")), .waiting)
  }

  func testTheReasonShowsWhenTheModelCannotBeUsed() {
    XCTAssertEqual(
      status(unavailable: .appleIntelligenceOff), .notPossible(reason: "Apple Intelligence is off"))
    XCTAssertEqual(
      status(unavailable: .modelDownloading), .notPossible(reason: "The model is downloading"))
    XCTAssertEqual(
      status(unavailable: .deviceNotEligible),
      .notPossible(reason: "This iPhone can't run Apple Intelligence"))
    XCTAssertEqual(status(unavailable: .systemTooOld), .notPossible(reason: "Needs iOS 26"))
    XCTAssertFalse(AdsRules.wantsRun(status(unavailable: .appleIntelligenceOff)))
  }

  func testASavedResultStillShowsWhenTheModelIsOffNow() {
    XCTAssertEqual(status(file: file(ads: 2), unavailable: .appleIntelligenceOff), .found(count: 2))
  }

  func testAFailureIsNotRetriedInALoop() {
    let failed = status(failure: "Finding ads stopped")
    XCTAssertEqual(failed, .notPossible(reason: "Finding ads stopped"))
    XCTAssertFalse(AdsRules.wantsRun(failed))
  }

  func testTheFailureComesBeforeTheModelsReason() {
    XCTAssertEqual(
      status(unavailable: .modelDownloading, failure: "Finding ads stopped"),
      .notPossible(reason: "Finding ads stopped"))
  }

  func testItRunsOnlyWhileTheAppIsActivePlayingOrInABackgroundTurn() {
    XCTAssertTrue(AdsRules.mayRun(appActive: true, playing: false, inBackgroundTask: false))
    XCTAssertTrue(AdsRules.mayRun(appActive: false, playing: true, inBackgroundTask: false))
    XCTAssertTrue(AdsRules.mayRun(appActive: false, playing: false, inBackgroundTask: true))
    XCTAssertFalse(AdsRules.mayRun(appActive: false, playing: false, inBackgroundTask: false))
  }

  func testOnlyADownloadingModelIsLookedAtAgain() {
    XCTAssertTrue(AdsRules.looksAgainLater(.modelDownloading))
    XCTAssertFalse(AdsRules.looksAgainLater(.appleIntelligenceOff))
    XCTAssertFalse(AdsRules.looksAgainLater(.deviceNotEligible))
    XCTAssertFalse(AdsRules.looksAgainLater(nil))
  }

  func testPercentOfPieces() {
    XCTAssertEqual(AdsRules.percent(done: 0, total: 7), 0)
    XCTAssertEqual(AdsRules.percent(done: 3, total: 7), 42)
    XCTAssertEqual(AdsRules.percent(done: 7, total: 7), 100)
    XCTAssertEqual(AdsRules.percent(done: 9, total: 7), 100)
    XCTAssertEqual(AdsRules.percent(done: 1, total: 0), 0)
  }
}
