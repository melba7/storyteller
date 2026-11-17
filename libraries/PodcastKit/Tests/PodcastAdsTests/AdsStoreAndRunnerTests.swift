import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

final class AdsStoreTests: XCTestCase {
  private var folder: URL!
  private let sha = String(repeating: "ab", count: 32)

  override func setUpWithError() throws { folder = try temporaryFolder() }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  private func file(sha: String? = nil) -> AdsFile {
    AdsFile(
      sha256: sha ?? self.sha, detector: "fake", detectorVersion: "1", osVersion: "26.0",
      duration: 600,
      ads: [
        FoundAd(
          start: 20, end: 60, kind: .ad, advertiser: "Acme", confidence: .sure, firstWords: "hello")
      ])
  }

  func testSavesAsShaAdsDetectorJson() throws {
    let store = AdsStore(folder: folder, sha256: sha)
    try store.save(file())
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(sha).ads.fake.json").path))
    XCTAssertEqual(store.load(detector: "fake"), file())
  }

  func testEachDetectorHasItsOwnFile() throws {
    let store = AdsStore(folder: folder, sha256: sha)
    try store.save(file())
    XCTAssertNil(store.load(detector: "other"))
  }

  func testLoadsOnlyForTheSameFile() throws {
    let store = AdsStore(folder: folder, sha256: sha)
    try store.save(file())
    let otherSha = String(repeating: "cd", count: 32)
    let other = AdsStore(folder: folder, sha256: otherSha)
    XCTAssertNil(other.load(detector: "fake"), "no file for another hash")
    // A file that was copied under another hash's name still holds the first hash.
    try FileManager.default.copyItem(at: store.url(detector: "fake"), to: other.url(detector: "fake"))
    XCTAssertNil(other.load(detector: "fake"))
  }

  func testAFileThatCannotBeReadCountsAsNone() throws {
    let store = AdsStore(folder: folder, sha256: sha)
    try Data("not json".utf8).write(to: store.url(detector: "fake"))
    XCTAssertNil(store.load(detector: "fake"))
  }

  func testADetectorNameCannotLeaveTheFolder() {
    let store = AdsStore(folder: folder, sha256: sha)
    XCTAssertEqual(store.url(detector: "../../x/y").deletingLastPathComponent().standardizedFileURL.path,
      folder.standardizedFileURL.path)
  }

  func testUndoIsRecordedOnceAndOnlyForARealAd() throws {
    let store = AdsStore(folder: folder, sha256: sha)
    try store.save(file())
    XCTAssertFalse(store.markUndone(detector: "fake", adStart: 300))
    XCTAssertTrue(store.markUndone(detector: "fake", adStart: 20))
    XCTAssertTrue(store.markUndone(detector: "fake", adStart: 20.2))
    let loaded = try XCTUnwrap(store.load(detector: "fake"))
    XCTAssertEqual(loaded.undone, [UndoneAd(start: 20, end: 60)])
    XCTAssertTrue(loaded.isUndone(loaded.ads[0]))
  }

  func testNothingToUndoWithoutAFile() {
    XCTAssertFalse(AdsStore(folder: folder, sha256: sha).markUndone(detector: "fake", adStart: 1))
  }
}

final class AdsRunnerTests: XCTestCase {
  private var folder: URL!
  private let sha = "aa"

  override func setUpWithError() throws { folder = try temporaryFolder() }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  /// Says the lines of `ad` that are in the piece are an ad.
  private func detector(ad: ClosedRange<Int>, budget: Int = 150) -> FakeDetector {
    FakeDetector(tokenBudget: budget) { piece in
      let inside = piece.lines.map(\.number).filter { ad.contains($0) }
      guard let first = inside.first, let last = inside.last else { return [] }
      return [range(first, last)]
    }
  }

  func testAnAdAcrossACutIsFoundOnce() async throws {
    let transcript = makeTranscript(talk(120, ad: 40...47))
    let store = AdsStore(folder: folder, sha256: sha)
    let ad = detector(ad: 40...47, budget: 160)
    let pieces = AdChunker.pieces(of: AdChunker.number(transcript.lines), tokenBudget: 160)
    XCTAssertGreaterThan(pieces.filter { $0.lines.contains { (40...47).contains($0.number) } }.count, 1,
      "the ad is seen by more than one piece")
    guard case .finished(let file) = try await AdsRunner.run(
      transcript: transcript, detector: ad, store: store, osVersion: "26.0")
    else { return XCTFail("did not finish") }
    XCTAssertEqual(file.ads.count, 1)
    XCTAssertEqual(file.ads[0].start, 389.5, accuracy: 0.01)
    XCTAssertEqual(file.ads[0].end, 469.5, accuracy: 0.01)
    XCTAssertEqual(store.load(detector: "fake"), file)
    XCTAssertEqual(file.detector, "fake")
    XCTAssertEqual(file.osVersion, "26.0")
  }

  func testNoAdsIsASavedResult() async throws {
    let store = AdsStore(folder: folder, sha256: sha)
    let none = FakeDetector { _ in [] }
    guard case .finished(let file) = try await AdsRunner.run(
      transcript: makeTranscript(talk(20)), detector: none, store: store, osVersion: "26.0")
    else { return XCTFail("did not finish") }
    XCTAssertTrue(file.ads.isEmpty)
    XCTAssertNotNil(store.load(detector: "fake"), "so the episode counts as checked")
  }

  func testAPieceThatIsTooLongIsSplitInTwo() async throws {
    let seen = Counter()
    let picky = FakeDetector(tokenBudget: 400) { piece in
      seen.add(piece.lines.count)
      if piece.lines.count > 12 { throw AdDetectorError.tooLong }
      return []
    }
    let outcome = try await AdsRunner.run(
      transcript: makeTranscript(talk(40)), detector: picky,
      store: AdsStore(folder: folder, sha256: sha), osVersion: "26.0")
    guard case .finished = outcome else { return XCTFail("did not finish") }
    // 40 lines are too long, so two of 20; those are too long, so four of 10.
    XCTAssertEqual(seen.sizes.first, 40)
    XCTAssertEqual(seen.sizes.filter { $0 <= 12 }.count, 4, "\(seen.sizes)")
  }

  func testASingleLineThatDoesNotFitFails() async {
    let never = FakeDetector { _ in throw AdDetectorError.tooLong }
    do {
      _ = try await AdsRunner.run(
        transcript: makeTranscript(talk(3)), detector: never,
        store: AdsStore(folder: folder, sha256: sha), osVersion: "26.0")
      XCTFail("should have thrown")
    } catch {
      XCTAssertEqual(error as? AdDetectorError, .failed("A single line does not fit the model."))
    }
  }

  func testAnUnavailableModelStopsTheRunAndSavesNothing() async {
    let off = FakeDetector { _ in throw AdDetectorError.unavailable(.appleIntelligenceOff) }
    let store = AdsStore(folder: folder, sha256: sha)
    do {
      _ = try await AdsRunner.run(
        transcript: makeTranscript(talk(20)), detector: off, store: store, osVersion: "26.0")
      XCTFail("should have thrown")
    } catch {
      XCTAssertEqual(error as? AdDetectorError, .unavailable(.appleIntelligenceOff))
    }
    XCTAssertNil(store.load(detector: "fake"))
  }

  func testStoppingBetweenPiecesSavesNothing() async throws {
    let store = AdsStore(folder: folder, sha256: sha)
    let outcome = try await AdsRunner.run(
      transcript: makeTranscript(talk(60)), detector: FakeDetector { _ in [] }, store: store,
      osVersion: "26.0", shouldContinue: { false })
    XCTAssertEqual(outcome, .stopped)
    XCTAssertNil(store.load(detector: "fake"))
  }

  func testUnavailableReasonsReadWell() {
    XCTAssertEqual(AdUnavailable.appleIntelligenceOff.reason, "Apple Intelligence is off")
    XCTAssertEqual(AdUnavailable.modelDownloading.reason, "The model is downloading")
    XCTAssertEqual(AdUnavailable.deviceNotEligible.reason, "This iPhone can't run Apple Intelligence")
    XCTAssertTrue(AdUnavailable.modelDownloading.passesByItself)
    XCTAssertFalse(AdUnavailable.appleIntelligenceOff.passesByItself)
  }
}

private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var all: [Int] = []
  var sizes: [Int] { lock.withLock { all } }
  func add(_ size: Int) { lock.withLock { all.append(size) } }
}
