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

  func testAdsSavedOutsideTheAskedStretchSurviveAPartialRun() async throws {
    let transcript = makeTranscript(talk(160, ad: 40...47))
    let store = AdsStore(folder: folder, sha256: sha)
    let outside = FoundAd(
      start: 1500, end: 1530, kind: .ad, advertiser: "Other", confidence: .sure, firstWords: "x")
    let inside = FoundAd(
      start: 20, end: 40, kind: .ad, advertiser: "Stale", confidence: .sure, firstWords: "y")
    try store.savePartial(
      AdsFile(
        sha256: sha, detector: "fake", detectorVersion: "1", osVersion: "26", duration: 1600,
        ads: [inside, outside], undone: [UndoneAd(start: 5, end: 9)]))
    let outcome = try await AdsRunner.runPartial(
      partial: partial(transcript, lines: 100), detector: detector(Asked()), store: store,
      osVersion: "26")
    guard case .finished(let file) = outcome else { return XCTFail("\(outcome)") }
    XCTAssertTrue(file.ads.contains(outside), "outside the stretch: kept")
    XCTAssertFalse(file.ads.contains(inside), "inside the stretch: the finder's answers win")
    XCTAssertEqual(file.ads.count, 2)
    XCTAssertEqual(file.undone, [UndoneAd(start: 5, end: 9)])
  }

  func testTheFullRunSavesAPartialFileAfterEachPieceItAsks() async throws {
    let transcript = makeTranscript(talk(160, ad: 40...47))
    let all = AdChunker.pieces(of: AdChunker.number(transcript.lines), tokenBudget: 160)
    let adPiece = try XCTUnwrap(all.firstIndex { $0.lines.contains { $0.number == 42 } })
    XCTAssertLessThan(adPiece + 1, all.count - 1, "the ad is not in the last piece")
    let store = AdsStore(folder: folder, sha256: sha)
    let asked = Asked()
    let outcome = try await AdsRunner.run(
      transcript: transcript, detector: detector(asked), store: store, osVersion: "26",
      shouldContinue: { asked.all.count <= adPiece })
    XCTAssertEqual(outcome, .stopped)
    let partial = try XCTUnwrap(store.loadPartial(detector: "fake"))
    XCTAssertEqual(partial.ads.count, 1, "the ad is there before the run is done")
    XCTAssertNil(store.load(detector: "fake"))
    XCTAssertEqual(partial.coveredUntil, all[adPiece].end)
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
    let all = AdChunker.pieces(of: AdChunker.number(transcript.lines), tokenBudget: 160)
    XCTAssertGreaterThan(early, 0)
    XCTAssertEqual(
      Set(fullAsked.all), Set(all.map(\.key)).subtracting(asked.all),
      "only the pieces without a kept whole answer are asked")
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

/// The growing last piece: an ad in the first minutes is found as soon as that part is there.
final class AdsGrowingPieceTests: XCTestCase {
  private var folder: URL!
  private let sha = "aa"

  override func setUpWithError() throws { folder = try temporaryFolder() }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  private final class Asked: @unchecked Sendable {
    private let lock = NSLock()
    private var pieces: [TranscriptPiece] = []
    func add(_ piece: TranscriptPiece) { lock.withLock { pieces.append(piece) } }
    var all: [TranscriptPiece] { lock.withLock { pieces } }
  }

  /// A detector with the real budget. `ad` says which lines it calls an ad in a piece.
  private func detector(
    _ asked: Asked, ad: @escaping @Sendable (TranscriptPiece) -> ClosedRange<Int>? = { _ in 3...5 }
  ) -> FakeDetector {
    FakeDetector(tokenBudget: 2500) { piece in
      asked.add(piece)
      guard let wanted = ad(piece) else { return [] }
      let inside = piece.lines.map(\.number).filter { wanted.contains($0) }
      guard let first = inside.first, let last = inside.last else { return [] }
      return [range(first, last)]
    }
  }

  /// The first `count` lines of a transcript with a sponsor read at lines 3 to 5 (20 to 49 s).
  private func partial(lines count: Int, reached: Double) -> PartialTranscript {
    let transcript = makeTranscript(talk(60, ad: 3...5))
    let words = transcript.words.filter { $0.start < Double(count) * 10 }
    return PartialTranscript(
      identity: transcript.identity, duration: 600, reached: reached, words: words)
  }

  private func run(
    _ partial: PartialTranscript, _ detector: FakeDetector
  ) async throws -> AdsFile {
    let outcome = try await AdsRunner.runPartial(
      partial: partial, detector: detector, store: AdsStore(folder: folder, sha256: sha),
      osVersion: "26")
    guard case .finished(let file) = outcome else {
      XCTFail("\(outcome)")
      throw CancellationError()
    }
    return file
  }

  func testAFiveMinutePartialTranscriptYieldsOneAskablePiece() throws {
    let lines = AdChunker.number(makeTranscript(talk(30)).lines)
    XCTAssertTrue(AdChunker.safePieces(of: lines, tokenBudget: 2500, reached: 300).isEmpty)
    let piece = try XCTUnwrap(AdChunker.growingPiece(of: lines, tokenBudget: 2500, reached: 300))
    XCTAssertEqual(piece.firstNumber, 1)
    XCTAssertEqual(piece.end, 279)
    XCTAssertLessThanOrEqual(piece.end, 300 - AdChunker.partialMargin)
  }

  func testTooLittleTranscriptIsNotAsked() {
    let lines = AdChunker.number(makeTranscript(talk(12)).lines)
    // 120 s done, the lines up to 100 s are old enough: 100 s is enough...
    XCTAssertNotNil(AdChunker.growingPiece(of: lines, tokenBudget: 2500, reached: 120))
    // ...but 70 s done leaves 50 s of lines, under the minimum.
    XCTAssertNil(AdChunker.growingPiece(of: lines, tokenBudget: 2500, reached: 70))
    XCTAssertNil(AdChunker.growingPiece(of: [], tokenBudget: 2500, reached: 700))
  }

  func testAnAdInTheFirstMinutesIsFoundFromAFiveMinuteTranscript() async throws {
    let asked = Asked()
    let file = try await run(partial(lines: 30, reached: 300), detector(asked))
    XCTAssertEqual(asked.all.count, 1)
    XCTAssertEqual(file.ads.count, 1)
    XCTAssertEqual(file.ads[0].start, 20, accuracy: 10)
    XCTAssertEqual(file.coveredUntil, 279)
    XCTAssertNil(file.refusedPieces)
  }

  func testAHeadLimitAsksOnlyTheFirstThreeMinutesAndKeepsTheAnswer() async throws {
    let asked = Asked()
    let store = AdsStore(folder: folder, sha256: sha)
    let outcome = try await AdsRunner.runPartial(
      partial: partial(lines: 60, reached: 600), detector: detector(asked), store: store,
      osVersion: "26", limit: PrepRules.headSeconds)
    guard case .finished(let head) = outcome else { return XCTFail("\(outcome)") }
    XCTAssertEqual(asked.all.count, 1)
    XCTAssertLessThanOrEqual(asked.all[0].end, PrepRules.headSeconds - AdChunker.partialMargin)
    XCTAssertEqual(head.ads.count, 1, "the sponsor read at 20 s is in the head")
    XCTAssertEqual(store.loadPartial(detector: "fake"), head)
    // The partial pass that follows reuses the head's answer while the piece has grown by
    // less than a growing step, so the head is not asked again.
    let later = try await AdsRunner.runPartial(
      partial: partial(lines: 25, reached: 250), detector: detector(asked), store: store,
      osVersion: "26")
    guard case .finished(let grown) = later else { return XCTFail("\(later)") }
    XCTAssertEqual(grown.ads.count, 1)
    XCTAssertEqual(asked.all.count, 1, "nothing was asked again")
  }

  func testTheLongerPieceAsksAgainAndTheAdIsNotDoubled() async throws {
    let asked = Asked()
    let first = try await run(partial(lines: 30, reached: 300), detector(asked))
    let second = try await run(partial(lines: 60, reached: 600), detector(asked))
    XCTAssertEqual(asked.all.count, 2, "the grown piece was asked again")
    XCTAssertEqual(first.ads.count, 1)
    XCTAssertEqual(second.ads, first.ads)
    XCTAssertEqual(second.coveredUntil, 579)
    // Only the newest answer for the piece is kept.
    let kept = AdsStore(folder: folder, sha256: sha).loadProgress(detector: "fake", version: "1")
    XCTAssertEqual(kept.answers.count, 1)
  }

  func testAnAdOnlyTheShortPieceFoundIsDroppedByTheLongerAnswer() async throws {
    let asked = Asked()
    let shortOnly = detector(asked) { $0.lines.count < 40 ? 3...5 : nil }
    let first = try await run(partial(lines: 30, reached: 300), shortOnly)
    XCTAssertEqual(first.ads.count, 1)
    let second = try await run(partial(lines: 60, reached: 600), shortOnly)
    XCTAssertEqual(second.ads, [], "the longer answer wins")
  }

  func testASmallGrowthDoesNotAskAgain() async throws {
    let asked = Asked()
    let first = try await run(partial(lines: 30, reached: 300), detector(asked))
    let second = try await run(partial(lines: 34, reached: 345), detector(asked))
    XCTAssertEqual(asked.all.count, 1, "40 more seconds is under the step")
    XCTAssertEqual(second.ads, first.ads)
    XCTAssertEqual(second.coveredUntil, first.coveredUntil, "it reaches as far as the answer does")
    let third = try await run(partial(lines: 44, reached: 445), detector(asked))
    XCTAssertEqual(asked.all.count, 2, "120 s more asks again")
    XCTAssertEqual(third.coveredUntil, 419)
  }

  func testAWholePieceIsAlwaysAskedAndReplacesTheGrowingAnswers() async throws {
    let asked = Asked()
    // A small budget, so the pieces fill up quickly.
    let small = FakeDetector(tokenBudget: 160) { piece in
      asked.add(piece)
      return []
    }
    _ = try await run(partial(lines: 20, reached: 210), small)
    _ = try await run(partial(lines: 60, reached: 600), small)
    let kept = AdsStore(folder: folder, sha256: sha).loadProgress(detector: "fake", version: "1")
    let starts = kept.answers.keys.compactMap { TranscriptPiece.keyParts($0)?.first }
    XCTAssertEqual(starts.count, Set(starts).count, "one answer for each start")
  }

  func testTheFullPassOfAFinishedTranscriptIsUnchangedByTheGrowingAnswers() async throws {
    let transcript = makeTranscript(talk(30, ad: 3...5))
    let asked = Asked()
    _ = try await run(partial(lines: 30, reached: 300), detector(asked))
    let store = AdsStore(folder: folder, sha256: sha)
    let outcome = try await AdsRunner.run(
      transcript: transcript, detector: detector(Asked()), store: store, osVersion: "26")
    let fresh = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: fresh) }
    let again = try await AdsRunner.run(
      transcript: transcript, detector: detector(Asked()),
      store: AdsStore(folder: fresh, sha256: sha), osVersion: "26")
    XCTAssertEqual(outcome, again)
    guard case .finished(let file) = outcome else { return XCTFail("\(outcome)") }
    XCTAssertEqual(file.ads.count, 1)
    XCTAssertNil(file.coveredUntil)
  }

  // MARK: Failures

  func testARefusedPieceCountsAsNoAdsAndIsReported() async throws {
    let asked = Asked()
    let refusing = FakeDetector(tokenBudget: 2500) { piece in
      asked.add(piece)
      throw AdDetectorError.refused
    }
    let file = try await run(partial(lines: 30, reached: 300), refusing)
    XCTAssertEqual(file.ads, [])
    XCTAssertEqual(file.refusedPieces, 1)
    // It is not asked again (it would be refused again), and the count stays.
    let again = try await run(partial(lines: 31, reached: 310), refusing)
    XCTAssertEqual(asked.all.count, 1)
    XCTAssertEqual(again.refusedPieces, 1)
  }

  func testAnyOtherFailureIsThrownAndSavesNothing() async throws {
    let failing = FakeDetector(tokenBudget: 2500) { _ in throw AdDetectorError.failed("boom") }
    do {
      _ = try await run(partial(lines: 30, reached: 300), failing)
      XCTFail("should throw")
    } catch {
      XCTAssertEqual(error as? AdDetectorError, .failed("boom"))
    }
    let store = AdsStore(folder: folder, sha256: sha)
    XCTAssertNil(store.loadPartial(detector: "fake"))
  }

  func testAFullRunReportsRefusedPieces() async throws {
    let transcript = makeTranscript(talk(30))
    let refusing = FakeDetector(tokenBudget: 2500) { _ in throw AdDetectorError.refused }
    let outcome = try await AdsRunner.run(
      transcript: transcript, detector: refusing, store: AdsStore(folder: folder, sha256: sha),
      osVersion: "26")
    guard case .finished(let file) = outcome else { return XCTFail("\(outcome)") }
    XCTAssertEqual(file.refusedPieces, 1)
  }
}
