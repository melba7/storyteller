import XCTest

@testable import PodcastAds

/// The maybes: making them from the word model, setting them in a file, reading and confirming.
final class AdMaybesTests: XCTestCase {
  private func maybe(_ start: Double, _ end: Double, kind: AdKind = .ad) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: kind, advertiser: "", confidence: .guess,
      firstWords: "w\(start)", source: "word-model")
  }

  private func ad(_ start: Double, _ end: Double) -> FoundAd {
    FoundAd(start: start, end: end, kind: .ad, advertiser: "Acme", confidence: .sure, firstWords: "")
  }

  private func file(
    ads: [FoundAd] = [], asks: [FoundAd]? = nil, maybes: [FoundAd]? = nil,
    undone: [UndoneAd] = [], denied: [UndoneAd]? = nil
  ) -> AdsFile {
    AdsFile(
      sha256: "aa", detector: "local", detectorVersion: "1", osVersion: "26", duration: 3000,
      ads: ads, undone: undone, asks: asks, denied: denied, maybes: maybes)
  }

  // MARK: From the word model

  /// "hi" lines are surely an ad, "mid" lines have a chance of about 0.555, "weak" lines about
  /// 0.40 (enough to open a maybe, not an ad), any other line about 0.03, and "pay" lines are
  /// credits.
  private func model(version: Int = 1) -> AdWordModel {
    func key(_ feature: String) -> String { String(AdWordModel.bucket(feature, buckets: 262144)) }
    let weights: [String: Any] = [
      key("#bias"): [5.0, 0.0, 0.0, 0.0, 0.0],
      key("u:hi"): [-7.0, 7.0, 0.0, 0.0, 0.0],
      key("u:mid"): [-2.5, 2.5, 0.0, 0.0, 0.0],
      key("u:weak"): [-2.9, 0.9, 0.0, 0.0, 0.0],
      key("u:promo"): [-7.0, 0.0, 7.0, 0.0, 0.0],
      key("u:credits"): [-7.0, 0.0, 0.0, 0.0, 7.0],
    ]
    let json: [String: Any] = [
      "version": version, "buckets": 262144, "classes": AdWordModel.classes, "weights": weights,
    ]
    return AdWordModel(data: try! JSONSerialization.data(withJSONObject: json))!
  }

  private func numbered(_ words: [String]) -> [NumberedLine] {
    words.enumerated().map {
      NumberedLine(
        number: $0.offset + 1, start: Double($0.offset) * 6, end: Double($0.offset) * 6 + 5,
        text: $0.element)
    }
  }

  private func plain(_ count: Int) -> [String] { Array(repeating: "plain", count: count) }

  func testAWeakStretchIsAMaybeAndTheStrongOneToo() {
    let lines = numbered(plain(6) + Array(repeating: "weak", count: 6) + plain(6))
    let found = AdMaybes.weak(
      model: model(), lines: lines, duration: 100, outside: [], source: "word-model")
    XCTAssertEqual(found.count, 1)
    let one = found[0]
    XCTAssertEqual(one.confidence, .guess)
    XCTAssertEqual(one.kind, .ad)
    XCTAssertEqual(one.source, "word-model")
    XCTAssertGreaterThanOrEqual(one.start, 30)
    XCTAssertLessThanOrEqual(one.start, 36)
    XCTAssertGreaterThanOrEqual(one.end, 65)
    XCTAssertLessThanOrEqual(one.end, 78)
    XCTAssertTrue(one.firstWords.hasPrefix("weak"), one.firstWords)
    // The model's own start threshold (0.6) finds nothing there.
    XCTAssertTrue(model().spans(lines: lines, duration: 100).isEmpty)
  }

  func testTheStrongStretchIsCutOutAndShortPartsAreDropped() {
    let lines = numbered(plain(4) + Array(repeating: "weak", count: 6) + plain(2) + Array(repeating: "hi", count: 6) + plain(4))
    let all = AdMaybes.weak(
      model: model(), lines: lines, duration: 100, outside: [], source: "s")
    XCTAssertEqual(all.count, 1, "the weak stretch runs into the strong one: they are joined")
    let strong = ad(72, 107)
    let cut = AdMaybes.weak(
      model: model(), lines: lines, duration: 100, outside: [strong], source: "s")
    XCTAssertEqual(cut.count, 1)
    XCTAssertLessThanOrEqual(cut[0].end, 72)
    XCTAssertGreaterThanOrEqual(cut[0].duration, AdMaybes.minLength)
    // Cut so that less than eight seconds is left: nothing.
    let nearly = AdMaybes.weak(
      model: model(), lines: lines, duration: 100, outside: [ad(0, 66)], source: "s")
    XCTAssertTrue(nearly.allSatisfy { $0.start >= 66 && $0.duration >= AdMaybes.minLength })
  }

  func testCreditsAreNeverAMaybeAndAPromoKeepsItsKind() {
    let lines = numbered(plain(4) + Array(repeating: "credits", count: 6) + plain(4) + Array(repeating: "promo", count: 6) + plain(4))
    let found = AdMaybes.weak(
      model: model(version: 2), lines: lines, duration: 100, outside: [], source: "s")
    XCTAssertEqual(found.map(\.kind), [.promo])
    let one = AdMaybes.weak(
      model: model(), lines: lines, duration: 100, outside: [], source: "s")
    XCTAssertFalse(one.contains { $0.kind == .credits })
  }

  func testAVersionTwoModelDecodesTheSameWay() {
    let lines = numbered(plain(6) + Array(repeating: "weak", count: 6) + plain(6))
    let found = AdMaybes.weak(
      model: model(version: 2), lines: lines, duration: 100, outside: [], source: "s")
    XCTAssertEqual(found.count, 1)
  }

  func testBadInputGivesNothing() {
    let none = AdMaybes.weak(model: model(), lines: [], duration: nil, outside: [], source: "s")
    XCTAssertTrue(none.isEmpty)
    var lines = numbered(plain(4) + Array(repeating: "weak", count: 6) + plain(4))
    lines[3].start = .nan
    XCTAssertTrue(
      AdMaybes.weak(model: model(), lines: lines, duration: 100, outside: [], source: "s").isEmpty)
    XCTAssertTrue(
      AdMaybes.weak(
        model: model(), lines: numbered(plain(3)), duration: .nan, outside: [ad(.nan, 3)], source: "s"
      ).isEmpty)
  }

  // MARK: Setting

  func testSettingStoresGuessesByStartAndNilWhenEmpty() {
    var sure = maybe(100, 130)
    sure.confidence = .sure
    let set = AdMaybes.setting([sure, maybe(10, 30)], in: file())
    XCTAssertEqual(set.maybes?.map(\.start), [10, 100])
    XCTAssertEqual(set.maybes?.map(\.confidence), [.guess, .guess])
    XCTAssertNil(AdMaybes.setting([], in: file(maybes: [maybe(10, 30)])).maybes)
  }

  func testSettingReplacesOpenMaybesAndKeepsConfirmedOnes() {
    var done = maybe(500, 540)
    done.confidence = .sure
    let before = file(maybes: [maybe(10, 30), done])
    let set = AdMaybes.setting([maybe(100, 130), maybe(510, 520)], in: before)
    XCTAssertEqual(set.maybes?.map(\.start), [100, 500], "the old open one goes; one over the confirmed is left out")
    XCTAssertEqual(set.maybes?.last?.confidence, .sure)
  }

  func testSettingTakesTheLongestWhenThereAreTooMany() {
    let many = (0..<30).map { maybe(Double($0) * 100, Double($0) * 100 + 10 + Double($0)) }
    let set = AdMaybes.setting(many, in: file())
    XCTAssertEqual(set.maybes?.count, AdMaybes.most)
    XCTAssertEqual(set.maybes?.first?.start, 1000, "the ten shortest are the ones left out")
    XCTAssertEqual(set.maybes?.map(\.start), set.maybes?.map(\.start).sorted())
  }

  func testSettingKeepsOverlappingMaybesApartAndRealOnesOnly() {
    let set = AdMaybes.setting(
      [maybe(100, 140), maybe(130, 150), maybe(200, 200), maybe(.nan, 5), maybe(300, 250)],
      in: file())
    XCTAssertEqual(set.maybes?.map(\.start), [100], "the longer of two that overlap; no bad stretch")
  }

  func testWhatCoversAMaybe() {
    let covering = file(
      ads: [ad(100, 130)], asks: [maybe(200, 230)], undone: [UndoneAd(start: 300, end: 330)],
      denied: [UndoneAd(start: 400, end: 430)])
    let set = AdMaybes.setting(
      [
        maybe(120, 150), maybe(190, 210), maybe(310, 320), maybe(395, 405), maybe(500, 530),
        maybe(60, 100),
      ], in: covering)
    XCTAssertEqual(set.maybes?.map(\.start), [60, 500], "an edge that only touches an ad is clear")
  }

  // MARK: Reading

  func testOpenAndLive() {
    var done = maybe(500, 540)
    done.confidence = .sure
    let held = file(
      ads: [ad(100, 130)], maybes: [maybe(110, 140), maybe(200, 240), maybe(700, 700), done])
    XCTAssertEqual(AdMaybes.open(in: held).map(\.start), [200])
    XCTAssertEqual(AdMaybes.live(in: held, at: 198)?.start, 200)
    XCTAssertEqual(AdMaybes.live(in: held, at: 239.9)?.start, 200)
    XCTAssertNil(AdMaybes.live(in: held, at: 197.9))
    XCTAssertNil(AdMaybes.live(in: held, at: 240))
    XCTAssertNil(AdMaybes.live(in: held, at: .nan))
    XCTAssertNil(AdMaybes.live(in: held, at: 510), "a confirmed maybe is not live")
  }

  // MARK: Confirming

  func testConfirmRecordsItAndMakesATapAd() throws {
    let before = file(ads: [ad(10, 40)], maybes: [maybe(200, 240)])
    let after = try XCTUnwrap(AdMaybes.confirm(before, maybeStart: 200.3))
    XCTAssertEqual(after.maybes?.first?.confidence, .sure)
    XCTAssertEqual(after.maybes?.first?.source, "word-model")
    XCTAssertEqual(after.ads.map(\.start), [10, 200])
    let tap = after.ads[1]
    XCTAssertEqual(tap.end, 240)
    XCTAssertEqual(tap.confidence, .sure)
    XCTAssertEqual(tap.source, AdAsking.source)
    XCTAssertNil(AdMaybes.confirm(after, maybeStart: 200), "twice does nothing")
    XCTAssertNil(AdMaybes.confirm(before, maybeStart: 201), "not the start the maybe has")
  }

  func testConfirmThroughTheStore() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = AdsStore(folder: folder, sha256: "aa")
    try store.savePartial(file(maybes: [maybe(200, 240)]))
    let got = AdMaybes.confirm(store: store, detector: "local", maybeStart: 200)
    XCTAssertEqual(got, maybe(200, 240))
    let saved = try XCTUnwrap(store.loadPartial(detector: "local"))
    XCTAssertEqual(saved.ads.map(\.source), [AdAsking.source])
    XCTAssertNil(AdMaybes.confirm(store: store, detector: "local", maybeStart: 200))
    XCTAssertNil(AdMaybes.confirm(store: store, detector: "other", maybeStart: 200))
  }

  // MARK: Files

  func testAFileSavedBeforeMaybesStillDecodes() throws {
    let old = file(ads: [ad(10, 40)])
    let data = try AdsStore.encoder.encode(old)
    let text = try XCTUnwrap(String(data: data, encoding: .utf8))
    XCTAssertFalse(text.contains("maybes"), "nil is not written")
    XCTAssertEqual(try JSONDecoder().decode(AdsFile.self, from: data).maybes, nil)
    let withKey = try AdsStore.encoder.encode(file(maybes: [maybe(1, 20)]))
    XCTAssertEqual(try JSONDecoder().decode(AdsFile.self, from: withKey).maybes, [maybe(1, 20)])
  }

  func testAConfirmedMaybeSurvivesAFreshFileWrittenThroughTheStore() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = AdsStore(folder: folder, sha256: "aa")
    try store.save(file(ads: [ad(10, 40)], maybes: [maybe(200, 240), maybe(300, 330)]))
    AdMaybes.confirm(store: store, detector: "local", maybeStart: 200)
    // The model's fresh result: its own ads, its own maybes, no memory of the tap.
    try store.save(file(ads: [ad(10, 40), ad(220, 260)], maybes: [maybe(400, 430)]))
    let saved = try XCTUnwrap(store.load(detector: "local"))
    XCTAssertEqual(saved.maybes?.map(\.start), [200, 400], "the confirmed stays, the old open one goes")
    XCTAssertEqual(saved.maybes?.first?.confidence, .sure)
    let tapped = saved.ads.filter { $0.source == AdAsking.source }
    XCTAssertEqual(tapped.map(\.start), [200])
    XCTAssertEqual(tapped.map(\.end), [220], "only the part no ad covers")
  }

  func testAnUndoneConfirmedMaybeIsNotRebuilt() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = AdsStore(folder: folder, sha256: "aa")
    try store.save(file(maybes: [maybe(200, 240)]))
    AdMaybes.confirm(store: store, detector: "local", maybeStart: 200)
    XCTAssertTrue(store.markUndone(detector: "local", adStart: 200))
    try store.save(file(ads: [ad(10, 40)]))
    let saved = try XCTUnwrap(store.load(detector: "local"))
    XCTAssertEqual(saved.ads.map(\.start), [10])
    XCTAssertTrue(AdMaybes.open(in: saved).isEmpty)
  }
}
