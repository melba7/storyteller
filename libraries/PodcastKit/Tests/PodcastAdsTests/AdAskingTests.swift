import XCTest

@testable import PodcastAds

/// `AdAsking` keeps the questions in an ads file: which one is live at the playhead, what an
/// answer does to the file, and which questions may be added.
final class AdAskingTests: XCTestCase {
  // MARK: Helpers

  /// An ads file as a build from before questions wrote it.
  private let oldFile = #"""
    {"ads":[{"advertiser":"Acme","confidence":"sure","end":60,"firstWords":"brought to you","kind":"ad","start":30}],"detector":"local","detectorVersion":"1","duration":3600,"osVersion":"26","sha256":"abc","undone":[],"version":1}
    """#

  private func ask(_ start: Double, _ end: Double, kind: AdKind = .promo) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: kind, advertiser: "", confidence: .guess,
      firstWords: "words at \(start)", source: "word-model")
  }

  private func ad(_ start: Double, _ end: Double, _ confidence: AdConfidence = .sure) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "Acme", confidence: confidence,
      firstWords: "brought to you")
  }

  private func file(
    ads: [FoundAd] = [], asks: [FoundAd]? = nil, undone: [UndoneAd] = [], denied: [UndoneAd]? = nil,
    coveredUntil: Double? = nil
  ) -> AdsFile {
    AdsFile(
      sha256: "abc", detector: "local", detectorVersion: "1", osVersion: "26", duration: 3600,
      ads: ads, undone: undone, coveredUntil: coveredUntil, asks: asks, denied: denied)
  }

  private func tempFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
    return folder
  }

  // MARK: Old files

  func testAnOldFileWithNoAsksReadsAndHasNoQuestion() throws {
    let old = try JSONDecoder().decode(AdsFile.self, from: Data(oldFile.utf8))
    XCTAssertNil(old.asks)
    XCTAssertNil(old.denied)
    XCTAssertEqual(AdAsking.open(in: old), [])
    XCTAssertNil(AdAsking.live(in: old, at: 40))
    XCTAssertNil(AdAsking.answer(old, askStart: 100, isAd: true))
    // A question can be added to it, and the file then reads back with it.
    let with = AdAsking.adding([ask(100, 130)], to: old)
    XCTAssertEqual(with.asks, [ask(100, 130)])
    XCTAssertEqual(with.ads, old.ads)
    let written = try AdsStore.encoder.encode(with)
    XCTAssertFalse(String(decoding: written, as: UTF8.self).contains("denied"), "none, so no key")
    XCTAssertEqual(try JSONDecoder().decode(AdsFile.self, from: written), with)
  }

  // MARK: Which question is live

  func testAQuestionIsLiveFromItsStartUpToItsEnd() {
    let f = file(asks: [ask(100, 130)])
    XCTAssertNil(AdAsking.live(in: f, at: 99.9))
    XCTAssertEqual(AdAsking.live(in: f, at: 100), ask(100, 130))
    XCTAssertEqual(AdAsking.live(in: f, at: 115), ask(100, 130))
    XCTAssertNil(AdAsking.live(in: f, at: 130), "the end is outside")
    XCTAssertNil(AdAsking.live(in: f, at: .nan))
  }

  func testOnlyTheQuestionAroundThePlayheadIsLive() {
    let f = file(asks: [ask(300, 330), ask(100, 130)])
    XCTAssertEqual(AdAsking.live(in: f, at: 310)?.start, 300)
    XCTAssertEqual(AdAsking.live(in: f, at: 110)?.start, 100)
    XCTAssertEqual(AdAsking.open(in: f).map(\.start), [100, 300], "open ones come by start")
  }

  func testAQuestionOverAFoundAdIsNotLive() {
    let f = file(ads: [ad(110, 160)], asks: [ask(100, 130)])
    XCTAssertEqual(AdAsking.open(in: f), [])
    XCTAssertNil(AdAsking.live(in: f, at: 105))
  }

  func testAQuestionOverAnUndoneStretchIsNotLive() {
    let f = file(asks: [ask(100, 130)], undone: [UndoneAd(start: 95, end: 125)])
    XCTAssertNil(AdAsking.live(in: f, at: 105))
  }

  func testAQuestionTheListenerSaidNoToIsNotLive() {
    let f = file(asks: [ask(100, 130)], denied: [UndoneAd(start: 100, end: 130)])
    XCTAssertEqual(AdAsking.open(in: f), [])
    XCTAssertNil(AdAsking.live(in: f, at: 105))
  }

  func testAQuestionWithBadTimesIsNeverLive() {
    let f = file(asks: [ask(.nan, 130), ask(200, .infinity), ask(300, 290), ask(400, 400)])
    XCTAssertEqual(AdAsking.open(in: f), [])
  }

  // MARK: Yes

  func testYesMovesTheAskIntoTheAdsAsASureAdFromTap() throws {
    let before = file(ads: [ad(30, 60), ad(500, 540)], asks: [ask(100, 130), ask(300, 330)])
    let after = try XCTUnwrap(AdAsking.answer(before, askStart: 100, isAd: true))
    XCTAssertEqual(after.ads.map(\.start), [30, 100, 500], "in order of start")
    let tapped = after.ads[1]
    XCTAssertEqual(tapped.confidence, .sure)
    XCTAssertEqual(tapped.source, "tap")
    XCTAssertEqual(AdAsking.source, "tap")
    XCTAssertEqual(tapped.end, 130)
    XCTAssertEqual(tapped.kind, .promo, "the question's kind stays")
    XCTAssertEqual(tapped.firstWords, "words at 100.0")
    XCTAssertEqual(after.asks, before.asks, "the list keeps every question, answered or not")
    XCTAssertEqual(AdAsking.open(in: after).map(\.start), [300], "the other question waits")
    XCTAssertEqual(after.undone, [])
    XCTAssertNil(after.denied)
    XCTAssertEqual(after.ads[0], before.ads[0])
    XCTAssertEqual(after.ads[2], before.ads[1])
  }

  func testAnAnsweredQuestionStaysInTheListButIsNotOpen() throws {
    // It stays so that the cap of three questions an episode counts it.
    let after = try XCTUnwrap(AdAsking.answer(file(asks: [ask(100, 130)]), askStart: 100, isAd: true))
    XCTAssertEqual(after.asks, [ask(100, 130)])
    XCTAssertEqual(AdAsking.open(in: after), [])
  }

  // MARK: No

  func testNoMovesTheAskToDeniedAndNeverToUndone() throws {
    let before = file(ads: [ad(30, 60)], asks: [ask(100, 130), ask(300, 330)])
    let after = try XCTUnwrap(AdAsking.answer(before, askStart: 300, isAd: false))
    XCTAssertEqual(after.denied, [UndoneAd(start: 300, end: 330)])
    XCTAssertEqual(after.undone, [], "a skip the listener took back is another thing")
    XCTAssertEqual(after.ads, before.ads, "no ad is added")
    XCTAssertEqual(after.asks, before.asks)
    XCTAssertEqual(AdAsking.open(in: after).map(\.start), [100])
    let again = try XCTUnwrap(AdAsking.answer(after, askStart: 100, isAd: false))
    XCTAssertEqual(again.denied, [UndoneAd(start: 300, end: 330), UndoneAd(start: 100, end: 130)])
  }

  func testNoIsKeptByTheModelsRunThatReplacesALocalFinalFile() throws {
    // The local final file stays on disk until the model's own final file replaces it, and
    // every write of the model's partial files carries what it holds: the question and the no.
    let store = AdsStore(folder: try tempFolder(), sha256: "abc")
    var local = file(asks: [ask(100, 130)])
    local.detectorVersion = LocalAdsFile.localVersion
    try store.save(local)
    XCTAssertNotNil(AdAsking.answer(store: store, detector: "local", askStart: 100, isAd: false))
    try store.savePartial(file(coveredUntil: 100))
    XCTAssertEqual(store.loadPartial(detector: "local")?.denied, [UndoneAd(start: 100, end: 130)])
    XCTAssertEqual(store.loadPartial(detector: "local")?.asks, [ask(100, 130)])
    XCTAssertEqual(store.loadPartial(detector: "local")?.undone, [])
  }

  // MARK: An answered ask is never live again

  func testAnAnsweredAskIsNeverLiveAgain() throws {
    for isAd in [true, false] {
      let answered = try XCTUnwrap(
        AdAsking.answer(file(asks: [ask(100, 130)]), askStart: 100, isAd: isAd))
      XCTAssertNil(AdAsking.live(in: answered, at: 110), "answered with isAd \(isAd)")
      XCTAssertEqual(AdAsking.open(in: answered), [])
      // A finder that asks about the same stretch again changes nothing: it is an ad now, or
      // it is undone.
      let asked = AdAsking.adding([ask(100, 130), ask(105, 128)], to: answered)
      XCTAssertEqual(asked, answered)
      XCTAssertNil(AdAsking.live(in: asked, at: 110))
    }
  }

  func testAnAskCannotBeAnsweredTwice() throws {
    let once = try XCTUnwrap(
      AdAsking.answer(file(asks: [ask(100, 130)]), askStart: 100, isAd: true))
    XCTAssertNil(AdAsking.answer(once, askStart: 100, isAd: true))
    XCTAssertNil(AdAsking.answer(once, askStart: 100, isAd: false))
    XCTAssertEqual(once.ads.count, 1, "it was not added twice")
  }

  func testAnAnswerNeedsAnOpenQuestionAtThatStart() {
    let f = file(asks: [ask(100, 130)])
    XCTAssertNil(AdAsking.answer(f, askStart: 200, isAd: true))
    XCTAssertNil(AdAsking.answer(f, askStart: .nan, isAd: true))
    XCTAssertNil(AdAsking.answer(file(), askStart: 100, isAd: false))
    let over = file(ads: [ad(110, 160)], asks: [ask(100, 130)])
    XCTAssertNil(AdAsking.answer(over, askStart: 100, isAd: true), "an ad is there already")
  }

  func testTheStartMayDifferByLessThanHalfASecond() throws {
    let f = file(asks: [ask(100, 130), ask(131, 160)])
    let after = try XCTUnwrap(AdAsking.answer(f, askStart: 100.3, isAd: false))
    XCTAssertEqual(after.denied, [UndoneAd(start: 100, end: 130)])
    let next = try XCTUnwrap(AdAsking.answer(f, askStart: 130.8, isAd: false))
    XCTAssertEqual(next.denied, [UndoneAd(start: 131, end: 160)], "the question that starts there")
    XCTAssertNil(AdAsking.answer(f, askStart: 100.6, isAd: false))
  }

  // MARK: Overlapping an ad

  func testAnAskThatOverlapsAFoundAdIsDroppedWhenAdded() {
    let f = file(ads: [ad(100, 160)])
    XCTAssertNil(AdAsking.adding([ask(90, 110)], to: f).asks, "over the start")
    XCTAssertNil(AdAsking.adding([ask(150, 200)], to: f).asks, "over the end")
    XCTAssertNil(AdAsking.adding([ask(110, 130)], to: f).asks, "inside")
    XCTAssertNil(AdAsking.adding([ask(50, 300)], to: f).asks, "around")
    XCTAssertEqual(AdAsking.adding([ask(160, 190), ask(70, 100)], to: f).asks?.map(\.start), [70, 160], "touching only")
  }

  func testAnUnsureAdAlsoDropsTheQuestionOverIt() {
    XCTAssertNil(AdAsking.adding([ask(100, 130)], to: file(ads: [ad(100, 130, .unsure)])).asks)
  }

  func testAnAskOverAnUndoneStretchOrAnotherAskIsDropped() {
    let f = file(asks: [ask(300, 330)], undone: [UndoneAd(start: 100, end: 130)])
    XCTAssertEqual(AdAsking.adding([ask(110, 140), ask(310, 340)], to: f), f)
  }

  func testAnAskWithBadTimesIsNotAdded() {
    XCTAssertEqual(AdAsking.adding([ask(.nan, 130), ask(200, 150), ask(300, .infinity)], to: file()), file())
  }

  // MARK: At most three

  func testNoMoreThanThreeQuestionsAreKept() {
    let five = [ask(100, 130), ask(200, 230), ask(300, 330), ask(400, 430), ask(500, 530)]
    let f = AdAsking.adding(five, to: file())
    XCTAssertEqual(f.asks?.map(\.start), [100, 200, 300], "the first three given: the most likely")
    XCTAssertEqual(AdAsks.most, 3)
  }

  func testRoomIsWhatTheStoredQuestionsLeave() {
    let f = AdAsking.adding([ask(400, 430), ask(500, 530)], to: file(asks: [ask(300, 330), ask(100, 130)]))
    XCTAssertEqual(f.asks?.map(\.start), [100, 300, 400], "stored by start")
    XCTAssertEqual(AdAsking.adding([ask(900, 930)], to: f), f, "three are stored already")
  }

  func testAnAnsweredQuestionKeepsItsPlaceInTheCapOfThree() throws {
    let full = AdAsking.adding(
      [ask(100, 130), ask(200, 230), ask(300, 330)], to: file())
    for isAd in [true, false] {
      let answered = try XCTUnwrap(AdAsking.answer(full, askStart: 100, isAd: isAd))
      XCTAssertEqual(AdAsking.adding([ask(400, 430)], to: answered), answered, "isAd \(isAd)")
    }
  }

  func testAddingKeepsEverythingElseInTheFile() {
    let f = file(ads: [ad(30, 60)], undone: [UndoneAd(start: 1000, end: 1040)], coveredUntil: 900)
    var expected = f
    expected.asks = [ask(100, 130)]
    XCTAssertEqual(AdAsking.adding([ask(100, 130)], to: f), expected)
  }

  func testAddingMakesEveryQuestionAGuess() {
    var loud = ask(100, 130)
    loud.confidence = .sure
    XCTAssertEqual(AdAsking.adding([loud], to: file()).asks?.first?.confidence, .guess)
  }

  // MARK: Through the store

  func testAnAnswerIsSavedInTheFinalFile() throws {
    let store = AdsStore(folder: try tempFolder(), sha256: "abc")
    try store.save(file(ads: [ad(30, 60)], asks: [ask(100, 130)]))
    let answered = AdAsking.answer(store: store, detector: "local", askStart: 100, isAd: true)
    XCTAssertEqual(answered, ask(100, 130), "the question that was answered")
    let saved = try XCTUnwrap(store.load(detector: "local"))
    XCTAssertEqual(saved.ads.map(\.start), [30, 100])
    XCTAssertEqual(saved.ads[1].source, "tap")
    XCTAssertEqual(saved.asks, [ask(100, 130)], "kept, and no longer open")
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
