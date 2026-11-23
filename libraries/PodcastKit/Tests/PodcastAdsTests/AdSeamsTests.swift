import XCTest

@testable import PodcastAds

/// The two optional fields that let a finder say where an ad came from and let the phone keep
/// questions: `FoundAd.source` and `AdsFile.asks`. Files written before them must still read.
final class AdSeamsTests: XCTestCase {
  /// An ads file as a build from before `source` and `asks` wrote it.
  private let oldFile = #"""
    {"ads":[{"advertiser":"Acme","confidence":"sure","end":60,"firstWords":"brought to you","kind":"ad","start":30}],"detector":"local","detectorVersion":"1","duration":3600,"osVersion":"26","sha256":"abc","undone":[],"version":1}
    """#

  private func ad(
    _ start: Double, _ end: Double, _ kind: AdKind = .ad, source: String? = nil,
    _ confidence: AdConfidence = .sure
  ) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: kind, advertiser: "", confidence: confidence, firstWords: "",
      source: source)
  }

  private func tempFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
    return folder
  }

  // MARK: Old files still read

  func testAnOldAdsFileReadsWithNoAsksAndNoSource() throws {
    let file = try JSONDecoder().decode(AdsFile.self, from: Data(oldFile.utf8))
    XCTAssertNil(file.asks)
    XCTAssertEqual(file.ads.count, 1)
    XCTAssertNil(file.ads[0].source)
    XCTAssertEqual(file.ads[0].advertiser, "Acme")
    XCTAssertEqual(file.version, AdsFile.currentVersion, "the file's version rule did not change")
  }

  func testAnOldFileOnDiskLoadsThroughTheStore() throws {
    let store = AdsStore(folder: try tempFolder(), sha256: "abc")
    try Data(oldFile.utf8).write(to: store.url(detector: "local"))
    let file = try XCTUnwrap(store.load(detector: "local"))
    XCTAssertNil(file.asks)
    XCTAssertEqual(file.ads.map(\.start), [30])
  }

  func testAFileWithNoAsksAndNoSourceIsWrittenWithoutThem() throws {
    let file = AdsFile(
      sha256: "abc", detector: "local", detectorVersion: "1", osVersion: "26", duration: 3600,
      ads: [ad(30, 60)])
    let text = String(decoding: try AdsStore.encoder.encode(file), as: UTF8.self)
    XCTAssertFalse(text.contains("asks"))
    XCTAssertFalse(text.contains("source"))
  }

  func testANewerFileWithAnUnknownVersionStillReadsAsNoFile() throws {
    let store = AdsStore(folder: try tempFolder(), sha256: "abc")
    let newer = oldFile.replacingOccurrences(of: #""version":1"#, with: #""version":2"#)
    try Data(newer.utf8).write(to: store.url(detector: "local"))
    XCTAssertNil(store.load(detector: "local"))
  }

  // MARK: Round trip

  func testSourceAndAsksRoundTripThroughTheStore() throws {
    let store = AdsStore(folder: try tempFolder(), sha256: "abc")
    let question = ad(500, 540, .promo, source: "repeat-words", .guess)
    let file = AdsFile(
      sha256: "abc", detector: "local", detectorVersion: "1", osVersion: "26", duration: 3600,
      ads: [ad(30, 60, source: "own-sound")], asks: [question])
    try store.save(file)
    let back = try XCTUnwrap(store.load(detector: "local"))
    XCTAssertEqual(back.ads.first?.source, "own-sound")
    XCTAssertEqual(back.asks, [question])
    XCTAssertEqual(back, file)
    let text = try XCTUnwrap(store.json(detector: "local"))
    XCTAssertTrue(text.contains(#""source":"own-sound""#))
    XCTAssertTrue(text.contains(#""asks""#))
  }

  func testAnEmptyAsksListIsKeptAsEmptyNotAsNil() throws {
    let file = AdsFile(
      sha256: "abc", detector: "local", detectorVersion: "1", osVersion: "26", duration: 3600,
      ads: [], asks: [])
    let back = try JSONDecoder().decode(
      AdsFile.self, from: try AdsStore.encoder.encode(file))
    XCTAssertEqual(back.asks, [])
  }

  func testSavingAgainKeepsTheAsksOfTheFileBeingSaved() throws {
    let store = AdsStore(folder: try tempFolder(), sha256: "abc")
    let question = ad(500, 540, source: "meaning", .guess)
    var file = AdsFile(
      sha256: "abc", detector: "local", detectorVersion: "1", osVersion: "26", duration: 3600,
      ads: [ad(30, 60)], asks: [question])
    try store.save(file)
    XCTAssertTrue(store.markUndone(detector: "local", adStart: 30))
    file = try XCTUnwrap(store.load(detector: "local"))
    XCTAssertEqual(file.asks, [question], "an undo does not drop the questions")
    XCTAssertEqual(file.undone.map(\.start), [30])
  }

  // MARK: Joining keeps the source only when every part has it

  func testJoinedAdsWithTheSameSourceKeepIt() {
    let joined = AdJoin.join([
      ad(0, 40, source: "own-sound"), ad(30, 90, source: "own-sound"), ad(90.2, 120, source: "own-sound"),
    ])
    XCTAssertEqual(joined.count, 1)
    XCTAssertEqual(joined[0].source, "own-sound")
  }

  func testJoinedAdsWithDifferentSourcesLoseIt() {
    let joined = AdJoin.join([ad(0, 40, source: "own-sound"), ad(30, 90, source: "meaning")])
    XCTAssertEqual(joined.count, 1)
    XCTAssertNil(joined[0].source)
  }

  func testAnAdWithNoSourceJoinedToOneWithASourceHasNone() {
    // The old finders give no source. A stretch they share with a new finder is not "only" the
    // new finder's, so it carries no name.
    XCTAssertNil(AdJoin.join([ad(0, 40), ad(30, 90, source: "meaning")])[0].source)
    XCTAssertNil(AdJoin.join([ad(0, 40, source: "meaning"), ad(30, 90)])[0].source)
    XCTAssertNil(AdJoin.join([ad(0, 40), ad(30, 90)])[0].source)
  }

  func testOnceASourceIsLostAFurtherPartDoesNotBringItBack() {
    let joined = AdJoin.join([
      ad(0, 40, source: "own-sound"), ad(35, 80, source: "meaning"), ad(75, 120, source: "own-sound"),
    ])
    XCTAssertEqual(joined.count, 1)
    XCTAssertNil(joined[0].source)
  }

  func testAdsThatAreNotJoinedKeepTheirOwnSource() {
    let joined = AdJoin.join([
      ad(0, 40, source: "own-sound"), ad(200, 260, source: "meaning"), ad(400, 460),
    ])
    XCTAssertEqual(joined.map(\.source), ["own-sound", "meaning", nil])
  }

  func testAPartCutOutOfAnAdKeepsThatAdsSource() {
    // The promo is cut back to what lies outside the ad; each keeps its own source.
    let joined = AdJoin.join([
      ad(100, 200, .ad, source: "own-sound"), ad(150, 260, .promo, source: "repeat-words"),
    ])
    XCTAssertEqual(joined.map(\.kind), [.ad, .promo])
    XCTAssertEqual(joined.map(\.source), ["own-sound", "repeat-words"])
  }

  func testJoiningDoesNotChangeWhatTheOldFieldsGive() {
    // The same ads with and without sources join to the same stretches and names.
    let plain = [ad(0, 45), ad(40, 70, .ad, .unsure), ad(300, 400, .credits)]
    let named = plain.map { var one = $0; one.source = "meaning"; return one }
    let a = AdJoin.join(plain)
    let b = AdJoin.join(named)
    XCTAssertEqual(a.map(\.start), b.map(\.start))
    XCTAssertEqual(a.map(\.end), b.map(\.end))
    XCTAssertEqual(a.map(\.confidence), b.map(\.confidence))
    XCTAssertEqual(b.map(\.source), ["meaning", "meaning"])
  }
}
