import XCTest

@testable import PodcastAds

/// The ads file of a prepared copy: made from the Mac's marks at their own times, skipped by default
/// when Claude was sure and asked about when it was not.
final class PreparedAdsTests: XCTestCase {
  private let hash = String(repeating: "cd", count: 32)

  private func mark(
    _ start: Double, _ end: Double, _ confidence: AheadMark.Confidence = .high,
    kind: AdKind = .ad
  ) -> AheadMark {
    AheadMark(
      kind: kind, confidence: confidence, start: start, end: end,
      startWords: "alpha bravo charlie delta echo foxtrot golf hotel india juliet",
      endWords: "kilo lima mike november oscar papa quebec romeo sierra tango")
  }

  private func entry(_ marks: [AheadMark], copy: Bool = true) -> AheadEntry {
    AheadEntry(
      feed: "https://f.test/rss", guid: "g1", title: "One", marked: 0, ads: marks,
      copy: copy ? PreparedCopy(file: "prepared/0123456789ab.mp3", sha256: hash, bytes: 1000) : nil)
  }

  private func made(_ marks: [AheadMark], duration: Double = 1800) throws -> AdsFile {
    try XCTUnwrap(PreparedAds.file(for: entry(marks), duration: duration))
  }

  // MARK: The file

  func testTheFileIsTheCopysAndMarkedPrepared() throws {
    let file = try made([mark(100, 160)])
    XCTAssertEqual(file.sha256, hash)
    XCTAssertEqual(file.prepared, true)
    XCTAssertEqual(file.duration, 1800)
    XCTAssertEqual(file.version, AdsFile.currentVersion)
    XCTAssertEqual(file.detector, PreparedAds.detector)
    XCTAssertEqual(file.detectorVersion, PreparedAds.detectorVersion)
    XCTAssertTrue(file.undone.isEmpty)
    XCTAssertNil(file.coveredUntil, "it is a final file")
  }

  func testNoCopyOrNoLengthGivesNoFile() {
    XCTAssertNil(PreparedAds.file(for: entry([mark(100, 160)], copy: false), duration: 1800))
    XCTAssertNil(PreparedAds.file(for: entry([mark(100, 160)]), duration: 0))
    XCTAssertNil(PreparedAds.file(for: entry([mark(100, 160)]), duration: .nan))
    XCTAssertNil(PreparedAds.file(for: entry([mark(100, 160)]), duration: -5))
  }

  func testTheDetectorCanBeNamedByTheCaller() throws {
    let file = try XCTUnwrap(
      PreparedAds.file(for: entry([]), duration: 600, detector: "apple-on-device"))
    XCTAssertEqual(file.detector, "apple-on-device")
  }

  func testAnEntryWithACopyAndNoAdsGivesAFileWithNone() throws {
    let file = try made([])
    XCTAssertEqual(file.ads, [])
    XCTAssertNil(file.asks)
    XCTAssertEqual(AdsRules.status(file: file, detectorVersion: "x", finding: nil, unavailable: nil, failure: nil), .noneFound)
  }

  // MARK: The ads

  func testHighAndMediumMarksAreAdsAtTheirOwnTimesNamedPrepared() throws {
    let file = try made([mark(100, 160), mark(400, 450.5, .medium, kind: .promo)])
    XCTAssertEqual(file.ads.map(\.start), [100, 400])
    XCTAssertEqual(file.ads.map(\.end), [160, 450.5])
    XCTAssertEqual(file.ads.map(\.kind), [.ad, .promo])
    XCTAssertEqual(file.ads.map(\.source), ["prepared", "prepared"])
    XCTAssertTrue(file.ads.allSatisfy { $0.confidence == .unsure })
    XCTAssertEqual(file.ads[0].firstWords, "alpha bravo charlie delta echo foxtrot golf hotel india juliet")
  }

  func testALowMarkIsAQuestionAndNeverAnAd() throws {
    let file = try made([mark(100, 160), mark(500, 540, .low)])
    XCTAssertEqual(file.ads.map(\.start), [100])
    let asks = try XCTUnwrap(file.asks)
    XCTAssertEqual(asks.map(\.start), [500])
    XCTAssertEqual(asks.map(\.end), [540])
    XCTAssertEqual(asks.first?.confidence, .guess)
    XCTAssertEqual(asks.first?.source, "prepared")
  }

  func testALowMarkOverAnAdIsNotAsked() throws {
    let file = try made([mark(100, 160), mark(120, 150, .low)])
    XCTAssertNil(file.asks)
  }

  func testNoMoreQuestionsThanAnEpisodeMayHave() throws {
    let file = try made((0..<6).map { mark(Double($0) * 100, Double($0) * 100 + 40, .low) })
    XCTAssertEqual(file.asks?.count, AdAsks.most)
  }

  func testMarksAreCutToTheLengthAndEmptyOnesAreDropped() throws {
    let file = try made(
      [mark(1700, 1900), mark(1900, 1950), mark(-20, 30), mark(500, 500), mark(600, 590),
       mark(.nan, 800), mark(900, .infinity)], duration: 1800)
    XCTAssertEqual(file.ads.map { [$0.start, $0.end] }, [[0, 30], [1700, 1800]])
  }

  func testMarksAreInOrderOfTime() throws {
    let file = try made([mark(900, 960), mark(100, 160), mark(500, 560), mark(300, 330, .low)])
    XCTAssertEqual(file.ads.map(\.start), [100, 500, 900])
  }

  func testMarksThatOverlapBecomeOneAdAndNeverTwoThatOverlap() throws {
    let file = try made([mark(100, 160), mark(150, 220), mark(220, 250), mark(400, 460)])
    XCTAssertEqual(file.ads.map { [$0.start, $0.end] }, [[100, 250], [400, 460]])
    XCTAssertEqual(file.ads.first?.source, "prepared")
    let other = try made([mark(100, 200), mark(150, 260, kind: .ownPlug)])
    let spans = other.ads.sorted { $0.start < $1.start }
    for (one, next) in zip(spans, spans.dropFirst()) { XCTAssertLessThanOrEqual(one.end, next.start) }
  }

  func testThePlayerSkipsAPreparedAdAndAskedStretchesAreLeftAlone() throws {
    let file = try made([mark(100, 160), mark(500, 540, .low)])
    var skipper = AdSkipper(file: file, settings: AdSkipSettings())
    let skip = skipper.reached(position: 100.2, rate: 1, duration: 1800, now: 0)
    XCTAssertNotNil(skip)
    XCTAssertGreaterThanOrEqual(skip?.target ?? 0, 160)
    XCTAssertNil(skipper.reached(position: 500.2, rate: 1, duration: 1800, now: 100))
  }

  // MARK: The status

  func testAPreparedFileIsFinishedWhateverTheDetectorVersion() throws {
    let file = try made([mark(100, 160), mark(300, 360)])
    for version in ["1", "", "9", PreparedAds.detectorVersion] {
      XCTAssertEqual(
        AdsRules.status(
          file: file, detectorVersion: version, finding: nil, unavailable: nil, failure: nil),
        .found(count: 2), version)
    }
    XCTAssertEqual(
      AdsRules.status(
        file: file, detectorVersion: "2", finding: nil, unavailable: .appleIntelligenceOff,
        failure: "boom"),
      .found(count: 2))
    XCTAssertFalse(AdsRules.wantsRun(AdsRules.status(file: file, detectorVersion: "2", finding: nil, unavailable: nil, failure: nil)))
  }

  func testAFileThatIsNotPreparedStillFollowsTheVersion() throws {
    var file = try made([mark(100, 160)])
    file.prepared = nil
    XCTAssertEqual(
      AdsRules.status(file: file, detectorVersion: "2", finding: nil, unavailable: nil, failure: nil),
      .waiting)
  }

  // MARK: The names

  func testPreparedIsNotAFinderTheSettingsOrTheGuardKnow() {
    XCTAssertEqual(PreparedAds.source, "prepared")
    XCTAssertFalse(ShowTuning.finderNames.contains(PreparedAds.source))
    let tuning = ShowTuning(
      data: Data(#"{"version": 1, "default": {"finders": {"prepared": "off"}}}"#.utf8))
    XCTAssertEqual(tuning.level(forFinder: "prepared", show: "s"), .skip, "the file cannot set it")
    let ad = FoundAd(
      start: 1, end: 40, kind: .ad, advertiser: "", confidence: .unsure, firstWords: "x",
      source: PreparedAds.source)
    XCTAssertEqual(tuning.apply(to: [ad], show: "s").skip, [ad], "finder levels do not touch it")
  }

  func testTheGuardKeepsNoAnswersAboutPrepared() {
    var guardian = FinderGuard(appBuild: "1")
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    for _ in 0..<5 { guardian.undone(finder: PreparedAds.source, show: "s", now: now) }
    guardian.denied(finder: PreparedAds.source, show: "s", now: now)
    XCTAssertEqual(guardian, FinderGuard(appBuild: "1"))
    XCTAssertEqual(guardian.mode(finder: PreparedAds.source, show: "s", episode: "e", now: now), .skip)
    // Eight real finders on one show are still all kept.
    for name in (0..<FinderGuard.maxFindersPerShow).map({ "finder-\($0)" }) {
      guardian.undone(finder: name, show: "s", now: now)
    }
    guardian.undone(finder: PreparedAds.source, show: "s", now: now)
    XCTAssertEqual(guardian.shows.first?.finders.count, FinderGuard.maxFindersPerShow)
    XCTAssertFalse(guardian.shows.first?.finders.contains { $0.finder == "prepared" } ?? true)
  }

  // MARK: What the listener does

  func testTheUndoOfAPreparedAdSavesItAsUndoneAndBlamesNoFinder() throws {
    let file = try made([mark(100, 160), mark(400, 460)])
    let store = AdsStore(folder: try temporaryFolder(), sha256: hash)
    try store.save(file)
    var skipper = AdSkipper(file: file, settings: AdSkipSettings())
    let skip = try XCTUnwrap(skipper.reached(position: 100.2, rate: 1, duration: 1800, now: 0))
    let back = try XCTUnwrap(skipper.undoSkip(now: 1))
    XCTAssertEqual(back.takenBack, [skip.ad], "the Undo takes back the ad itself")
    XCTAssertEqual(back.takenBack.first?.source, PreparedAds.source)
    XCTAssertTrue(store.markUndone(detector: file.detector, adStart: skip.ad.start))
    let saved = try XCTUnwrap(store.load(detector: file.detector))
    XCTAssertEqual(saved.undone, [UndoneAd(start: 100, end: 160)])
    XCTAssertEqual(saved.prepared, true, "it is still the prepared file")
    // No finder is blamed: the name is not one the guard or the settings can hold back.
    XCTAssertFalse(ShowTuning.finderNames.contains(try XCTUnwrap(back.takenBack.first?.source)))
  }

  func testATrimAndANoStillWriteToAPreparedFile() throws {
    let file = try made([mark(100, 160), mark(500, 540, .low)])
    let store = AdsStore(folder: try temporaryFolder(), sha256: hash)
    try store.save(file)
    XCTAssertTrue(store.markTrimmed(detector: file.detector, AdTrim(adStart: 100, end: 120)))
    XCTAssertEqual(store.load(detector: file.detector)?.ads.first?.trimmed(by: store.load(detector: file.detector)?.trims ?? []).end, 120)
    let answered = try XCTUnwrap(AdAsking.answer(try XCTUnwrap(store.load(detector: file.detector)), askStart: 500, isAd: false))
    XCTAssertEqual(answered.denied?.count, 1)
    XCTAssertEqual(answered.prepared, true)
  }
}
