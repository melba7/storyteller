import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

final class AdChunkerPartialTests: XCTestCase {
  private func lines(_ count: Int) -> [NumberedLine] {
    AdChunker.number(makeTranscript(talk(count)).lines)
  }

  func testAPrefixGivesTheSamePiecesExceptTheLast() {
    let all = lines(160)
    let full = AdChunker.pieces(of: all, tokenBudget: 160)
    XCTAssertGreaterThan(full.count, 4)
    for count in stride(from: 30, through: 160, by: 13) {
      let prefix = AdChunker.pieces(of: Array(all.prefix(count)), tokenBudget: 160)
      XCTAssertEqual(Array(prefix.dropLast()), Array(full.prefix(prefix.count - 1)), "prefix of \(count)")
    }
  }

  func testOnlyPiecesFarEnoughBeforeTheEdgeAreSafe() {
    let all = lines(160)
    let full = AdChunker.pieces(of: all, tokenBudget: 160)
    let prefix = Array(all.prefix(100))
    let reached = prefix.last!.end + 1
    let safe = AdChunker.safePieces(of: prefix, tokenBudget: 160, reached: reached, margin: 20)
    XCTAssertFalse(safe.isEmpty)
    XCTAssertEqual(safe, Array(full.prefix(safe.count)))
    XCTAssertTrue(safe.allSatisfy { $0.end <= reached - 20 })
    let all2 = AdChunker.pieces(of: prefix, tokenBudget: 160)
    XCTAssertLessThan(safe.count, all2.count, "the last piece is never safe")
  }

  func testAPieceTooCloseToTheEdgeWaits() {
    let prefix = Array(lines(100))
    let pieces = AdChunker.pieces(of: prefix, tokenBudget: 160)
    let beforeLast = pieces[pieces.count - 2]
    let safe = AdChunker.safePieces(
      of: prefix, tokenBudget: 160, reached: beforeLast.end + 5, margin: 20)
    XCTAssertEqual(safe.count, pieces.count - 2)
  }

  func testNothingIsSafeForAShortTranscript() {
    XCTAssertTrue(
      AdChunker.safePieces(of: lines(3), tokenBudget: 160, reached: 1000, margin: 20).isEmpty)
    XCTAssertTrue(AdChunker.safePieces(of: [], tokenBudget: 160, reached: 1000, margin: 20).isEmpty)
  }

  func testAKeyStaysTheSameBetweenThePartialAndTheFullTranscript() {
    let all = lines(160)
    let full = AdChunker.pieces(of: all, tokenBudget: 160)
    let safe = AdChunker.safePieces(
      of: Array(all.prefix(100)), tokenBudget: 160, reached: all[99].end + 1, margin: 20)
    XCTAssertEqual(safe.map(\.key), full.prefix(safe.count).map(\.key))
    XCTAssertEqual(Set(full.map(\.key)).count, full.count, "keys differ between pieces")
  }

  func testAKeyChangesWhenTheTextDoes() {
    var piece = lines(10)
    let before = TranscriptPiece(lines: piece).key
    piece[2].text += " changed"
    XCTAssertNotEqual(TranscriptPiece(lines: piece).key, before)
  }
}

final class AdsPartialStoreTests: XCTestCase {
  private var folder: URL!
  private let sha = "aa"

  override func setUpWithError() throws { folder = try temporaryFolder() }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  private func file(until: Double?) -> AdsFile {
    AdsFile(
      sha256: sha, detector: "fake", detectorVersion: "1", osVersion: "26.0", duration: 600,
      ads: [], coveredUntil: until)
  }

  func testProgressIsSavedPerDetectorVersion() throws {
    let store = AdsStore(folder: folder, sha256: sha)
    var progress = AdProgress(sha256: sha, detector: "fake", detectorVersion: "1")
    progress.answers["k"] = [range(2, 4)]
    try store.saveProgress(progress)
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: folder.appendingPathComponent("\(sha).ads.fake.progress.json").path))
    XCTAssertEqual(store.loadProgress(detector: "fake", version: "1"), progress)
    XCTAssertEqual(store.loadProgress(detector: "fake", version: "2").answers, [:])
    XCTAssertEqual(store.loadProgress(detector: "other", version: "1").answers, [:])
  }

  func testAnUnreadableProgressFileCountsAsNone() throws {
    let store = AdsStore(folder: folder, sha256: sha)
    try Data("nope".utf8).write(to: folder.appendingPathComponent("\(sha).ads.fake.progress.json"))
    XCTAssertEqual(store.loadProgress(detector: "fake", version: "1").answers, [:])
  }

  func testThePartialFileIsReadAndTheFinalOneWins() throws {
    let store = AdsStore(folder: folder, sha256: sha)
    XCTAssertNil(store.best(detector: "fake"))
    try store.savePartial(file(until: 300))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: folder.appendingPathComponent("\(sha).ads.fake.partial.json").path))
    XCTAssertEqual(store.loadPartial(detector: "fake")?.coveredUntil, 300)
    XCTAssertNil(store.load(detector: "fake"), "a partial file is not the final one")
    XCTAssertEqual(store.best(detector: "fake")?.coveredUntil, 300)
    try store.save(file(until: nil))
    XCTAssertNil(store.best(detector: "fake")?.coveredUntil)
  }

  func testTheTextTheAppReadsIsTheFinalFileElseThePartialOne() throws {
    let store = AdsStore(folder: folder, sha256: sha)
    XCTAssertNil(store.bestJSON(detector: "fake"))
    try store.savePartial(file(until: 300))
    let partial = try XCTUnwrap(store.bestJSON(detector: "fake"))
    XCTAssertTrue(partial.contains("\"coveredUntil\":300"))
    try store.save(file(until: nil))
    let final = try XCTUnwrap(store.bestJSON(detector: "fake"))
    XCTAssertFalse(final.contains("coveredUntil"))
    XCTAssertEqual(final, store.json(detector: "fake"))
  }

  func testAnOlderFileWithoutCoveredUntilStillDecodes() throws {
    let old = """
      {"version":1,"sha256":"aa","detector":"fake","detectorVersion":"1","osVersion":"26","duration":5,"ads":[],"undone":[]}
      """
    let decoded = try JSONDecoder().decode(AdsFile.self, from: Data(old.utf8))
    XCTAssertNil(decoded.coveredUntil)
  }
}

final class AdsRunnerPartialTests: XCTestCase {
  private var folder: URL!
  private let sha = "aa"

  override func setUpWithError() throws { folder = try temporaryFolder() }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  /// A counting detector: says lines 40 to 47 are an ad.
  private final class Asked: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String] = []
    func add(_ key: String) { lock.withLock { keys.append(key) } }
    var all: [String] { lock.withLock { keys } }
  }

  private func detector(_ asked: Asked, version: String = "1") -> FakeDetector {
    FakeDetector(version: version, tokenBudget: 160) { piece in
      asked.add(piece.key)
      let inside = piece.lines.map(\.number).filter { (40...47).contains($0) }
      guard let first = inside.first, let last = inside.last else { return [] }
      return [range(first, last)]
    }
  }

  private func partial(_ transcript: Transcript, lines count: Int) -> PartialTranscript {
    let kept = Array(transcript.lines.prefix(count))
    let words = transcript.words.filter { $0.start < kept.last!.end }
    return PartialTranscript(
      identity: transcript.identity, duration: transcript.duration, reached: kept.last!.end + 1,
      words: words)
  }

  func testAPartialRunAsksTheSafePiecesAndSavesAPartialFile() async throws {
    let transcript = makeTranscript(talk(160, ad: 40...47))
    let store = AdsStore(folder: folder, sha256: sha)
    let asked = Asked()
    let outcome = try await AdsRunner.runPartial(
      partial: partial(transcript, lines: 100), detector: detector(asked), store: store,
      osVersion: "26.0")
    guard case .finished(let file) = outcome else { return XCTFail("\(outcome)") }
    XCTAssertEqual(file.ads.count, 1)
    XCTAssertEqual(file.ads[0].start, 390, accuracy: 10)
    let covered = try XCTUnwrap(file.coveredUntil)
    XCTAssertLessThanOrEqual(covered, 100 * 10 - 20)
    XCTAssertGreaterThan(covered, 0)
    XCTAssertEqual(store.loadPartial(detector: "fake"), file)
    XCTAssertNil(store.load(detector: "fake"))
    XCTAssertEqual(
      store.loadProgress(detector: "fake", version: "1").answers.count, asked.all.count)
  }

  func testASecondPartialRunAsksOnlyThePiecesThatAreNew() async throws {
    let transcript = makeTranscript(talk(160, ad: 40...47))
    let store = AdsStore(folder: folder, sha256: sha)
    let asked = Asked()
    _ = try await AdsRunner.runPartial(
      partial: partial(transcript, lines: 80), detector: detector(asked), store: store, osVersion: "26")
    let first = asked.all.count
    _ = try await AdsRunner.runPartial(
      partial: partial(transcript, lines: 80), detector: detector(asked), store: store, osVersion: "26")
    XCTAssertEqual(asked.all.count, first, "nothing new to ask")
    _ = try await AdsRunner.runPartial(
      partial: partial(transcript, lines: 130), detector: detector(asked), store: store, osVersion: "26")
    XCTAssertGreaterThan(asked.all.count, first)
    XCTAssertEqual(Set(asked.all).count, asked.all.count, "no piece was asked twice")
  }

  func testANewDetectorVersionIgnoresOldAnswers() async throws {
    let transcript = makeTranscript(talk(160))
    let store = AdsStore(folder: folder, sha256: sha)
    let asked = Asked()
    _ = try await AdsRunner.runPartial(
      partial: partial(transcript, lines: 100), detector: detector(asked), store: store, osVersion: "26")
    let first = asked.all.count
    _ = try await AdsRunner.runPartial(
      partial: partial(transcript, lines: 100), detector: detector(asked, version: "2"), store: store,
      osVersion: "26")
    XCTAssertEqual(asked.all.count, first * 2)
  }

  func testNothingSafeYetSavesNoFile() async throws {
    let transcript = makeTranscript(talk(160))
    let store = AdsStore(folder: folder, sha256: sha)
    let asked = Asked()
    _ = try await AdsRunner.runPartial(
      partial: partial(transcript, lines: 4), detector: detector(asked), store: store, osVersion: "26")
    XCTAssertTrue(asked.all.isEmpty)
    XCTAssertNil(store.loadPartial(detector: "fake"))
  }

  func testStoppingKeepsTheAnswersSoFar() async throws {
    let transcript = makeTranscript(talk(160))
    let store = AdsStore(folder: folder, sha256: sha)
    let asked = Asked()
    let outcome = try await AdsRunner.runPartial(
      partial: partial(transcript, lines: 130), detector: detector(asked), store: store,
      osVersion: "26", shouldContinue: { asked.all.count < 2 })
    XCTAssertEqual(outcome, .stopped)
    XCTAssertEqual(store.loadProgress(detector: "fake", version: "1").answers.count, 2)
  }

  func testTheFullRunReusesAnswersAndRemovesTheScratchFiles() async throws {
    let transcript = makeTranscript(talk(160, ad: 40...47))
    let store = AdsStore(folder: folder, sha256: sha)
    let asked = Asked()
    _ = try await AdsRunner.runPartial(
      partial: partial(transcript, lines: 100), detector: detector(asked), store: store, osVersion: "26")
    let early = asked.all.count
    let fullAsked = Asked()
    let outcome = try await AdsRunner.run(
      transcript: transcript, detector: detector(fullAsked), store: store, osVersion: "26")
    guard case .finished(let file) = outcome else { return XCTFail("\(outcome)") }
    let total = AdChunker.pieces(of: AdChunker.number(transcript.lines), tokenBudget: 160).count
    XCTAssertEqual(fullAsked.all.count, total - early)
    XCTAssertTrue(Set(fullAsked.all).isDisjoint(with: asked.all))
    XCTAssertNil(file.coveredUntil)
    XCTAssertEqual(store.load(detector: "fake"), file)
    XCTAssertNil(store.loadPartial(detector: "fake"))
    XCTAssertEqual(store.loadProgress(detector: "fake", version: "1").answers, [:])
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: folder.appendingPathComponent("\(sha).ads.fake.progress.json").path))
    // Same ads as a run with nothing reused.
    let fresh = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: fresh) }
    let again = try await AdsRunner.run(
      transcript: transcript, detector: detector(Asked()), store: AdsStore(folder: fresh, sha256: sha),
      osVersion: "26")
    XCTAssertEqual(again, .finished(file))
  }
}
