import XCTest

@testable import PodcastAds

/// `AdAsking.answer(store:...)`: the answer is saved in the file it was found in.
final class AdAskingStoreTests: XCTestCase {
  private func ask(_ start: Double, _ end: Double) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .promo, advertiser: "", confidence: .guess,
      firstWords: "words at \(start)", source: "word-model")
  }

  private func ad(_ start: Double, _ end: Double) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "Acme", confidence: .sure,
      firstWords: "brought to you")
  }

  private func file(
    ads: [FoundAd] = [], asks: [FoundAd]? = nil, coveredUntil: Double? = nil
  ) -> AdsFile {
    AdsFile(
      sha256: "abc", detector: "local", detectorVersion: "1", osVersion: "26", duration: 3600,
      ads: ads, coveredUntil: coveredUntil, asks: asks)
  }

  private func tempFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
    return folder
  }

  // MARK: Through the store

  func testAnAnswerIsSavedInTheFinalFile() throws {
    let store = AdsStore(folder: try tempFolder(), sha256: "abc")
    try store.save(file(ads: [ad(30, 60)], asks: [ask(100, 130)]))
    let answered = AdAsking.answer(store: store, detector: "local", askStart: 100, isAd: true)
    XCTAssertEqual(answered, ask(100, 130), "the question that was answered")
    let saved = try XCTUnwrap(store.load(detector: "local"))
    XCTAssertEqual(saved.ads.map(\.start), [30, 100])
    XCTAssertEqual(saved.ads.map(\.source), [nil, "tap"])
    XCTAssertEqual(saved.asks, [AdAsking.answered(ask(100, 130))], "kept, and no longer open")
    XCTAssertEqual(AdAsking.open(in: saved), [])
    XCTAssertNil(store.loadPartial(detector: "local"), "no partial file was made")
  }

  func testAnAnswerIsSavedInThePartialFileWhileTheEpisodeIsStillBeingChecked() throws {
    let store = AdsStore(folder: try tempFolder(), sha256: "abc")
    try store.savePartial(file(asks: [ask(100, 130)], coveredUntil: 600))
    XCTAssertNotNil(AdAsking.answer(store: store, detector: "local", askStart: 100, isAd: false))
    XCTAssertNil(store.load(detector: "local"), "no final file was made")
    let partial = try XCTUnwrap(store.loadPartial(detector: "local"))
    XCTAssertEqual(partial.denied, [UndoneAd(start: 100, end: 130)])
    XCTAssertEqual(partial.undone, [])
    XCTAssertEqual(partial.coveredUntil, 600)
  }

  func testAStoreWithNoOpenQuestionAnswersNilAndWritesNothing() throws {
    let folder = try tempFolder()
    let store = AdsStore(folder: folder, sha256: "abc")
    XCTAssertNil(AdAsking.answer(store: store, detector: "local", askStart: 100, isAd: true))
    try store.save(file(ads: [ad(30, 60)]))
    XCTAssertNil(AdAsking.answer(store: store, detector: "local", askStart: 100, isAd: true))
    XCTAssertEqual(store.load(detector: "local")?.ads, [ad(30, 60)])
  }
}
