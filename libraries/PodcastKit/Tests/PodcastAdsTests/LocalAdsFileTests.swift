import XCTest

@testable import PodcastAds

/// The local finders' ads put into an episode's partial and final ads files.
final class LocalAdsFileTests: XCTestCase {
  private var folder: URL!
  private var store: AdsStore!
  override func setUpWithError() throws {
    folder = try temporaryFolder()
    store = AdsStore(folder: folder, sha256: "aa")
  }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  private func ad(
    _ start: Double, _ end: Double, _ kind: AdKind = .ad, _ name: String = "Acme"
  ) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: kind, advertiser: name, confidence: .sure, firstWords: "w")
  }

  @discardableResult
  private func partial(_ found: [FoundAd], covered: Double = 100) -> Bool {
    LocalAdsFile.addToPartial(
      found, store: store, detector: "local", detectorVersion: "1", osVersion: "26.0",
      duration: 600, covered: covered)
  }

  func testAPartialFileIsMadeWhenThereIsNone() {
    XCTAssertTrue(partial([ad(10, 40)], covered: 90))
    let file = store.loadPartial(detector: "local")
    XCTAssertEqual(file?.ads, [ad(10, 40)])
    XCTAssertEqual(file?.coveredUntil, 90)
    XCTAssertEqual(file?.detectorVersion, "1")
    XCTAssertEqual(file?.duration, 600)
  }

  func testNothingToAddMakesNoFile() {
    XCTAssertFalse(partial([]))
    XCTAssertNil(store.loadPartial(detector: "local"))
  }

  func testAfterAModelPassThatWroteItsOwnAdsBothAreKept() throws {
    var model = AdsFile(
      sha256: "aa", detector: "local", detectorVersion: "7", osVersion: "26.0", duration: 600,
      ads: [ad(200, 240)], undone: [UndoneAd(start: 300, end: 330)], coveredUntil: 250,
      refusedPieces: 2)
    model.addTrim(AdTrim(adStart: 200, end: 230))
    try store.savePartial(model)
    XCTAssertTrue(partial([ad(10, 40)], covered: 100), "the ads changed")
    let file = try XCTUnwrap(store.loadPartial(detector: "local"))
    XCTAssertEqual(file.ads.map(\.start), [10, 200])
    XCTAssertEqual(file.coveredUntil, 250, "never goes back")
    XCTAssertEqual(file.detectorVersion, "7")
    XCTAssertEqual(file.undone, [UndoneAd(start: 300, end: 330)])
    XCTAssertEqual(file.refusedPieces, 2)
    XCTAssertEqual(file.trims, [AdTrim(adStart: 200, end: 230)])
  }

  func testTheCoveredPlaceGrowsAndTheFileIsWrittenOnlyWhenSomethingChanged() throws {
    XCTAssertTrue(partial([ad(10, 40)], covered: 90))
    XCTAssertFalse(partial([ad(10, 40)], covered: 90), "nothing changed")
    XCTAssertFalse(partial([ad(10, 40)], covered: 50), "a smaller covered place changes nothing")
    XCTAssertTrue(partial([ad(10, 40)], covered: 120), "only the covered place changed")
    XCTAssertEqual(store.loadPartial(detector: "local")?.coveredUntil, 120)
    XCTAssertTrue(partial([], covered: 130))
    XCTAssertEqual(store.loadPartial(detector: "local")?.ads, [ad(10, 40)])
  }

  func testAnUndoneAdIsNotAddedAgain() throws {
    XCTAssertTrue(partial([ad(10, 40)]))
    XCTAssertTrue(store.markUndone(detector: "local", adStart: 10))
    var file = try XCTUnwrap(store.loadPartial(detector: "local"))
    file.ads = []
    try store.savePartial(file)
    XCTAssertFalse(partial([ad(10.2, 41)], covered: 100), "the same ad found again")
    XCTAssertEqual(store.loadPartial(detector: "local")?.ads, [])
    XCTAssertTrue(partial([ad(10.2, 41), ad(100, 130)], covered: 110))
    XCTAssertEqual(store.loadPartial(detector: "local")?.ads, [ad(100, 130)])
  }

  func testNothingIsAddedToPartialWhenAFinalFileExists() throws {
    try store.save(
      AdsFile(
        sha256: "aa", detector: "local", detectorVersion: "1", osVersion: "26.0", duration: 600,
        ads: [ad(200, 240)]))
    XCTAssertFalse(partial([ad(10, 40)]))
    XCTAssertNil(store.loadPartial(detector: "local"))
  }

  func testSaveFinalThenAddToFinal() throws {
    XCTAssertNil(LocalAdsFile.addToFinal([ad(10, 40)], store: store, detector: "local"))
    let saved = try LocalAdsFile.saveFinal(
      [ad(10, 40), ad(30, 60)], store: store, detector: "local", detectorVersion: "1",
      osVersion: "26.0", duration: 600)
    XCTAssertEqual(saved.ads, [ad(10, 60)])
    XCTAssertNil(saved.coveredUntil)
    XCTAssertEqual(store.load(detector: "local"), saved)
    let added = LocalAdsFile.addToFinal([ad(200, 240)], store: store, detector: "local")
    XCTAssertEqual(added?.ads.map(\.start), [10, 200])
    XCTAssertEqual(store.load(detector: "local")?.ads.map(\.start), [10, 200])
    let again = LocalAdsFile.addToFinal([ad(200, 240)], store: store, detector: "local")
    XCTAssertEqual(again, added, "nothing changed, so the file is as it was")
  }

  func testSaveFinalCarriesTheUndoneListAndRemovesTheScratchFiles() throws {
    XCTAssertTrue(partial([ad(10, 40)]))
    XCTAssertTrue(store.markUndone(detector: "local", adStart: 10))
    try store.saveProgress(AdProgress(sha256: "aa", detector: "local", detectorVersion: "1"))
    let saved = try LocalAdsFile.saveFinal(
      [ad(10, 40), ad(100, 130)], store: store, detector: "local", detectorVersion: "1",
      osVersion: "26.0", duration: 600)
    XCTAssertEqual(saved.undone, [UndoneAd(start: 10, end: 40)])
    XCTAssertEqual(saved.ads, [ad(100, 130)])
    XCTAssertNil(store.loadPartial(detector: "local"))
    XCTAssertEqual(store.loadProgress(detector: "local", version: "1").answers, [:])
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: folder.appendingPathComponent("aa.ads.local.progress.json").path))
  }

  func testAnUndoneAdIsNotAddedToTheFinalFile() throws {
    var file = AdsFile(
      sha256: "aa", detector: "local", detectorVersion: "1", osVersion: "26.0", duration: 600,
      ads: [], undone: [UndoneAd(start: 10, end: 40)])
    try store.save(file)
    file = try XCTUnwrap(LocalAdsFile.addToFinal([ad(10, 40)], store: store, detector: "local"))
    XCTAssertEqual(file.ads, [])
  }
}
