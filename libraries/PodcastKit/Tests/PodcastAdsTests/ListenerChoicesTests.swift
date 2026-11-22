import XCTest

@testable import PodcastAds

/// What the listener chose (trims, undone skips) must outlive the finders writing files again.
final class ListenerChoicesTests: XCTestCase {
  private var folder: URL!
  private var store: AdsStore!
  override func setUpWithError() throws {
    folder = try temporaryFolder()
    store = AdsStore(folder: folder, sha256: "aa")
  }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  private func ad(_ start: Double, _ end: Double, _ kind: AdKind = .ad) -> FoundAd {
    FoundAd(start: start, end: end, kind: kind, advertiser: "Acme", confidence: .sure, firstWords: "w")
  }

  @discardableResult
  private func addToPartial(_ ads: [FoundAd], covered: Double = 300) -> Bool {
    LocalAdsFile.addToPartial(
      ads, store: store, detector: "local", detectorVersion: "1", osVersion: "26", duration: 600,
      covered: covered)
  }

  // MARK: Trims

  func testATrimSurvivesASponsorAdThatCutsTheTrimmedPlug() throws {
    XCTAssertTrue(addToPartial([ad(100, 160, .ownPlug)], covered: 200))
    XCTAssertTrue(store.markTrimmed(detector: "local", AdTrim(adStart: 100, end: 130)))
    addToPartial([ad(95, 112, .ad)])
    var skipper = AdSkipper(file: store.best(detector: "local"), settings: AdSkipSettings())
    let skip = try XCTUnwrap(skipper.reached(position: 95, rate: 1, duration: 600, now: 0))
    XCTAssertEqual(skip.target, 130, accuracy: 0.01, "the plug still ends where the listener cut it")
  }

  func testATrimCutsAnAdThatStartsInsideTheTrimmedStretchAndRunsPast() {
    let trims = [AdTrim(adStart: 100, end: 130)]
    XCTAssertEqual(ad(112, 160).trimmed(by: trims).end, 130)
    XCTAssertEqual(ad(95, 112).trimmed(by: trims).end, 112, "it ends before the trim")
    XCTAssertEqual(ad(130, 160).trimmed(by: trims).end, 160, "it starts after the trim")
    XCTAssertEqual(ad(40, 90).trimmed(by: trims).end, 90, "it lies before the trimmed ad")
  }

  // MARK: Undone

  func testAFinalFileWrittenAgainKeepsTheUndoneSkip() throws {
    _ = try LocalAdsFile.saveFinal(
      [ad(10, 40)], store: store, detector: "local", detectorVersion: "", osVersion: "26",
      duration: 600)
    XCTAssertTrue(store.markUndone(detector: "local", adStart: 10))
    let again = try LocalAdsFile.saveFinal(
      [ad(10, 40)], store: store, detector: "local", detectorVersion: "", osVersion: "26",
      duration: 600)
    XCTAssertEqual(again.undone, [UndoneAd(start: 10, end: 40)])
    XCTAssertEqual(again.ads, [], "an undone ad is not found again")
    let skipper = AdSkipper(file: store.best(detector: "local"), settings: AdSkipSettings())
    XCTAssertEqual(skipper.ads, [])
  }

  func testTheModelsFinalFileKeepsWhatWasUndoneInTheLocalFinalFile() async throws {
    let first = ad(10, 40)
    _ = try LocalAdsFile.saveFinal(
      [first], store: store, detector: "fake", detectorVersion: "", osVersion: "26", duration: 300)
    XCTAssertTrue(store.markUndone(detector: "fake", adStart: 10))
    let transcript = makeTranscript(talk(30))
    let detector = FakeDetector(answer: { _ in [] })
    _ = try await AdsRunner.run(
      transcript: transcript, detector: detector, store: store, osVersion: "26")
    XCTAssertEqual(store.load(detector: "fake")?.undone, [UndoneAd(start: 10, end: 40)])
    let after = LocalAdsFile.addToFinal([first], store: store, detector: "fake")
    XCTAssertEqual(after?.ads, [], "the undone ad is not added again")
  }

  func testAnUndoneListIsTheUnionOfTheFinalAndThePartialFile() throws {
    _ = try LocalAdsFile.saveFinal(
      [ad(10, 40), ad(200, 230)], store: store, detector: "local", detectorVersion: "",
      osVersion: "26", duration: 600)
    XCTAssertTrue(store.markUndone(detector: "local", adStart: 10))
    var partial = AdsFile(
      sha256: "aa", detector: "local", detectorVersion: "", osVersion: "26", duration: 600, ads: [],
      undone: [UndoneAd(start: 200, end: 230)], coveredUntil: 0)
    partial.undone.append(UndoneAd(start: 10, end: 40))
    try store.savePartial(partial)
    _ = try LocalAdsFile.saveFinal(
      [], store: store, detector: "local", detectorVersion: "", osVersion: "26", duration: 600)
    let undone = store.load(detector: "local")?.undone ?? []
    XCTAssertEqual(Set(undone.map(\.start)), [10, 200])
    XCTAssertEqual(undone.count, 2, "no skip is listed twice")
  }

  func testAFailedModelRunKeepsTheOlderModelResultAndItsUndone() throws {
    var old = AdsFile(
      sha256: "aa", detector: "local", detectorVersion: "1", osVersion: "26", duration: 3000,
      ads: [ad(100, 130), ad(1200, 1230), ad(2400, 2430)])
    old.undone = [UndoneAd(start: 2400, end: 2430)]
    try store.save(old)
    let partial = AdsFile(
      sha256: "aa", detector: "local", detectorVersion: "2", osVersion: "26", duration: 3000,
      ads: [ad(100, 130)], coveredUntil: 600)
    try store.savePartial(partial)
    let saved = try LocalAdsFile.saveFinal(
      [ad(100, 130)], store: store, detector: "local", detectorVersion: LocalAdsFile.localVersion,
      osVersion: "26", duration: 3000, afterFailure: true)
    XCTAssertEqual(saved.ads.map(\.start), [100, 1200])
    XCTAssertEqual(saved.undone, [UndoneAd(start: 2400, end: 2430)])
    let skipper = AdSkipper(file: store.best(detector: "local"), settings: AdSkipSettings())
    XCTAssertEqual(skipper.ads.map(\.start), [100, 1200])
  }

  func testAFailedModelRunDoesNotKeepALocalOnlyFinalFilesAds() throws {
    _ = try LocalAdsFile.saveFinal(
      [ad(500, 530)], store: store, detector: "local", detectorVersion: LocalAdsFile.localVersion,
      osVersion: "26", duration: 3000)
    let saved = try LocalAdsFile.saveFinal(
      [ad(100, 130)], store: store, detector: "local", detectorVersion: LocalAdsFile.localVersion,
      osVersion: "26", duration: 3000, afterFailure: true)
    XCTAssertEqual(saved.ads.map(\.start), [100])
  }

  func testANewAdBesideAnUndoneOneIsNotJoinedToIt() {
    XCTAssertTrue(addToPartial([ad(100, 130)], covered: 200))
    XCTAssertTrue(store.markUndone(detector: "local", adStart: 100))
    addToPartial([ad(130.2, 170)])
    let file = store.best(detector: "local")
    let skipper = AdSkipper(file: file, settings: AdSkipSettings())
    XCTAssertEqual(skipper.ads.map { [$0.start, $0.end] }, [[130.2, 170]])
    XCTAssertEqual(file?.undone, [UndoneAd(start: 100, end: 130)])
  }

  func testANewAdBesideAnUndoneOneInAFinalFileIsNotJoinedToIt() throws {
    _ = try LocalAdsFile.saveFinal(
      [ad(100, 130)], store: store, detector: "local", detectorVersion: "", osVersion: "26",
      duration: 600)
    XCTAssertTrue(store.markUndone(detector: "local", adStart: 100))
    let file = LocalAdsFile.addToFinal([ad(130.2, 170)], store: store, detector: "local")
    let skipper = AdSkipper(file: file, settings: AdSkipSettings())
    XCTAssertEqual(skipper.ads.map { [$0.start, $0.end] }, [[130.2, 170]])
  }

  func testUndoWorksAfterAJoinMovedTheAdsStart() {
    XCTAssertTrue(addToPartial([ad(100, 130)], covered: 200))
    addToPartial([ad(95, 112)])
    XCTAssertEqual(store.best(detector: "local")?.ads.map(\.start), [95])
    XCTAssertTrue(store.markUndone(detector: "local", adStart: 100), "the skip began at 100")
    XCTAssertEqual(store.best(detector: "local")?.undone, [UndoneAd(start: 95, end: 130)])
  }

  func testUndoOfAStartNoAdCoversIsRefused() {
    XCTAssertTrue(addToPartial([ad(100, 130)], covered: 200))
    XCTAssertFalse(store.markUndone(detector: "local", adStart: 140))
    XCTAssertFalse(store.markUndone(detector: "local", adStart: 50))
  }
}
