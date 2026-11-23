import XCTest

@testable import PodcastAds

/// A "yes" is recorded in the question itself, and every write of an ads file rebuilds a
/// "tap" ad for the parts of the confirmed stretch that no ad of the file covers. The ad made by
/// the yes cannot be what keeps it: `AdJoin` drops an ad's source when it joins it with a
/// touching ad, a model's checkpoint does not hold it, and a model ad may cover only a part.
final class AdAskingJoinTests: XCTestCase {
  private var folder: URL!
  private var store: AdsStore { AdsStore(folder: folder, sha256: "aa") }

  override func setUpWithError() throws { folder = try temporaryFolder() }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  private func ask(_ start: Double, _ end: Double) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "", confidence: .guess,
      firstWords: "question", source: "word-model")
  }

  private func ad(_ start: Double, _ end: Double) -> FoundAd {
    FoundAd(start: start, end: end, kind: .ad, advertiser: "Acme", confidence: .sure, firstWords: "x")
  }

  private func file(
    ads: [FoundAd] = [], asks: [FoundAd]? = nil, version: String = "1", covered: Double? = nil
  ) -> AdsFile {
    AdsFile(
      sha256: "aa", detector: "local", detectorVersion: version, osVersion: "26", duration: 600,
      ads: ads, coveredUntil: covered, asks: asks)
  }

  /// What the model's checkpoint writes: a fresh partial file with the ads it found so far.
  private func checkpoint(ads: [FoundAd], covered: Double) throws {
    var fresh = file(ads: ads, covered: covered)
    fresh.undone = store.loadPartial(detector: "local")?.undone ?? []
    try store.savePartial(fresh)
  }

  /// Whether the ads the player would skip (those not undone) cover every second from `from` to `to`.
  private func plays(_ file: AdsFile, _ from: Double, _ to: Double) -> Bool {
    var reached = from
    for ad in file.ads.filter({ !file.isUndone($0) }).sorted(by: { $0.start < $1.start }) {
      if ad.start <= reached + 0.001 { reached = max(reached, ad.end) }
    }
    return reached >= to - 0.001
  }

  private func yes(_ start: Double) {
    XCTAssertNotNil(AdAsking.answer(store: store, detector: "local", askStart: start, isAd: true))
  }

  // MARK: A join strips the source

  func testAYesSurvivesALocalAdThatTheJoinMakesOneAdWith() throws {
    // A local ad 50 to 100 touches the question 100 to 130. Every pass the model's checkpoint
    // writes a fresh file and the local finder's ad is added and joined with what is there.
    try store.savePartial(file(asks: [ask(100, 130)], covered: 0))
    yes(100)
    for covered in [200.0, 300, 400] {
      try checkpoint(ads: [], covered: covered)
      LocalAdsFile.addToPartial(
        [ad(50, 100)], store: store, detector: "local", detectorVersion: "1", osVersion: "26",
        duration: 600, covered: covered)
      let now = try XCTUnwrap(store.loadPartial(detector: "local"))
      XCTAssertTrue(plays(now, 50, 130), "the confirmed stretch plays at \(covered): \(now.ads)")
      XCTAssertEqual(AdAsking.open(in: now), [], "and it is not asked again at \(covered)")
    }
  }

  func testAYesSurvivesAFinalJoinAndTheNextModelVersionsFinalFile() throws {
    try store.save(file(asks: [ask(100, 130)]))
    yes(100)
    let joined = LocalAdsFile.addToFinal([ad(130.2, 180)], store: store, detector: "local")
    XCTAssertEqual(joined?.ads.map(\.start), [100], "the join made one ad 100 to 180")
    XCTAssertNil(joined?.ads.first?.source, "and lost the source")
    // The next model version saves its own final file, which knows nothing of that stretch.
    try store.save(file(ads: [ad(300, 360)], version: "2"))
    let after = try XCTUnwrap(store.load(detector: "local"))
    XCTAssertTrue(plays(after, 100, 130), "\(after.ads)")
    XCTAssertTrue(plays(after, 300, 360))
    XCTAssertEqual(AdAsking.open(in: after), [])
  }

  // MARK: An ad over only a part

  func testAYesKeepsTheStretchThatANewAdDoesNotCover() throws {
    try store.savePartial(file(asks: [ask(100, 130)], covered: 0))
    yes(100)
    try checkpoint(ads: [ad(125, 200)], covered: 300)
    let after = try XCTUnwrap(store.loadPartial(detector: "local"))
    XCTAssertEqual(after.ads.map(\.start), [100, 125])
    XCTAssertEqual(after.ads.map(\.end), [125, 200], "the confirmed part is cut where the model's ad starts")
    XCTAssertEqual(after.ads.map(\.source), ["tap", nil])
    XCTAssertEqual(after.ads.first?.confidence, .sure)
    XCTAssertEqual(AdAsking.open(in: after), [])
  }

  func testTheConfirmedStretchComesBackInPiecesAroundSeveralNewAds() throws {
    try store.savePartial(file(asks: [ask(100, 130)], covered: 0))
    yes(100)
    try checkpoint(ads: [ad(110, 115), ad(120, 125)], covered: 300)
    let after = try XCTUnwrap(store.loadPartial(detector: "local"))
    XCTAssertEqual(after.ads.map(\.start), [100, 110, 115, 120, 125])
    XCTAssertEqual(after.ads.map(\.source), ["tap", nil, "tap", nil, "tap"])
    XCTAssertTrue(plays(after, 100, 130))
  }

  func testASliverUnderHalfASecondIsNotMadeAnAd() throws {
    try store.savePartial(file(asks: [ask(100, 130)], covered: 0))
    yes(100)
    try checkpoint(ads: [ad(100.2, 200)], covered: 300)
    let after = try XCTUnwrap(store.loadPartial(detector: "local"))
    XCTAssertEqual(after.ads, [ad(100.2, 200)])
  }

  func testAnAdThatCoversTheWholeYesIsNotDoubled() throws {
    try store.savePartial(file(asks: [ask(100, 130)], covered: 0))
    yes(100)
    for covered in [200.0, 300] {
      try checkpoint(ads: [ad(95, 135)], covered: covered)
      let after = try XCTUnwrap(store.loadPartial(detector: "local"))
      XCTAssertEqual(after.ads, [ad(95, 135)], "the model's own ad stands")
    }
  }

  // MARK: Undone, a stale file, a no

  func testAnUndoneYesIsNotMadeAnAdAgainWhateverTheOrderOfTheFiles() throws {
    // The yes is in the final file; the undo of its skip is only in the partial file.
    try store.save(file(asks: [ask(100, 130)]))
    yes(100)
    var partial = file(covered: 0)
    partial.undone = [UndoneAd(start: 100, end: 130)]
    try store.savePartial(partial)
    try store.save(file(ads: [ad(400, 450)], version: "2"))
    let after = try XCTUnwrap(store.load(detector: "local"))
    XCTAssertEqual(after.ads, [ad(400, 450)])
    XCTAssertEqual(AdAsking.open(in: after), [])
  }

  func testAFileLoadedBeforeTheAnswersCannotTakeThemBack() throws {
    try store.save(file(ads: [ad(30, 60)], asks: [ask(100, 130), ask(300, 330)], version: ""))
    let stale = try XCTUnwrap(store.load(detector: "local"))
    yes(100)
    XCTAssertNotNil(AdAsking.answer(store: store, detector: "local", askStart: 300, isAd: false))
    var older = stale
    older.ads.append(ad(500, 560))
    try store.save(older)
    let after = try XCTUnwrap(store.load(detector: "local"))
    XCTAssertEqual(after.ads.map(\.start), [30, 100, 500])
    XCTAssertEqual(after.ads.map(\.source), [nil, "tap", nil])
    XCTAssertEqual(after.denied, [UndoneAd(start: 300, end: 330)])
    XCTAssertEqual(AdAsking.open(in: after), [], "neither question is open again")
    XCTAssertEqual(after.asks?.map(\.confidence), [.sure, .guess], "the yes is still recorded")
  }

  func testANoAndThenAnAdOverTheSameStretchIsStillSkipped() throws {
    try store.savePartial(file(asks: [ask(100, 130)], covered: 0))
    XCTAssertNotNil(AdAsking.answer(store: store, detector: "local", askStart: 100, isAd: false))
    _ = try LocalAdsFile.saveFinal(
      [ad(100, 130)], store: store, detector: "local", detectorVersion: "1", osVersion: "26",
      duration: 600)
    let saved = try XCTUnwrap(store.load(detector: "local"))
    XCTAssertEqual(saved.ads, [ad(100, 130)])
    XCTAssertTrue(plays(saved, 100, 130))
  }

  // MARK: The file stays as it is

  func testWritingTheSameFileAgainGivesTheSameBytes() throws {
    try store.savePartial(file(asks: [ask(100, 130), ask(300, 330), ask(500, 530)], covered: 0))
    yes(100)
    XCTAssertNotNil(AdAsking.answer(store: store, detector: "local", askStart: 300, isAd: false))
    try store.save(file(ads: [ad(400, 450)], version: "1"))
    let url = store.url(detector: "local")
    let first = try Data(contentsOf: url)
    for _ in 0..<3 {
      try store.save(try XCTUnwrap(store.load(detector: "local")))
      XCTAssertEqual(try Data(contentsOf: url), first)
    }
    XCTAssertNotNil(store.loadPartial(detector: "local"), "the partial file is still there too")
    let loaded = try XCTUnwrap(store.load(detector: "local"))
    XCTAssertEqual(loaded.asks?.map(\.start), [100, 300, 500], "the order of the questions is stable")
  }

  func testTheListsAreWrittenOnlyWhenTheyHoldSomething() throws {
    try store.save(file(ads: [ad(30, 60)]))
    let text = String(decoding: try Data(contentsOf: store.url(detector: "local")), as: UTF8.self)
    XCTAssertFalse(text.contains("asks"))
    XCTAssertFalse(text.contains("denied"))
    XCTAssertFalse(text.contains("tap"))
  }

  // MARK: Damaged files

  func testAnAdWithNoLengthDoesNotMultiplyOnEveryWrite() throws {
    // A damaged file (JSON cannot hold a NaN, so the damage is a stretch that ends before it
    // starts) must not grow by what is carried from it.
    var bad = file(covered: 0)
    var flat = ad(100, 100)
    flat.source = "tap"
    bad.ads = [flat]
    bad.asks = [AdAsking.answered(ask(200, 200)), AdAsking.answered(ask(300, 290))]
    bad.undone = [UndoneAd(start: 7, end: 7), UndoneAd(start: 9, end: 3)]
    bad.denied = [UndoneAd(start: 5, end: 5), UndoneAd(start: 9, end: 3)]
    try store.savePartial(bad)
    var counts: [[Int]] = []
    for _ in 0..<6 {
      try store.savePartial(try XCTUnwrap(store.loadPartial(detector: "local")))
      let now = try XCTUnwrap(store.loadPartial(detector: "local"))
      counts.append([now.ads.count, now.asks?.count ?? 0, now.undone.count, now.denied?.count ?? 0])
    }
    XCTAssertEqual(Set(counts).count, 1, "the same every time: \(counts)")
    XCTAssertEqual(counts.last?.first, 1)
  }

  func testNothingThatIsNotARealStretchIsCarried() {
    let nan = Double.nan
    var earlier = file(covered: 0)
    earlier.asks = [AdAsking.answered(ask(nan, 130)), AdAsking.answered(ask(100, .infinity))]
    earlier.denied = [UndoneAd(start: nan, end: 5), UndoneAd(start: 5, end: 5)]
    earlier.undone = [UndoneAd(start: 1, end: nan)]
    let carried = AdAsking.carrying(earlier, into: file(ads: [ad(400, 450)]))
    XCTAssertEqual(carried.ads, [ad(400, 450)])
    XCTAssertNil(carried.asks)
    XCTAssertNil(carried.denied)
  }

  func testAHugeDeniedListIsCutToTheNewestFewWhenCarried() throws {
    var big = file(covered: 0)
    let once = (0..<20_000).map { UndoneAd(start: Double($0) * 10, end: Double($0) * 10 + 5) }
    big.denied = once + once  // every entry twice
    try store.savePartial(big)
    try checkpoint(ads: [], covered: 10)
    let after = try XCTUnwrap(store.loadPartial(detector: "local"))
    XCTAssertEqual(after.denied?.count, 4 * AdAsks.most)
    XCTAssertEqual(after.denied?.last, UndoneAd(start: 199_990, end: 199_995), "the newest stay")
    XCTAssertEqual(Set((after.denied ?? []).map(\.start)).count, 4 * AdAsks.most, "each once")
  }
}
