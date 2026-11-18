import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// A piece the model refuses is asked again in halves, so the ad in the half that is not
/// refused is still found.
final class AdsRefusalTests: XCTestCase {
  private var folder: URL!
  private let sha = String(repeating: "ab", count: 32)

  override func setUpWithError() throws { folder = try temporaryFolder() }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  private final class Asked: @unchecked Sendable {
    private let lock = NSLock()
    private var pieces: [TranscriptPiece] = []
    func add(_ piece: TranscriptPiece) { lock.withLock { pieces.append(piece) } }
    var all: [TranscriptPiece] { lock.withLock { pieces } }
    var sizes: [Int] { all.map(\.lines.count) }
  }

  private final class Switch: @unchecked Sendable {
    private let lock = NSLock()
    private var isOn = true
    var on: Bool {
      get { lock.withLock { isOn } }
      set { lock.withLock { isOn = newValue } }
    }
  }

  /// A detector with the real budget, so the whole transcript of the tests is one piece. It
  /// refuses the pieces `refuses` says, and calls the lines of the sponsor read ("ad copy ...")
  /// an ad in the others.
  private func detector(
    _ asked: Asked, refuses: @escaping @Sendable (TranscriptPiece) -> Bool
  ) -> FakeDetector {
    FakeDetector(tokenBudget: 2500) { piece in
      asked.add(piece)
      if refuses(piece) { throw AdDetectorError.refused }
      let inside = piece.lines.filter { $0.text.hasPrefix("ad copy") }.map(\.number)
      guard let first = inside.first, let last = inside.last else { return [] }
      return [range(first, last)]
    }
  }

  private func finish(
    _ transcript: Transcript, _ detector: FakeDetector, file: StaticString = #filePath,
    line: UInt = #line
  ) async throws -> AdsFile {
    let outcome = try await AdsRunner.run(
      transcript: transcript, detector: detector, store: AdsStore(folder: folder, sha256: sha),
      osVersion: "26")
    guard case .finished(let result) = outcome else {
      XCTFail("\(outcome)", file: file, line: line)
      throw CancellationError()
    }
    return result
  }

  func testARefusedPieceIsAskedInHalvesAndKeepsTheAdInTheOtherHalf() async throws {
    let asked = Asked()
    // The model refuses any piece that holds line 50. The sponsor read is in lines 20 to 25.
    let file = try await finish(
      makeTranscript(talk(60, ad: 20...25)),
      detector(asked) { piece in piece.lines.contains { $0.number == 50 } })
    XCTAssertEqual(file.ads.count, 1)
    XCTAssertEqual(file.refusedPieces, 1, "the part around line 50 could not be read")
    XCTAssertEqual(asked.sizes.first, 60, "the whole piece is asked first")
    XCTAssertEqual(AdsRules.finished(file), .partlyChecked(count: 1))
  }

  func testAPieceWhoseHalvesBothAnswerCountsAsNotRefused() async throws {
    let asked = Asked()
    let file = try await finish(
      makeTranscript(talk(60, ad: 20...25)), detector(asked) { $0.lines.count > 30 })
    XCTAssertEqual(asked.sizes, [60, 30, 30])
    XCTAssertEqual(file.ads.count, 1)
    XCTAssertNil(file.refusedPieces)
    XCTAssertEqual(AdsRules.finished(file), .found(count: 1))
  }

  func testAPieceShorterThanTheGrowingMinimumIsNotSplit() async throws {
    // Five lines are 49 seconds, under `AdChunker.growingMinimum`: one question, one refusal.
    XCTAssertEqual(AdChunker.growingMinimum, 60)
    let short = Asked()
    let file = try await finish(makeTranscript(talk(5)), detector(short) { _ in true })
    XCTAssertEqual(short.sizes, [5])
    XCTAssertEqual(file.refusedPieces, 1)
    // Seven lines are 69 seconds: they are split once, and the halves (3 and 4 lines) are too
    // short to be split again.
    let long = Asked()
    let again = try await finish(makeTranscript(talk(7)), detector(long) { _ in true })
    XCTAssertEqual(long.sizes, [7, 3, 4])
    XCTAssertEqual(again.refusedPieces, 1)
  }

  func testTheSplitGoesAtMostTwoLevelsDeep() async throws {
    let asked = Asked()
    let file = try await finish(makeTranscript(talk(60)), detector(asked) { _ in true })
    // The piece, its two halves and their four halves: six more questions, and no more.
    XCTAssertEqual(asked.sizes, [60, 30, 15, 15, 30, 15, 15])
    XCTAssertEqual(file.refusedPieces, 1, "one piece is counted once, however many leaves")
    XCTAssertTrue(file.ads.isEmpty)
  }

  func testHalvesKeepTheLineNumbersOfTheWholeTranscript() async throws {
    let asked = Asked()
    let file = try await finish(
      makeTranscript(talk(60, ad: 40...45)), detector(asked) { $0.lines.count > 30 })
    // Lines 40 to 45 are in the second half, which starts at line 31.
    XCTAssertEqual(asked.all.map(\.firstNumber), [1, 1, 31])
    let ad = try XCTUnwrap(file.ads.first)
    XCTAssertEqual(ad.start, 390, accuracy: 10)
    XCTAssertEqual(ad.end, 450, accuracy: 10)
  }

  func testARefusedPieceIsRememberedSoItIsNotAskedAgainOnTheNextRun() async throws {
    // 40 lines make five pieces of the default budget. The first holds line 3, which is
    // refused, and the sponsor read in lines 12 to 14 is in its other half. The second piece
    // fails once, so the run stops after the first.
    let transcript = makeTranscript(talk(40, ad: 12...14))
    let pieces = AdChunker.pieces(of: AdChunker.number(transcript.lines), tokenBudget: 150)
    XCTAssertGreaterThan(pieces.count, 2)
    let secondKey = pieces[1].key
    let failing = Switch()
    let asked = Asked()
    let model = FakeDetector { piece in
      asked.add(piece)
      if piece.lines.contains(where: { $0.number == 3 }) { throw AdDetectorError.refused }
      if failing.on, piece.key == secondKey { throw AdDetectorError.failed("boom") }
      let inside = piece.lines.filter { $0.text.hasPrefix("ad copy") }.map(\.number)
      guard let first = inside.first, let last = inside.last else { return [] }
      return [range(first, last)]
    }
    let store = AdsStore(folder: folder, sha256: sha)
    do {
      _ = try await AdsRunner.run(
        transcript: transcript, detector: model, store: store, osVersion: "26")
      XCTFail("the second piece fails")
    } catch {
      XCTAssertEqual(error as? AdDetectorError, .failed("boom"))
    }
    let kept = store.loadProgress(detector: "fake", version: "1")
    XCTAssertEqual(kept.refused, [pieces[0].key], "the refused piece is kept in the progress file")
    let askedAboutLine3 = asked.all.filter { $0.lines.contains { $0.number == 3 } }.count
    XCTAssertGreaterThan(askedAboutLine3, 1, "it was asked in halves")

    failing.on = false
    let outcome = try await AdsRunner.run(
      transcript: transcript, detector: model, store: store, osVersion: "26")
    guard case .finished(let file) = outcome else { return XCTFail("\(outcome)") }
    XCTAssertEqual(
      asked.all.filter { $0.lines.contains { $0.number == 3 } }.count, askedAboutLine3,
      "the refused piece was not asked again")
    XCTAssertEqual(file.refusedPieces, 1)
    XCTAssertEqual(file.ads.count, 1)
  }

  func testAGrowingPieceThatIsRefusedIsAskedOnce() async throws {
    // A growing piece is asked again every time it has grown, so it is not asked in halves
    // as well; once it is a whole piece it is.
    let asked = Asked()
    let transcript = makeTranscript(talk(60, ad: 3...5))
    let words = transcript.words.filter { $0.start < 300 }
    let outcome = try await AdsRunner.runPartial(
      partial: PartialTranscript(
        identity: transcript.identity, duration: 600, reached: 300, words: words),
      detector: detector(asked) { _ in true }, store: AdsStore(folder: folder, sha256: sha),
      osVersion: "26")
    guard case .finished(let file) = outcome else { return XCTFail("\(outcome)") }
    XCTAssertEqual(asked.all.count, 1)
    XCTAssertEqual(file.refusedPieces, 1)
  }
}
