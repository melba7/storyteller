import XCTest

@testable import PodcastAds

/// The ahead finder's one look at an episode whose final ads file is made already: what it adds to
/// the file and what it leaves alone.
final class AheadPassTests: XCTestCase {
  private func found(
    _ start: Double, _ end: Double, kind: AdKind = .ad, confidence: AdConfidence = .sure,
    source: String? = "ahead"
  ) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: kind, advertiser: "", confidence: confidence,
      firstWords: "words", source: source)
  }

  private func file(
    _ ads: [FoundAd] = [], undone: [UndoneAd] = [], asks: [FoundAd]? = nil,
    denied: [UndoneAd]? = nil
  ) -> AdsFile {
    AdsFile(
      sha256: "abc", detector: "apple-on-device", detectorVersion: "3", osVersion: "26",
      duration: 1800, ads: ads, undone: undone, asks: asks, denied: denied)
  }

  private func merge(
    _ result: AheadFound, into saved: AdsFile, level: FinderMode = .skip,
    listener: AdSkipSettings = AdSkipSettings(), tuning: ShowTuning = ShowTuning()
  ) -> AheadPass.Made {
    AheadPass.merge(
      result, into: saved, show: "f", listener: listener, tuning: tuning, level: level)
  }

  private func tuning(_ json: String) -> ShowTuning {
    ShowTuning(data: Data(json.utf8))
  }

  // MARK: What is added

  func testTheFoundAdsJoinTheOnesTheFileHasAndKeepTheirName() {
    let old = found(100, 160, confidence: .sure, source: nil)
    let made = merge(AheadFound(ads: [found(600, 660)]), into: file([old]))
    XCTAssertEqual(made.file.ads.map(\.start), [100, 600])
    XCTAssertEqual(made.file.ads[0], old, "the old ad is as it was")
    XCTAssertEqual(made.file.ads[1].source, "ahead")
    XCTAssertEqual(made.skips, 1)
    XCTAssertEqual(made.questions, 0)
  }

  func testAnAdAFinderOfTheMacGivesIsAtMostUnsureSoTheListenerCanUndoIt() {
    let made = merge(AheadFound(ads: [found(600, 660, confidence: .sure)]), into: file())
    XCTAssertEqual(made.file.ads.map(\.confidence), [.unsure])
  }

  func testOnlyWhatLiesOutsideTheAdsOfTheFileIsAdded() {
    let old = found(100, 160, source: nil)
    // 90 to 130 lies over the old ad, 150 to 230 reaches past its end, 400 to 460 is apart.
    let made = merge(
      AheadFound(ads: [found(90, 130), found(150, 230), found(400, 460)]), into: file([old]))
    XCTAssertEqual(made.file.ads.first { $0.start == 100 }, old)
    XCTAssertFalse(made.file.ads.contains { $0.start < 160 && $0.end > 100 && $0 != old })
    XCTAssertTrue(made.file.ads.contains { $0.start == 400 && $0.end == 460 })
    XCTAssertTrue(
      made.file.ads.allSatisfy { $0 == old || $0.start >= 160 + AheadPass.apart - 0.001 || $0.end <= 100 })
  }

  func testAnAdAlreadyInTheFileIsNotAddedAgain() {
    let first = merge(AheadFound(ads: [found(600, 660)]), into: file())
    let again = merge(AheadFound(ads: [found(600, 660)]), into: first.file)
    XCTAssertEqual(again.file, first.file)
    XCTAssertEqual(again.skips, 0)
  }

  func testAFileThatNothingIsAddedToComesBackAsItWas() {
    let saved = file([found(100, 160, source: nil)])
    let made = merge(AheadFound(), into: saved)
    XCTAssertEqual(made.file, saved)
  }

  func testTheListenersUndoneSkipsStayAndNothingIsAddedOverThem() {
    let undone = UndoneAd(start: 600, end: 660)
    let saved = file([found(600, 660, source: nil)], undone: [undone])
    let made = merge(AheadFound(ads: [found(610, 650), found(900, 960)]), into: saved)
    XCTAssertEqual(made.file.undone, [undone])
    XCTAssertEqual(made.file.ads.map(\.start), [600, 900])
    XCTAssertEqual(made.file.ads[0], saved.ads[0])
  }

  func testAnUndoneStretchWithNoAdLeftInTheFileStillKeepsTheMarkOut() {
    let saved = file([], undone: [UndoneAd(start: 600, end: 660)])
    let made = merge(AheadFound(ads: [found(605, 655)]), into: saved)
    XCTAssertEqual(made.file.ads, [])
  }

  func testAStretchTheListenerSaidNoToIsNotAdded() {
    let saved = file([], denied: [UndoneAd(start: 600, end: 660)])
    let made = merge(
      AheadFound(ads: [found(610, 650)], asks: [found(620, 680, confidence: .unsure)]), into: saved)
    XCTAssertEqual(made.file.ads, [])
    XCTAssertNil(made.file.asks)
    XCTAssertEqual(made.file.denied, saved.denied)
  }

  // MARK: The switches and the settings

  func testASortTheListenerDoesNotSkipIsLeftOut() {
    let listener = AdSkipSettings(skipAds: false, skipOwnPlugs: true, skipPromos: true)
    let made = merge(
      AheadFound(ads: [found(600, 660, kind: .ad), found(900, 960, kind: .ownPlug)]), into: file(),
      listener: listener)
    XCTAssertEqual(made.file.ads.map(\.kind), [.ownPlug])
  }

  func testAFinderSetToOffAddsNothing() {
    let made = merge(
      AheadFound(ads: [found(600, 660)], asks: [found(900, 960, confidence: .unsure)]),
      into: file(), level: .off)
    XCTAssertEqual(made.file, file())
  }

  func testAFinderSetToAskOnlyAsks() {
    let made = merge(AheadFound(ads: [found(600, 660)]), into: file(), level: .ask)
    XCTAssertEqual(made.file.ads, [])
    XCTAssertEqual(made.file.asks?.map(\.start), [600])
    XCTAssertEqual(made.file.asks?.first?.confidence, .guess)
    XCTAssertEqual(made.skips, 0)
    XCTAssertEqual(made.questions, 1)
  }

  func testASortTheSettingsOnlyAsksAboutBecomesAQuestion() {
    let settings = tuning(
      #"{"version": 1, "shows": [{"feed": "f", "sorts": {"sponsor": "ask"}}]}"#)
    let made = merge(
      AheadFound(ads: [found(600, 660, kind: .ad), found(900, 960, kind: .promo)]), into: file(),
      tuning: settings)
    XCTAssertEqual(made.file.ads.map(\.kind), [.promo])
    XCTAssertEqual(made.file.asks?.map(\.start), [600])
  }

  func testTheFindersSettingForTheShowDecidesAsItDoesInTheOtherPasses() {
    let settings = tuning(
      #"{"version": 1, "shows": [{"feed": "f", "finders": {"ahead": "ask"}}]}"#)
    let made = merge(AheadFound(ads: [found(600, 660)]), into: file(), tuning: settings)
    XCTAssertEqual(made.file.ads, [])
    XCTAssertEqual(made.file.asks?.map(\.start), [600])
  }

  // MARK: Half matches

  func testAHalfMatchOnlyAsksWhateverTheLevelIs() {
    let made = merge(
      AheadFound(asks: [found(600, 660, confidence: .unsure)]), into: file(), level: .skip)
    XCTAssertEqual(made.file.ads, [])
    XCTAssertEqual(made.file.asks?.map(\.start), [600])
    XCTAssertEqual(made.questions, 1)
  }

  func testAQuestionIsNotAskedOverAnAdOfTheFileOrOneJustAdded() {
    let saved = file([found(100, 160, source: nil)])
    let made = merge(
      AheadFound(
        ads: [found(600, 660)],
        asks: [found(120, 150, confidence: .unsure), found(620, 650, confidence: .unsure)]),
      into: saved)
    XCTAssertNil(made.file.asks)
    XCTAssertEqual(made.file.ads.map(\.start), [100, 600])
  }

  func testTheFileNeverHoldsMoreThanThreeQuestionsInAll() {
    let saved = file(asks: [
      found(100, 160, confidence: .guess), found(300, 360, confidence: .guess),
    ])
    let made = merge(
      AheadFound(asks: [
        found(600, 660, confidence: .unsure), found(900, 960, confidence: .unsure),
      ]), into: saved)
    XCTAssertEqual(made.file.asks?.count, AdAsks.most)
    XCTAssertEqual(made.file.asks?.map(\.start), [100, 300, 600])
  }

  // MARK: The stretches the finder keeps out of

  func testTheJudgedStretchesAreTheListenersNoUndoneSkipsAndOpenQuestions() {
    let saved = file(
      [found(100, 160, source: nil)], undone: [UndoneAd(start: 200, end: 260)],
      asks: [found(300, 360, confidence: .guess)], denied: [UndoneAd(start: 400, end: 460)])
    let judged = AheadPass.judged(in: saved).map { [$0.start, $0.end] }
    XCTAssertEqual(Set(judged.map { $0[0] }), [200, 300, 400])
    XCTAssertEqual(judged.count, 3)
  }

  func testTheJudgedStretchesOfAFileWithNoAnswersAreNone() {
    XCTAssertTrue(AheadPass.judged(in: file([found(100, 160, source: nil)])).isEmpty)
  }
}
