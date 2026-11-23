import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// What an answer and the questions of a file must survive: every write of a fresh file (the
/// model's checkpoints, its final file, `LocalAdsFile.saveFinal`) goes through
/// `AdsStore.carryingTrims`, which has to carry them like it carries trims and undone skips.
final class AdAskingCarryTests: XCTestCase {
  private var folder: URL!
  private var store: AdsStore { AdsStore(folder: folder, sha256: "aa") }

  override func setUpWithError() throws { folder = try temporaryFolder() }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  private func ask(_ start: Double, _ end: Double) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .promo, advertiser: "", confidence: .guess,
      firstWords: "words at \(start)", source: "word-model")
  }

  private func ad(_ start: Double, _ end: Double) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "Acme", confidence: .sure, firstWords: "x")
  }

  private func file(
    ads: [FoundAd] = [], asks: [FoundAd]? = nil, version: String = "1", covered: Double? = nil
  ) -> AdsFile {
    AdsFile(
      sha256: "aa", detector: "local", detectorVersion: version, osVersion: "26", duration: 600,
      ads: ads, coveredUntil: covered, asks: asks)
  }

  /// What `AdsRunner`'s checkpoint writes after each piece: a fresh partial file that knows
  /// only the ads the model found so far and the undone skips.
  private func checkpoint(ads: [FoundAd], covered: Double) throws {
    var fresh = file(ads: ads, covered: covered)
    fresh.undone = store.loadPartial(detector: "local")?.undone ?? []
    try store.savePartial(fresh)
  }

  // MARK: A yes

  func testAYesAndTheOtherQuestionSurviveTheModelsNextCheckpoint() throws {
    try store.savePartial(file(asks: [ask(100, 130), ask(300, 330)], covered: 0))
    XCTAssertNotNil(AdAsking.answer(store: store, detector: "local", askStart: 100, isAd: true))
    try checkpoint(ads: [ad(400, 450)], covered: 200)
    let after = try XCTUnwrap(store.loadPartial(detector: "local"))
    XCTAssertEqual(after.ads.map(\.start), [100, 400], "the tap ad is kept, in order of start")
    XCTAssertEqual(after.ads.first?.source, "tap")
    XCTAssertEqual(after.ads.first?.confidence, .sure)
    XCTAssertEqual(after.coveredUntil, 200, "the rest of the file is what the model wrote")
    XCTAssertEqual(AdAsking.open(in: after), [ask(300, 330)], "the second question still waits")
    // And it survives a second checkpoint.
    try checkpoint(ads: [ad(400, 450), ad(500, 540)], covered: 400)
    let again = try XCTUnwrap(store.loadPartial(detector: "local"))
    XCTAssertEqual(again.ads.map(\.start), [100, 400, 500])
    XCTAssertEqual(AdAsking.open(in: again), [ask(300, 330)])
  }

  func testAYesAndTheQuestionsSurviveTheFinalFileOfAModelRun() throws {
    try store.savePartial(file(asks: [ask(100, 130), ask(300, 330)], covered: 0))
    XCTAssertNotNil(AdAsking.answer(store: store, detector: "local", askStart: 100, isAd: true))
    let final = try LocalAdsFile.saveFinal(
      [ad(500, 560)], store: store, detector: "local", detectorVersion: "1", osVersion: "26",
      duration: 600)
    XCTAssertEqual(final.ads.map(\.start), [500])
    let saved = try XCTUnwrap(store.load(detector: "local"))
    XCTAssertEqual(saved.ads.map(\.start), [100, 500])
    XCTAssertEqual(saved.ads.first?.source, "tap")
    XCTAssertEqual(saved.asks, [ask(100, 130), ask(300, 330)])
    XCTAssertEqual(AdAsking.open(in: saved), [ask(300, 330)])
  }

  func testAYesSurvivesARealRunOfTheModel() async throws {
    // The transcript is 30 lines of ten seconds. The listener said yes to a question at 100 to
    // 130 s while the model was still working; then the model's run finishes.
    try store.savePartial(
      AdsFile(
        sha256: "aa", detector: "fake", detectorVersion: "1", osVersion: "26", duration: 300,
        ads: [], coveredUntil: 0, asks: [ask(100, 130), ask(200, 230)]))
    XCTAssertNotNil(AdAsking.answer(store: store, detector: "fake", askStart: 100, isAd: true))
    let detector = FakeDetector(tokenBudget: 150) { piece in
      piece.lines.contains { $0.number == 3 } ? [range(3, 5)] : []
    }
    let outcome = try await AdsRunner.run(
      transcript: makeTranscript(talk(30, ad: 3...5)), detector: detector, store: store,
      osVersion: "26")
    guard case .finished = outcome else { return XCTFail("did not finish") }
    let saved = try XCTUnwrap(store.load(detector: "fake"))
    XCTAssertEqual(saved.ads.filter { $0.source == "tap" }.map(\.start), [100])
    XCTAssertTrue(saved.ads.contains { $0.start < 30 }, "and the model's own ad is there too")
    XCTAssertEqual(AdAsking.open(in: saved), [ask(200, 230)])
    XCTAssertNil(store.loadPartial(detector: "fake"), "the scratch files went")
  }

  func testNoQuestionIsAskedAgainAfterAYes() throws {
    try store.savePartial(file(asks: [ask(100, 130)], covered: 0))
    XCTAssertNotNil(AdAsking.answer(store: store, detector: "local", askStart: 100, isAd: true))
    try checkpoint(ads: [], covered: 200)
    let stored = try XCTUnwrap(store.loadPartial(detector: "local"))
    let again = AdAsking.adding([ask(100, 130), ask(105, 128)], to: stored)
    XCTAssertEqual(again, stored)
    XCTAssertEqual(AdAsking.open(in: again), [])
    XCTAssertNil(AdAsking.live(in: again, at: 110))
  }

  func testTheCapOfThreeCountsTheAnsweredQuestionsAfterAWrite() throws {
    try store.savePartial(
      file(asks: [ask(100, 130), ask(200, 230), ask(300, 330)], covered: 0))
    XCTAssertNotNil(AdAsking.answer(store: store, detector: "local", askStart: 100, isAd: false))
    XCTAssertNotNil(AdAsking.answer(store: store, detector: "local", askStart: 200, isAd: true))
    try checkpoint(ads: [], covered: 200)
    let stored = try XCTUnwrap(store.loadPartial(detector: "local"))
    XCTAssertEqual(stored.asks?.count, 3)
    XCTAssertEqual(AdAsking.adding([ask(500, 530)], to: stored), stored, "no fourth question")
  }

  func testAFileThatWasLoadedBeforeTheWriteCannotBringTheCapOverThree() throws {
    // A caller that adds three new questions to a file it holds in memory, while the saved file
    // already has three (some answered), gets the saved ones back, not six.
    try store.savePartial(
      file(asks: [ask(100, 130), ask(200, 230), ask(300, 330)], covered: 0))
    XCTAssertNotNil(AdAsking.answer(store: store, detector: "local", askStart: 100, isAd: true))
    let stale = AdAsking.adding([ask(500, 530), ask(600, 630), ask(700, 730)], to: file(covered: 100))
    try store.savePartial(stale)
    let saved = try XCTUnwrap(store.loadPartial(detector: "local"))
    XCTAssertEqual(saved.asks?.map(\.start), [100, 200, 300])
    XCTAssertEqual(saved.ads.map(\.start), [100], "and the answered one is still an ad")
  }

  // MARK: What the model found itself

  func testATapAdThatTheModelFoundAgainIsNotAddedTwice() throws {
    try store.savePartial(file(asks: [ask(100, 130)], covered: 0))
    XCTAssertNotNil(AdAsking.answer(store: store, detector: "local", askStart: 100, isAd: true))
    try checkpoint(ads: [ad(95, 135)], covered: 200)
    let after = try XCTUnwrap(store.loadPartial(detector: "local"))
    XCTAssertEqual(after.ads, [ad(95, 135)], "the model's own ad stands; it covers the question")
    XCTAssertEqual(AdAsking.open(in: after), [])
  }

  func testATapAdTheListenerUndidStaysUndone() throws {
    try store.savePartial(file(asks: [ask(100, 130)], covered: 0))
    XCTAssertNotNil(AdAsking.answer(store: store, detector: "local", askStart: 100, isAd: true))
    XCTAssertTrue(store.markUndone(detector: "local", adStart: 100))
    try checkpoint(ads: [ad(400, 450)], covered: 200)
    let after = try XCTUnwrap(store.loadPartial(detector: "local"))
    let tapped = try XCTUnwrap(after.ads.first { $0.source == "tap" })
    XCTAssertTrue(after.isUndone(tapped), "so the player does not skip it again")
    XCTAssertEqual(AdAsking.open(in: after), [])
  }

  // MARK: A no

  func testANoNextToARealAdDoesNotStopTheAd() throws {
    // The question is 12 to 35 s. The model later finds a real ad at 33 to 90 s. A "no" must
    // never silence an ad, so the ad is kept and skipped.
    try store.savePartial(file(asks: [ask(12, 35)], covered: 0))
    XCTAssertNotNil(AdAsking.answer(store: store, detector: "local", askStart: 12, isAd: false))
    let final = try LocalAdsFile.saveFinal(
      [ad(33, 90)], store: store, detector: "local", detectorVersion: "1", osVersion: "26",
      duration: 600)
    XCTAssertEqual(final.ads, [ad(33, 90)])
    let saved = try XCTUnwrap(store.load(detector: "local"))
    XCTAssertEqual(saved.ads, [ad(33, 90)])
    XCTAssertEqual(saved.undone, [], "the no was never an undone skip")
    XCTAssertEqual(saved.denied, [UndoneAd(start: 12, end: 35)], "but it is remembered")
    XCTAssertEqual(AdAsking.open(in: saved), [], "the question is answered, and an ad covers it")
  }

  func testANoNextToAnAdFoundByTheCheckpointsDoesNotStopIt() throws {
    try store.savePartial(file(asks: [ask(12, 35)], covered: 0))
    XCTAssertNotNil(AdAsking.answer(store: store, detector: "local", askStart: 12, isAd: false))
    try checkpoint(ads: [ad(33, 90)], covered: 100)
    let after = try XCTUnwrap(store.loadPartial(detector: "local"))
    XCTAssertEqual(after.ads, [ad(33, 90)])
    XCTAssertFalse(after.isUndone(after.ads[0]))
    XCTAssertEqual(after.denied, [UndoneAd(start: 12, end: 35)], "carried through the checkpoint")
  }

  func testANoSurvivesTheFinalFileAndKeepsTheQuestionClosed() throws {
    try store.savePartial(file(asks: [ask(100, 130)], covered: 0))
    XCTAssertNotNil(AdAsking.answer(store: store, detector: "local", askStart: 100, isAd: false))
    _ = try LocalAdsFile.saveFinal(
      [], store: store, detector: "local", detectorVersion: "1", osVersion: "26", duration: 600)
    let saved = try XCTUnwrap(store.load(detector: "local"))
    XCTAssertEqual(saved.denied, [UndoneAd(start: 100, end: 130)])
    XCTAssertEqual(AdAsking.adding([ask(100, 130)], to: saved), saved)
    XCTAssertEqual(AdAsking.open(in: saved), [])
  }

  func testAnAdIsNeverMatchedAgainstDenied() {
    let f = AdsFile(
      sha256: "aa", detector: "local", detectorVersion: "1", osVersion: "26", duration: 600,
      ads: [ad(33, 90)], denied: [UndoneAd(start: 12, end: 35), UndoneAd(start: 40, end: 80)])
    XCTAssertFalse(f.isUndone(f.ads[0]))
  }
}
