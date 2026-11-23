import XCTest

@testable import PodcastAds

/// `AdAsks` turns the lines a model is half sure about into questions. A line is asked about
/// when its chance of being an ad lies from the ask threshold up to (not including) the
/// model's own start threshold, and it is not inside a found ad.
final class AdAsksTests: XCTestCase {
  // MARK: Helpers

  /// A row of the five class probabilities where the chance of an ad is `chance`, all of it in
  /// the "sponsor" class.
  private func row(_ chance: Double, sort: Int = 1) -> [Double] {
    var row = [Double](repeating: 0, count: 5)
    row[0] = 1 - chance
    row[sort] = chance
    return row
  }

  /// One line for each chance, 5 seconds long and 6 seconds apart (line n covers 6(n-1) to
  /// 6(n-1)+5), numbered from 1, with its rows.
  private func lines(_ chances: [Double], sort: Int = 1) -> (lines: [NumberedLine], rows: [[Double]]) {
    let lines = chances.indices.map {
      NumberedLine(number: $0 + 1, start: Double($0) * 6, end: Double($0) * 6 + 5, text: "line \($0 + 1) says words")
    }
    return (lines, chances.map { row($0, sort: sort) })
  }

  private func ask(
    _ chances: [Double], from: Double = AdAsks.askFrom, below: Double = 0.6,
    outside ads: [FoundAd] = [], source: String = "word-model"
  ) -> [FoundAd] {
    let made = lines(chances)
    return AdAsks.questions(
      lines: made.lines, rows: made.rows, from: from, below: below, outside: ads, source: source)
  }

  private func found(_ start: Double, _ end: Double, _ confidence: AdConfidence = .sure) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "Acme", confidence: confidence, firstWords: "")
  }

  /// `count` lines of one chance, then `gap` plain lines (chance 0.02) between runs.
  private func runs(_ chances: [Double], lines each: Int = 4, gap: Int = 2) -> [Double] {
    chances.flatMap { [Double](repeating: $0, count: each) + [Double](repeating: 0.02, count: gap) }
  }

  // MARK: What is asked

  func testARunBetweenTheAskThresholdAndTheStartThresholdIsAsked() {
    let asked = ask([0.02, 0.02, 0.45, 0.45, 0.45, 0.45, 0.02, 0.02])
    XCTAssertEqual(asked.count, 1)
    let question = asked[0]
    XCTAssertEqual(question.start, 12, "the first line of the run starts it")
    XCTAssertEqual(question.end, 35, "the last line of the run ends it")
    XCTAssertEqual(question.confidence, .guess, "a question is never skipped by what reads `ads`")
    XCTAssertEqual(question.kind, .ad)
    XCTAssertEqual(question.source, "word-model", "the caller names the finder")
    XCTAssertEqual(question.advertiser, "")
    XCTAssertEqual(
      question.firstWords, "line 3 says words line 4 says words line 5 says words line 6",
      "the first fourteen words of the run")
  }

  func testARunAboveTheStartThresholdIsNotAsked() {
    // It is an ad as before: the model's own spans take it.
    XCTAssertEqual(ask([0.02, 0.7, 0.7, 0.7, 0.7, 0.02]), [])
    XCTAssertEqual(ask([0.02, 0.6, 0.6, 0.6, 0.6, 0.02]), [], "the start threshold itself is an ad")
  }

  func testARunBelowTheAskThresholdIsNotAsked() {
    XCTAssertEqual(ask([0.2, 0.2, 0.2, 0.2, 0.2, 0.2]), [])
    XCTAssertEqual(ask([0.34, 0.34, 0.34, 0.34, 0.34]), [])
  }

  func testTheBandIncludesTheAskThresholdAndLeavesOutTheStartThreshold() {
    // 0.25 and 0.5 are exact in a double, so the edges are tested without rounding.
    XCTAssertEqual(ask([0.25, 0.25, 0.25, 0.25], from: 0.25, below: 0.5).count, 1)
    XCTAssertEqual(ask([0.5, 0.5, 0.5, 0.5], from: 0.25, below: 0.5), [])
  }

  func testTheAskThresholdIsAParameter() {
    let chances = [0.45, 0.45, 0.45, 0.45]
    XCTAssertEqual(ask(chances).count, 1)
    XCTAssertEqual(ask(chances, from: 0.5), [], "a higher ask threshold asks less")
    XCTAssertEqual(AdAsks.askFrom, 0.35)
  }

  func testARunOfDifferentChancesInsideTheBandIsOneQuestion() {
    XCTAssertEqual(ask([0.02, 0.36, 0.59, 0.4, 0.5, 0.02]).count, 1)
  }

  func testAWeakLineBreaksTheRun() {
    // 3 lines are 17 s, and the two halves are each 10 s or more, so both are asked.
    let asked = ask([0.45, 0.45, 0.2, 0.45, 0.45])
    XCTAssertEqual(asked.map(\.start).sorted(), [0, 18])
  }

  // MARK: How long

  func testARunShorterThanTenSecondsIsNotAsked() {
    // One 5 s line, and two 4 s lines with a 1 s gap (9 s from start to end).
    XCTAssertEqual(ask([0.45]), [])
    let two = [
      NumberedLine(number: 1, start: 0, end: 4, text: "a b"),
      NumberedLine(number: 2, start: 5, end: 9, text: "c d"),
    ]
    XCTAssertEqual(
      AdAsks.questions(lines: two, rows: [row(0.45), row(0.45)], below: 0.6, outside: [], source: "x"), [])
  }

  func testARunOfExactlyTenSecondsIsAsked() {
    let lines = [
      NumberedLine(number: 1, start: 0, end: 5, text: "a b"),
      NumberedLine(number: 2, start: 5, end: 10, text: "c d"),
    ]
    let asked = AdAsks.questions(
      lines: lines, rows: [row(0.45), row(0.45)], below: 0.6, outside: [], source: "x")
    XCTAssertEqual(asked.count, 1)
    XCTAssertEqual(asked.first?.duration, 10)
  }

  func testARunLongerThanTheLongestAdIsNotAsked() {
    // A stretch the model is unsure about for over five minutes is a mistake, not a break.
    let long = [Double](repeating: 0.45, count: 60)  // 60 lines, 6 s apart: 359 s
    XCTAssertEqual(ask(long), [])
    XCTAssertEqual(ask([Double](repeating: 0.45, count: 50)).count, 1, "299 s still fits")
  }

  // MARK: How many, and which

  func testNeverMoreThanThreeAndTheMostLikelyFirst() {
    // Five separate runs; the chances are 0.40, 0.55, 0.45, 0.50 and 0.38 (starts 0, 36, ...).
    let chances = runs([0.40, 0.55, 0.45, 0.50, 0.38])
    let asked = ask(chances)
    XCTAssertEqual(asked.count, 3)
    XCTAssertEqual(asked.map(\.start), [36, 108, 72], "0.55, then 0.50, then 0.45")
    XCTAssertEqual(AdAsks.most, 3)
  }

  func testTheMostLikelyIsTheMeanChanceOfTheRun() {
    // One run has a single 0.59 line among 0.36 lines (mean 0.41), the other is a steady 0.45.
    let chances = [0.36, 0.59, 0.36, 0.36, 0.02, 0.02, 0.45, 0.45, 0.45, 0.45]
    XCTAssertEqual(ask(chances).map(\.start), [36, 0])
  }

  func testRunsWithTheSameChanceComeEarliestFirst() {
    XCTAssertEqual(ask(runs([0.45, 0.45, 0.45])).map(\.start), [0, 36, 72])
  }

  // MARK: Found ads

  func testALineInsideAFoundAdIsLeftOut() {
    // Eight lines at 0.45 cover 0 to 47 s; an ad takes 18 to 47, so the first three lines remain.
    let asked = ask([Double](repeating: 0.45, count: 8), outside: [found(18, 47)])
    XCTAssertEqual(asked.count, 1)
    XCTAssertEqual(asked.first?.start, 0)
    XCTAssertEqual(asked.first?.end, 17)
  }

  func testAnAdThatTouchesALineOnlyAtItsEdgeLeavesTheLineIn() {
    // The ad starts exactly where line 3 ends (it is 12 to 17: the ad starts at 17).
    let asked = ask([Double](repeating: 0.45, count: 3), outside: [found(17, 40)])
    XCTAssertEqual(asked.count, 1)
    XCTAssertEqual(asked.first?.end, 17)
  }

  func testNothingIsAskedInsideAnAdWhateverItsConfidence() {
    let chances = [Double](repeating: 0.45, count: 8)
    for confidence in [AdConfidence.sure, .unsure, .guess] {
      XCTAssertEqual(ask(chances, outside: [found(-10, 100, confidence)]), [], "\(confidence)")
    }
  }

  // MARK: The kind

  func testTheKindFollowsTheClassWithTheMostChanceOverTheRun() {
    XCTAssertEqual(askKind(sort: 1), .ad)
    XCTAssertEqual(askKind(sort: 2), .promo)
    XCTAssertEqual(askKind(sort: 3), .ownPlug)
    XCTAssertEqual(askKind(sort: 4), .credits)
  }

  private func askKind(sort: Int) -> AdKind? {
    let made = lines([0.45, 0.45, 0.45, 0.45], sort: sort)
    return AdAsks.questions(
      lines: made.lines, rows: made.rows, below: 0.6, outside: [], source: "x"
    ).first?.kind
  }

  func testARowOfAnUnknownShapeStillGivesAnAd() {
    // Two classes only: the chance is still 1 minus the first, and the kind falls back to ad.
    let made = lines([0.45, 0.45, 0.45, 0.45])
    let rows = made.rows.map { [$0[0], $0[1]] }
    let asked = AdAsks.questions(lines: made.lines, rows: rows, below: 0.6, outside: [], source: "x")
    XCTAssertEqual(asked.first?.kind, .ad)
  }

  func testTheFirstWordsAreAtMostFourteen() {
    let text = (1...30).map { "w\($0)" }.joined(separator: " ")
    let lines = [NumberedLine(number: 1, start: 0, end: 20, text: text)]
    let asked = AdAsks.questions(
      lines: lines, rows: [row(0.45)], below: 0.6, outside: [], source: "x")
    XCTAssertEqual(asked.first?.firstWords.split(separator: " ").count, AdRules.firstWords)
    XCTAssertTrue(asked.first?.firstWords.hasPrefix("w1 w2 w3") == true)
  }

  // MARK: Bad input

  func testEmptyAndNaNRowsTrapNothing() {
    let made = lines([0.45, 0.45, 0.45, 0.45])
    func asked(_ lines: [NumberedLine], _ rows: [[Double]]) -> [FoundAd] {
      AdAsks.questions(lines: lines, rows: rows, below: 0.6, outside: [], source: "x")
    }
    XCTAssertEqual(asked([], []), [])
    XCTAssertEqual(asked(made.lines, []), [])
    XCTAssertEqual(asked([], made.rows), [])
    XCTAssertEqual(asked(made.lines, [[], [], [], []]), [])
    XCTAssertEqual(asked(made.lines, [[0.5], [0.5], [0.5], [0.5]]), [], "one number is no row")
    let nan = Double.nan, inf = Double.infinity
    XCTAssertEqual(asked(made.lines, [[nan, 0.5, 0, 0, 0], [nan, 0, 0, 0, 0], [nan, nan, nan, nan, nan], [inf, 0, 0, 0, 0]]), [])
    XCTAssertEqual(asked(made.lines, [[-inf, 0, 0, 0, 0], [-5, 0, 0, 0, 0], [7, 0, 0, 0, 0], [0.5, nan, 0, 0, 0]]).count, 0)
  }

  func testAWrongSizedRowListReadsOnlyTheLinesThatHaveRows() {
    let made = lines([0.45, 0.45, 0.45, 0.45, 0.45, 0.45])
    let few = Array(made.rows.prefix(4))
    let asked = AdAsks.questions(lines: made.lines, rows: few, below: 0.6, outside: [], source: "x")
    XCTAssertEqual(asked.count, 1)
    XCTAssertEqual(asked.first?.end, 23, "the fourth line is the last one with a row")
  }

  func testBadThresholdsAndBadTimesAskNothing() {
    let made = lines([0.45, 0.45, 0.45, 0.45])
    func asked(from: Double, below: Double) -> [FoundAd] {
      AdAsks.questions(lines: made.lines, rows: made.rows, from: from, below: below, outside: [], source: "x")
    }
    XCTAssertEqual(asked(from: .nan, below: 0.6), [])
    XCTAssertEqual(asked(from: 0.35, below: .nan), [])
    XCTAssertEqual(asked(from: 0.6, below: 0.35), [], "an empty band")
    var broken = made.lines
    broken[1].start = .nan
    broken[2].end = .infinity
    XCTAssertEqual(
      AdAsks.questions(lines: broken, rows: made.rows, below: 0.6, outside: [], source: "x"), [])
    let reversed = [NumberedLine(number: 1, start: 30, end: 5, text: "a b")]
    XCTAssertEqual(
      AdAsks.questions(lines: reversed, rows: [row(0.45)], below: 0.6, outside: [], source: "x"), [])
    XCTAssertEqual(ask([0.45, 0.45, 0.45, 0.45], outside: [found(.nan, .nan), found(.infinity, 0)]).count, 1)
  }
}
