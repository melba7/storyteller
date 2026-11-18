import XCTest

@testable import PodcastAds

/// The trims the listener made (a skip that went too far) are kept in the ads file.
final class AdsStoreTrimTests: XCTestCase {
  private var folder: URL!
  private let sha = String(repeating: "ab", count: 32)

  override func setUpWithError() throws { folder = try temporaryFolder() }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  private func file(trims: [AdTrim]? = nil) -> AdsFile {
    AdsFile(
      sha256: sha, detector: "fake", detectorVersion: "1", osVersion: "26.0", duration: 600,
      ads: [
        FoundAd(
          start: 20, end: 60, kind: .ad, advertiser: "Acme", confidence: .sure, firstWords: "hello")
      ], trims: trims)
  }

  func testAFileSavedBeforeTrimsExistedReadsAsNoTrims() throws {
    let store = AdsStore(folder: folder, sha256: sha)
    try store.save(file())
    let text = try String(contentsOf: store.url(detector: "fake"), encoding: .utf8)
    XCTAssertFalse(text.contains("trims"), "nothing is written when there are none")
    XCTAssertNil(try XCTUnwrap(store.load(detector: "fake")).trims)
  }

  func testATrimIsKeptInTheFinalFile() throws {
    let store = AdsStore(folder: folder, sha256: sha)
    try store.save(file())
    XCTAssertTrue(store.markTrimmed(detector: "fake", AdTrim(adStart: 20, end: 50)))
    XCTAssertEqual(store.load(detector: "fake")?.trims, [AdTrim(adStart: 20, end: 50)])
  }

  func testATrimIsKeptInThePartialFileWhileThereIsNoFinalOne() throws {
    let store = AdsStore(folder: folder, sha256: sha)
    try store.savePartial(file())
    XCTAssertTrue(store.markTrimmed(detector: "fake", AdTrim(adStart: 20.2, end: 50)))
    XCTAssertNil(store.load(detector: "fake"))
    XCTAssertEqual(store.loadPartial(detector: "fake")?.trims, [AdTrim(adStart: 20.2, end: 50)])
  }

  func testOnlyARealAdCanBeTrimmed() throws {
    let store = AdsStore(folder: folder, sha256: sha)
    XCTAssertFalse(store.markTrimmed(detector: "fake", AdTrim(adStart: 20, end: 50)), "no file")
    try store.save(file())
    XCTAssertFalse(store.markTrimmed(detector: "fake", AdTrim(adStart: 300, end: 320)))
    XCTAssertNil(store.load(detector: "fake")?.trims)
  }

  func testTheSameAdKeepsOneTrimWithTheEarlierEnd() throws {
    let store = AdsStore(folder: folder, sha256: sha)
    try store.save(file())
    store.markTrimmed(detector: "fake", AdTrim(adStart: 20, end: 50))
    store.markTrimmed(detector: "fake", AdTrim(adStart: 20, end: 40))
    store.markTrimmed(detector: "fake", AdTrim(adStart: 20, end: 55))
    XCTAssertEqual(store.load(detector: "fake")?.trims, [AdTrim(adStart: 20, end: 40)])
  }

  func testAFileSavedByTheDetectorKeepsTheTrimsMadeMeanwhile() throws {
    let store = AdsStore(folder: folder, sha256: sha)
    try store.savePartial(file())
    store.markTrimmed(detector: "fake", AdTrim(adStart: 20, end: 50))
    // The detector saves the next partial file, and then the final one, without knowing the trim.
    try store.savePartial(file())
    XCTAssertEqual(store.loadPartial(detector: "fake")?.trims, [AdTrim(adStart: 20, end: 50)])
    try store.save(file())
    XCTAssertEqual(store.load(detector: "fake")?.trims, [AdTrim(adStart: 20, end: 50)])
    // And a later run over the final file keeps them too.
    try store.save(file())
    XCTAssertEqual(store.load(detector: "fake")?.trims, [AdTrim(adStart: 20, end: 50)])
  }

  func testWhatTheJsonForTheAppSaysHasTheTrims() throws {
    let store = AdsStore(folder: folder, sha256: sha)
    try store.save(file())
    store.markTrimmed(detector: "fake", AdTrim(adStart: 20, end: 50))
    let text = try XCTUnwrap(store.bestJSON(detector: "fake"))
    let back = try JSONDecoder().decode(AdsFile.self, from: Data(text.utf8))
    XCTAssertEqual(back.trims, [AdTrim(adStart: 20, end: 50)])
  }

  // MARK: Carrying trims from one file to another (a stream's ads moving to its real name)

  func testTrimsAreAddedOneByOneAndTheEarlierEndOfTheSameAdStays() {
    var list: [AdTrim] = []
    list.add(AdTrim(adStart: 20, end: 50))
    list.add(AdTrim(adStart: 20.3, end: 40))
    list.add(AdTrim(adStart: 20, end: 55))
    list.add(AdTrim(adStart: 200, end: 230))
    XCTAssertEqual(list, [AdTrim(adStart: 20, end: 40), AdTrim(adStart: 200, end: 230)])
  }

  func testTrimsCarriedInTheFileAreMergedWithTheOnesOnDiskAndNeverMakeAnAdLonger() throws {
    let store = AdsStore(folder: folder, sha256: sha)
    // The file under the real name already has a trim, made after the download was filed.
    try store.savePartial(file(trims: [AdTrim(adStart: 20, end: 45)]))
    // The stream's head carries the trims made while it streamed: one for the same ad, later.
    try store.savePartial(file(trims: [AdTrim(adStart: 20, end: 55)]))
    XCTAssertEqual(store.loadPartial(detector: "fake")?.trims, [AdTrim(adStart: 20, end: 45)])
    // And one that is earlier shortens it further.
    try store.savePartial(file(trims: [AdTrim(adStart: 20, end: 30)]))
    XCTAssertEqual(store.loadPartial(detector: "fake")?.trims, [AdTrim(adStart: 20, end: 30)])
  }

  func testAStreamsTrimSurvivesTheMoveToTheRealName() throws {
    // While it streams, the ads are under a made-up name and the listener trims one.
    let stream = AdsStore(folder: folder, sha256: "stream-ep1")
    var streamFile = file()
    streamFile.sha256 = "stream-ep1"
    try stream.savePartial(streamFile)
    XCTAssertTrue(stream.markTrimmed(detector: "fake", AdTrim(adStart: 20, end: 50)))
    // The head keeps what it read from that file, then the file goes away with the folder.
    var carried: [AdTrim] = []
    for trim in stream.loadPartial(detector: "fake")?.trims ?? [] { carried.add(trim) }
    stream.discardPartial(detector: "fake")
    // Saved again under the real hash, the ad is still trimmed.
    let real = AdsStore(folder: folder, sha256: sha)
    try real.savePartial(file(trims: carried))
    XCTAssertEqual(real.loadPartial(detector: "fake")?.trims, [AdTrim(adStart: 20, end: 50)])
    XCTAssertEqual(real.best(detector: "fake")?.ads.first?.trimmed(by: carried).end, 50)
  }
}
