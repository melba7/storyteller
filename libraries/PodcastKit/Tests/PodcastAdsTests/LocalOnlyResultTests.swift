import XCTest

@testable import PodcastAds

/// A final ads file made by the local finders alone (`detectorVersion` empty): when it counts as
/// the result, and what is kept when it is made.
final class LocalOnlyResultTests: XCTestCase {
  private var folder: URL!
  private var store: AdsStore!
  override func setUpWithError() throws {
    folder = try temporaryFolder()
    store = AdsStore(folder: folder, sha256: "aa")
  }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  private func ad(_ start: Double, _ end: Double, _ kind: AdKind = .ad) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: kind, advertiser: "Acme", confidence: .sure, firstWords: "w")
  }

  private func file(ads: Int, version: String) -> AdsFile {
    AdsFile(
      sha256: "aa", detector: "fake", detectorVersion: version, osVersion: "26.0", duration: 600,
      ads: (0..<ads).map { ad(Double($0) * 100, Double($0) * 100 + 40) })
  }

  private func status(
    _ file: AdsFile?, running: String = "2", finding: Int? = nil, unavailable: AdUnavailable? = nil,
    failure: String? = nil
  ) -> AdsStatus {
    AdsRules.status(
      file: file, partial: nil, detectorVersion: running, finding: finding, unavailable: unavailable,
      failure: failure)
  }

  // MARK: Status

  func testTheVersionIsEmpty() {
    XCTAssertEqual(LocalAdsFile.localVersion, "")
  }

  func testALocalResultIsTheResultWhileTheModelCannotBeAsked() {
    let local = file(ads: 2, version: LocalAdsFile.localVersion)
    XCTAssertEqual(status(local, unavailable: .appleIntelligenceOff), .found(count: 2))
    XCTAssertEqual(status(local, unavailable: .modelDownloading), .found(count: 2))
    XCTAssertEqual(status(local, unavailable: .systemTooOld), .found(count: 2))
    XCTAssertEqual(status(file(ads: 0, version: ""), unavailable: .deviceNotEligible), .noneFound)
    XCTAssertFalse(AdsRules.wantsRun(status(local, unavailable: .appleIntelligenceOff)))
  }

  func testALocalResultIsTheResultAfterAFailureOfTheModel() {
    let local = file(ads: 1, version: LocalAdsFile.localVersion)
    XCTAssertEqual(status(local, failure: "Finding ads stopped"), .found(count: 1))
    XCTAssertFalse(AdsRules.wantsRun(status(local, failure: "x"), failure: "x"))
  }

  func testALocalResultIsOldWhenTheModelCanBeAsked() {
    let local = file(ads: 2, version: LocalAdsFile.localVersion)
    XCTAssertEqual(status(local), .waiting)
    XCTAssertTrue(AdsRules.wantsRun(status(local)))
  }

  func testAFinalFileOfAnotherVersionIsStillOldWhateverTheModelSays() {
    let older = file(ads: 2, version: "1")
    XCTAssertEqual(status(older, unavailable: .appleIntelligenceOff), .notPossible(reason: "Apple Intelligence is off"))
    XCTAssertEqual(status(older, failure: "x"), .notPossible(reason: "x"))
  }

  func testTheModelsOwnResultStillCountsAndARunStillShowsItsPercent() {
    XCTAssertEqual(status(file(ads: 3, version: "2")), .found(count: 3))
    XCTAssertEqual(status(file(ads: 3, version: ""), finding: 40), .finding(percent: 40))
  }

  func testALocalResultWhenThereIsNoModelAtAll() {
    // No detector: the running version is empty too, which is the local version.
    XCTAssertEqual(
      status(file(ads: 1, version: ""), running: "", unavailable: .systemTooOld), .found(count: 1))
  }

  // MARK: When a whole transcript is queued

  func testAWholeTranscriptWithNoFinalFileIsQueuedWhenTheModelCannotBeAsked() {
    for shown: AdsStatus in [.waiting, .partialFound(count: 1), .notPossible(reason: "x")] {
      XCTAssertTrue(
        AdsRules.wantsLocalRun(shown, failure: nil, hasFinal: false, unavailable: .appleIntelligenceOff))
    }
  }

  func testItIsNotQueuedWhenItHasAResultAFailureOrAModel() {
    let off = AdUnavailable.appleIntelligenceOff
    XCTAssertFalse(AdsRules.wantsLocalRun(.waiting, failure: nil, hasFinal: true, unavailable: off))
    XCTAssertFalse(AdsRules.wantsLocalRun(.waiting, failure: "x", hasFinal: false, unavailable: off))
    XCTAssertFalse(AdsRules.wantsLocalRun(.waiting, failure: nil, hasFinal: false, unavailable: nil))
    XCTAssertFalse(AdsRules.wantsLocalRun(.found(count: 1), failure: nil, hasFinal: false, unavailable: off))
    XCTAssertFalse(AdsRules.wantsLocalRun(.finding(percent: 5), failure: nil, hasFinal: false, unavailable: off))
  }

  // MARK: Saving it

  func testAFailedRunKeepsWhatTheModelFoundSoFarAndItsAnswers() throws {
    var partial = AdsFile(
      sha256: "aa", detector: "local", detectorVersion: "2", osVersion: "26.0", duration: 600,
      ads: [ad(300, 340)], undone: [UndoneAd(start: 500, end: 530)], coveredUntil: 350)
    partial.refusedPieces = 1
    try store.savePartial(partial)
    var progress = AdProgress(sha256: "aa", detector: "local", detectorVersion: "2")
    progress.answers["k"] = []
    try store.saveProgress(progress)
    let saved = try LocalAdsFile.saveFinal(
      [ad(10, 40)], store: store, detector: "local", detectorVersion: LocalAdsFile.localVersion,
      osVersion: "26.0", duration: 600, afterFailure: true)
    XCTAssertEqual(saved.ads.map(\.start), [10, 300], "the model's ads stay")
    XCTAssertEqual(saved.detectorVersion, "")
    XCTAssertEqual(saved.undone, [UndoneAd(start: 500, end: 530)])
    XCTAssertNotNil(store.loadPartial(detector: "local"), "the scratch files stay")
    XCTAssertEqual(store.loadProgress(detector: "local", version: "2").answers.count, 1)
  }

  func testWithoutAFailureTheScratchFilesGoAsBefore() throws {
    try store.saveProgress(AdProgress(sha256: "aa", detector: "local", detectorVersion: "2"))
    _ = try LocalAdsFile.saveFinal(
      [ad(10, 40)], store: store, detector: "local", detectorVersion: "", osVersion: "26.0",
      duration: 600)
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: folder.appendingPathComponent("aa.ads.local.progress.json").path))
  }

  func testWhatTheListenerSaidAboutALocalResultSurvivesTheModelsRun() throws {
    _ = try LocalAdsFile.saveFinal(
      [ad(10, 40), ad(100, 130)], store: store, detector: "local", detectorVersion: "",
      osVersion: "26.0", duration: 600)
    XCTAssertTrue(store.markUndone(detector: "local", adStart: 10))
    LocalAdsFile.carryChoices(store: store, detector: "local")
    let partial = try XCTUnwrap(store.loadPartial(detector: "local"))
    XCTAssertEqual(partial.undone, [UndoneAd(start: 10, end: 40)])
    XCTAssertEqual(partial.ads, [])
    // The player still reads the final file until the model's run replaces it.
    XCTAssertEqual(store.best(detector: "local")?.detectorVersion, "")
    XCTAssertEqual(store.best(detector: "local")?.undone, [UndoneAd(start: 10, end: 40)])
    // And once is enough.
    LocalAdsFile.carryChoices(store: store, detector: "local")
    XCTAssertEqual(store.loadPartial(detector: "local")?.undone.count, 1)
  }

  func testNothingIsCarriedFromAFinalFileOfTheModelOrFromNoFile() throws {
    LocalAdsFile.carryChoices(store: store, detector: "local")
    XCTAssertNil(store.loadPartial(detector: "local"))
    try store.save(file(ads: 1, version: "2").with(detector: "local", undone: [UndoneAd(start: 0, end: 40)]))
    LocalAdsFile.carryChoices(store: store, detector: "local")
    XCTAssertNil(store.loadPartial(detector: "local"))
  }
}

extension AdsFile {
  fileprivate func with(detector: String, undone: [UndoneAd]) -> AdsFile {
    var copy = self
    copy.detector = detector
    copy.undone = undone
    return copy
  }
}
