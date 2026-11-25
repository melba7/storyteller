import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// What the phone does with Apple's on-device model's ads on one show: the finder level (the
/// Mac's settings and the finder guard, the stricter wins) decides whether they skip, only ask or
/// are dropped, in the lists the ads files keep and in the questions.
final class AppleModelAdsTests: XCTestCase {
  private func ad(
    _ start: Double, kind: AdKind = .ad, _ confidence: AdConfidence = .sure, source: String? = nil
  ) -> FoundAd {
    FoundAd(
      start: start, end: start + 30, kind: kind, advertiser: "", confidence: confidence,
      firstWords: "", source: source)
  }

  /// A settings file for show "a" (feed "feed-a"): the default block and the show's own keys.
  private func tuning(default block: String = "{}", show keys: String = "") -> ShowTuning {
    let text = #"{"version": 1, "default": \#(block), "shows": [{"feed": "feed-a"\#(keys)}]}"#
    return ShowTuning(text: text, showOf: MacFiles.table([FeedKey.key("feed-a"): "a"]))
  }

  private var skipping: ShowTuning { tuning(show: #", "finders": {"apple-model": "skip"}"#) }

  // MARK: The name

  func testTheScorecardsAndThePhonesAdsCarryTheSameName() {
    XCTAssertEqual(AppleModelAds.source, "apple-model")
    XCTAssertEqual(AppleModelAds.source, ShowTuning.appleModel)
    var saved = AppleAnswers(model: "m 1")
    saved.episodes["e"] = .init(
      ads: [.init(start: 1, end: 31, kind: .ad, confidence: .sure)], refusedPieces: 0, seconds: 1)
    XCTAssertEqual(saved.ads(for: "e")?.first?.source, AppleModelAds.source)
    let placed = AppleModelAds.place([ad(1)], level: .skip, tuning: skipping, show: "a")
    XCTAssertEqual(placed.skip.first?.source, AppleModelAds.source)
  }

  // MARK: The level

  func testTheGuardAndTheSettingsAgreeOnTheStricter() {
    XCTAssertEqual(AppleModelAds.level(guarded: .skip, tuning: ShowTuning(), show: "a"), .ask)
    XCTAssertEqual(AppleModelAds.level(guarded: .skip, tuning: skipping, show: "a"), .skip)
    XCTAssertEqual(AppleModelAds.level(guarded: .ask, tuning: skipping, show: "a"), .ask)
    XCTAssertEqual(AppleModelAds.level(guarded: .off, tuning: skipping, show: "a"), .off)
    XCTAssertEqual(AppleModelAds.level(guarded: .skip, tuning: skipping, show: "b"), .ask)
    XCTAssertEqual(AppleModelAds.level(guarded: .skip, tuning: skipping, show: ""), .ask)
  }

  // MARK: Placing

  func testByDefaultEveryAnswerAsksAndNoneSkips() {
    let answers = [ad(0, .sure), ad(100, .unsure), ad(200, kind: .credits, .guess)]
    let placed = AppleModelAds.place(answers, level: .ask, tuning: ShowTuning(), show: "a")
    XCTAssertEqual(placed.skip, [])
    XCTAssertEqual(placed.ask.map(\.start), [0, 100, 200])
    XCTAssertTrue(placed.ask.allSatisfy { $0.source == "apple-model" })
    XCTAssertEqual(placed.ask.map(\.confidence), [.sure, .unsure, .guess], "kept as the model said it")
  }

  func testASkipLevelSkipsWhatTheSortsAllowAndAsksTheRest() {
    let set = tuning(
      show: #", "finders": {"apple-model": "skip"}, "sorts": {"intro_credits": "ask", "host_ask": "off"}"#)
    let answers = [ad(0), ad(100, kind: .credits), ad(200, kind: .ownPlug), ad(300, kind: .promo)]
    let placed = AppleModelAds.place(answers, level: .skip, tuning: set, show: "a")
    XCTAssertEqual(placed.skip.map(\.start), [0, 300])
    XCTAssertEqual(placed.ask.map(\.start), [100])
  }

  func testTheGuardCanHoldBackWhatTheSettingsLetSkip() {
    let answers = [ad(0), ad(100)]
    let asked = AppleModelAds.place(answers, level: .ask, tuning: skipping, show: "a")
    XCTAssertEqual(asked.skip, [])
    XCTAssertEqual(asked.ask.count, 2)
    let off = AppleModelAds.place(answers, level: .off, tuning: skipping, show: "a")
    XCTAssertEqual(off.skip, [])
    XCTAssertEqual(off.ask, [])
  }

  func testASortThatIsOffDropsAnAnswerEvenWhenTheFinderOnlyAsks() {
    let set = tuning(show: #", "sorts": {"sponsor": "off"}"#)
    let placed = AppleModelAds.place([ad(0), ad(100, kind: .promo)], level: .ask, tuning: set, show: "a")
    XCTAssertEqual(placed.ask.map(\.kind), [.promo])
  }

  // MARK: What a run keeps

  func testAPlacingKeepsTheSkipsAndRemembersTheQuestionsOfTheLastList() {
    let placing = ModelPlacing(level: .ask, tuning: ShowTuning(), show: "a")
    XCTAssertEqual(placing.keep([ad(0), ad(100)]), [])
    XCTAssertEqual(placing.asked.map(\.start), [0, 100])
    XCTAssertEqual(placing.keep([ad(100)]), [])
    XCTAssertEqual(placing.asked.map(\.start), [100], "the newest list replaces the older one")
    let free = ModelPlacing(level: .skip, tuning: skipping, show: "a")
    XCTAssertEqual(free.keep([ad(0)]).map(\.source), ["apple-model"])
    XCTAssertEqual(free.asked, [])
  }

  // MARK: Through the runner

  private let sha = "aa"
  private var folder: URL!

  override func setUpWithError() throws { folder = try temporaryFolder() }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  /// A model that says lines 40 to 47 are an ad, wherever it is asked about them.
  private let model = FakeDetector(tokenBudget: 160) { piece in
    let inside = piece.lines.map(\.number).filter { (40...47).contains($0) }
    guard let first = inside.first, let last = inside.last else { return [] }
    return [range(first, last)]
  }

  func testAFinderThatOnlyAsksLeavesNoModelAdInTheFilesAndHandsOverTheQuestions() async throws {
    let transcript = makeTranscript(talk(120, ad: 40...47))
    let store = AdsStore(folder: folder, sha256: sha)
    let placing = ModelPlacing(level: .ask, tuning: ShowTuning(), show: "a")
    guard
      case .finished(let file) = try await AdsRunner.run(
        transcript: transcript, detector: model, store: store, osVersion: "26.0", placing: placing)
    else { return XCTFail("did not finish") }
    XCTAssertEqual(file.ads, [])
    XCTAssertEqual(store.load(detector: "fake")?.ads, [])
    XCTAssertEqual(placing.asked.count, 1)
    XCTAssertEqual(placing.asked.first?.source, "apple-model")
    XCTAssertEqual(placing.asked.first?.start ?? 0, 390, accuracy: 10)
  }

  func testAFinderThatSkipsKeepsTheModelsAdWithItsNameAndAsksNothing() async throws {
    let transcript = makeTranscript(talk(120, ad: 40...47))
    let store = AdsStore(folder: folder, sha256: sha)
    let placing = ModelPlacing(level: .skip, tuning: skipping, show: "a")
    guard
      case .finished(let file) = try await AdsRunner.run(
        transcript: transcript, detector: model, store: store, osVersion: "26.0", placing: placing)
    else { return XCTFail("did not finish") }
    XCTAssertEqual(file.ads.count, 1)
    XCTAssertEqual(file.ads.first?.source, "apple-model")
    XCTAssertEqual(placing.asked, [])
  }

  func testWithNoPlacingTheRunnerIsAsItWas() async throws {
    let transcript = makeTranscript(talk(120, ad: 40...47))
    let store = AdsStore(folder: folder, sha256: sha)
    guard
      case .finished(let file) = try await AdsRunner.run(
        transcript: transcript, detector: model, store: store, osVersion: "26.0")
    else { return XCTFail("did not finish") }
    XCTAssertEqual(file.ads.count, 1)
    XCTAssertNil(file.ads.first?.source)
  }

  func testTheFilesSavedWhileARunGoesOnHoldNoSkipOfAFinderThatOnlyAsks() async throws {
    let transcript = makeTranscript(talk(120, ad: 40...47))
    let store = AdsStore(folder: folder, sha256: sha)
    let placing = ModelPlacing(level: .ask, tuning: ShowTuning(), show: "a")
    let seen = Seen()
    _ = try await AdsRunner.run(
      transcript: transcript, detector: model, store: store, osVersion: "26.0", placing: placing,
      progress: { done, _ in
        if done > 0 { seen.add(store.loadPartial(detector: "fake")?.ads.count ?? -1) }
      })
    XCTAssertFalse(seen.counts.isEmpty, "the run saved a partial file after a piece")
    XCTAssertEqual(Set(seen.counts), [0])
  }

  func testAPartialRunPlacesTheSameWay() async throws {
    let transcript = makeTranscript(talk(120, ad: 40...47))
    let partial = PartialTranscript(
      identity: transcript.identity, duration: transcript.duration, reached: transcript.duration,
      words: transcript.words)
    let asking = AdsStore(folder: folder, sha256: sha)
    _ = try await AdsRunner.runPartial(
      partial: partial, detector: model, store: asking, osVersion: "26.0",
      placing: ModelPlacing(level: .ask, tuning: ShowTuning(), show: "a"))
    XCTAssertEqual(asking.loadPartial(detector: "fake")?.ads, [])
    let other = AdsStore(folder: try temporaryFolder(), sha256: sha)
    _ = try await AdsRunner.runPartial(
      partial: partial, detector: model, store: other, osVersion: "26.0",
      placing: ModelPlacing(level: .skip, tuning: skipping, show: "a"))
    XCTAssertEqual(other.loadPartial(detector: "fake")?.ads.count, 1)
  }
}

/// What a callback saw, kept under a lock because the callbacks are `@Sendable`.
private final class Seen: @unchecked Sendable {
  private let lock = NSLock()
  private var seen: [Int] = []
  var counts: [Int] { lock.withLock { seen } }
  func add(_ count: Int) { lock.withLock { seen.append(count) } }
}
