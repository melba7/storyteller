import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// A transcript of `count` lines, one every `step` seconds, each about `chars` characters.
func makeLines(count: Int, step: Double = 10, chars: Int = 60) -> [NumberedLine] {
  (0..<count).map {
    NumberedLine(
      number: $0 + 1, start: Double($0) * step, end: Double($0) * step + step - 1,
      text: String(repeating: "x", count: chars))
  }
}

final class AdChunkerTests: XCTestCase {
  func testNumbersLinesFromOne() {
    let numbered = AdChunker.number([
      TranscriptLine(start: 0, end: 2, text: "a"), TranscriptLine(start: 3, end: 5, text: "b"),
    ])
    XCTAssertEqual(numbered.map(\.number), [1, 2])
    XCTAssertEqual(numbered[1].prompt, "[2] b")
  }

  func testEstimateIsAboutFourCharactersPerToken() {
    let line = NumberedLine(number: 1, start: 0, end: 1, text: String(repeating: "x", count: 95))
    // "[1] " and the line break add 5 characters: 100 characters, 25 tokens.
    XCTAssertEqual(AdChunker.tokens(of: line), 25)
  }

  func testEveryPieceFitsTheBudgetAndTheLinesAreCovered() {
    let lines = makeLines(count: 200)
    let budget = 300
    let pieces = AdChunker.pieces(of: lines, tokenBudget: budget, overlap: 120)
    XCTAssertGreaterThan(pieces.count, 1)
    for piece in pieces {
      XCTAssertLessThanOrEqual(piece.lines.map(AdChunker.tokens(of:)).reduce(0, +), budget)
    }
    XCTAssertEqual(pieces.first?.firstNumber, 1)
    XCTAssertEqual(pieces.last?.lastNumber, 200)
    let covered = Set(pieces.flatMap { $0.lines.map(\.number) })
    XCTAssertEqual(covered, Set(1...200))
  }

  func testPiecesOverlapByAboutTwoMinutes() {
    let lines = makeLines(count: 200)
    let pieces = AdChunker.pieces(of: lines, tokenBudget: 500, overlap: 120)
    for (a, b) in zip(pieces, pieces.dropFirst()) {
      XCTAssertLessThanOrEqual(b.firstNumber, a.lastNumber, "no gap between pieces")
      let overlapSeconds = a.end - b.start
      XCTAssertGreaterThanOrEqual(overlapSeconds, 100)
      XCTAssertLessThanOrEqual(overlapSeconds, 130)
      XCTAssertGreaterThan(b.lastNumber, a.lastNumber, "each piece reaches further")
    }
  }

  func testOverlapIsTrimmedWhenItWouldLeaveNoRoom() {
    // The overlap alone (120 s = 12 lines) costs more than the budget allows.
    let lines = makeLines(count: 60)
    let pieces = AdChunker.pieces(of: lines, tokenBudget: 100, overlap: 120)
    XCTAssertEqual(pieces.last?.lastNumber, 60)
    for (a, b) in zip(pieces, pieces.dropFirst()) {
      XCTAssertGreaterThan(b.lastNumber, a.lastNumber)
      XCTAssertGreaterThan(b.firstNumber, a.firstNumber)
    }
  }

  func testAShortTranscriptIsOnePieceAndAnEmptyOneNone() {
    XCTAssertEqual(AdChunker.pieces(of: makeLines(count: 5), tokenBudget: 2500).count, 1)
    XCTAssertTrue(AdChunker.pieces(of: [], tokenBudget: 2500).isEmpty)
  }

  func testALineOverTheBudgetGetsItsOwnPiece() {
    let pieces = AdChunker.pieces(of: makeLines(count: 3, chars: 400), tokenBudget: 20, overlap: 0)
    XCTAssertEqual(pieces.map(\.lines.count), [1, 1, 1])
  }

  func testSplitCutsInTwoAndStopsAtOneLine() throws {
    let piece = TranscriptPiece(lines: makeLines(count: 5))
    let (a, b) = try XCTUnwrap(AdChunker.split(piece))
    XCTAssertEqual(a.lines.count + b.lines.count, 5)
    XCTAssertEqual(a.lastNumber + 1, b.firstNumber)
    XCTAssertNil(AdChunker.split(TranscriptPiece(lines: makeLines(count: 1))))
  }
}
