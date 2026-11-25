import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// `podcast-teach score --ahead`: the row "Plus the Mac's marks from the night before", on a tiny
/// teaching folder made up here. The marks are made from Claude's own labels and the words of the
/// transcript, and go through the same finder as the phone's.
final class AheadScoreRowTests: XCTestCase {
  private var folder: FolderWriter!
  private var printed: [String] = []
  private var warned: [String] = []
  private let rowName = "Plus the Mac's marks from the night before"

  override func setUpWithError() throws { folder = try FolderWriter() }
  override func tearDown() { folder.remove() }

  /// A transcript of one line every 10 seconds, 30 lines, 6 invented words a line, and the lines
  /// from `first` to `last` (counted from 1) given 20 words of an ad of this episode.
  private func transcript(_ tag: String, adLines first: Int, _ last: Int) -> String {
    (1...30).map { line in
      let at = (line - 1) * 10
      let stamp = String(format: "[%d:%02d:%02d.0]", at / 3600, at % 3600 / 60, at % 60)
      let words =
        (first...last).contains(line)
        ? (0..<20).map { "\(tag)ad\(line)x\($0)" } : (0..<6).map { "\(tag)talk\(line)x\($0)" }
      return "\(stamp) " + words.joined(separator: " ")
    }.joined(separator: "\n") + "\n"
  }

  /// Two shows, one episode each; each has one marked sponsor ad that no rule of the phone would
  /// find, because it is made of invented words. e1: 100 to 130 s. e2: 150 to 190 s.
  private func fill(secondDownloadOfE2: Bool = false) throws {
    try folder.write(
      "episodes.json",
      #"{"version": 1, "episodes": [{"id": "e1", "feed": "https://one.test/rss", "show": "One", "title": "T1", "seconds": 300}, {"id": "e2", "feed": "https://two.test/rss", "show": "Two", "title": "T2", "seconds": 300}]}"#
    )
    try folder.write("transcripts/e1.txt", transcript("a", adLines: 11, 13))
    try folder.write("transcripts/e2.txt", transcript("b", adLines: 16, 19))
    try folder.write("labels/e1.json", labelJSON(segmentJSON(start: "100", end: "130")))
    try folder.write("labels/e2.json", labelJSON(segmentJSON(start: "150", end: "190")))
    if secondDownloadOfE2 {
      try folder.write("copies/e2.truth.txt", "# two downloads\n2:28.5 3:10.0\n")
    }
  }

  private func run(_ options: [String] = ["--no-model", "--no-library", "--all", "--ahead"]) -> Int32 {
    printed = []
    warned = []
    return AdScoreCommand.run(
      [folder.url.path] + options, out: { self.printed.append($0) }, err: { self.warned.append($0) })
  }

  private var output: String { printed.joined(separator: "\n") }

  private func saved() -> [ScorecardRow] {
    ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json")).runs.last?.rows ?? []
  }

  // MARK: The row

  func testTheRowComesAfterTheLastFinderRowAndPassesWhatTheMarksFind() throws {
    try fill()
    XCTAssertEqual(run(), 0, output + warned.joined())
    let rows = saved()
    XCTAssertEqual(rows.map(\.name).suffix(2), ["Plus per-show settings", rowName])
    let before = try XCTUnwrap(rows.first { $0.name == "Plus per-show settings" }?.bar)
    let after = try XCTUnwrap(rows.last?.bar)
    XCTAssertEqual(before.breaks, 2)
    XCTAssertEqual(before.passed, 0, "nothing of the phone finds invented words")
    XCTAssertEqual(after.passed, 2, "the marks' words are in the transcripts, with the edges of the labels")
    XCTAssertEqual(after.noAdSkips, 0)
    XCTAssertTrue(output.contains(rowName), output)
  }

  func testTheRunsTotalIsStillTheLastFinderRow() throws {
    try fill()
    XCTAssertEqual(run(), 0)
    let history = ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json"))
    let rows = try XCTUnwrap(history.runs.last?.rows)
    XCTAssertEqual(history.runs.last?.total, rows.first { $0.name == "Plus per-show settings" }?.total)
  }

  func testWithoutTheFlagThereIsNoRow() throws {
    try fill()
    XCTAssertEqual(run(["--no-model", "--no-library", "--all"]), 0)
    XCTAssertFalse(saved().contains { $0.name == rowName })
    XCTAssertFalse(output.contains(rowName), output)
  }

  func testTheReportSaysWhatTheMarksAreMadeOfTheBarTheCausesAndTheVerdict() throws {
    try fill()
    XCTAssertEqual(run(), 0)
    XCTAssertTrue(output.contains("\(rowName): 2 of 2 scored episodes have marks"), output)
    XCTAssertTrue(output.contains("2 marked ads"), output)
    XCTAssertTrue(output.contains("no second download"), output)
    XCTAssertTrue(output.contains("2 of 2 breaks pass"), output)
    XCTAssertTrue(output.contains("Why breaks fail in this row: no break fails."), output)
    XCTAssertTrue(output.contains("Verdict: no go. 2 more breaks pass than the last finder row"), output)
    XCTAssertTrue(output.contains("the real number comes from the exam"), output)
  }

  // MARK: Two downloads

  func testASpotThatTheSecondDownloadShowsTheHostPutInIsNotInTheMarks() throws {
    try fill(secondDownloadOfE2: true)
    XCTAssertEqual(run(), 0)
    let after = try XCTUnwrap(saved().last?.bar)
    XCTAssertEqual(after.passed, 1, "e1 has no second download, so its spot is used; e2's is left out")
    XCTAssertTrue(output.contains("1 marked ad left out"), output)
    XCTAssertTrue(output.contains("second download"), output)
  }

  func testASpotBothDownloadsHaveStaysInTheMarks() throws {
    try fill()
    // The two downloads differ only far from e2's ad.
    try folder.write("copies/e2.truth.txt", "0:10.0 0:30.0\n")
    XCTAssertEqual(run(), 0)
    XCTAssertEqual(try XCTUnwrap(saved().last?.bar).passed, 2)
    XCTAssertTrue(output.contains("0 marked ads left out"), output)
  }

  func testTheMarksAreClaudesOwnLabelsEvenWhenTheRunScoresTheSnappedOnes() throws {
    try fill()
    // The snapped labels hold an ad that only the second download found; Claude marked nothing there.
    try folder.write("labels-snapped/e1.json", labelJSON(segmentJSON(start: "100", end: "130") + ", " + segmentJSON(start: "200", end: "230")))
    try folder.write("labels-snapped/e2.json", labelJSON(segmentJSON(start: "150", end: "190")))
    XCTAssertEqual(run(["--no-model", "--no-library", "--all", "--ahead", "--labels", "labels-snapped"]), 0)
    let after = try XCTUnwrap(saved().last?.bar)
    XCTAssertEqual(after.breaks, 3)
    XCTAssertEqual(after.passed, 2, "the unmarked stretch stays missed")
  }

  // MARK: What is left out

  func testCreditsAndEpisodesWithNoMarkedAdGiveNoMark() throws {
    try fill()
    try folder.write("labels/e1.json", labelJSON(segmentJSON(start: "100", end: "130", sort: "intro_credits")))
    XCTAssertEqual(run(), 0)
    XCTAssertTrue(output.contains("\(rowName): 1 of 2 scored episodes have marks"), output)
  }

  func testLowConfidenceMarksAreUnsureAndAllKindsOfAdsAreMarked() throws {
    try fill()
    try folder.write(
      "labels/e1.json",
      labelJSON(segmentJSON(start: "100", end: "130", sort: "host_ask", confidence: "low")))
    XCTAssertEqual(run(), 0)
    // A low mark is still a mark; the bar counts it only as a maybe, never as an ad that was missed.
    XCTAssertTrue(output.contains("\(rowName): 2 of 2 scored episodes have marks"), output)
  }

  func testTheRowSkipsAHighOrMediumMarkAndOnlyAsksAboutALowOneAsThePhoneDoes() throws {
    // The bar counts a skip over a low-marked stretch as neither right nor wrong (`maybe`), so the
    // row's own layer is looked at: its list holds the ads the row skips, and no question.
    let lines = (1...30).map { line in
      (11...13).contains(line)
        ? (0..<20).map { "ad\(line)x\($0)" }.joined(separator: " ")
        : (0..<6).map { "talk\(line)x\($0)" }.joined(separator: " ")
    }
    let episode = TeachingEpisode(
      id: "e1", feed: "feed1", show: "Show One", title: "Title", transcript: makeTranscript(lines),
      truth: [], maybe: [], onShelf: true)
    let adWords = (11...13).flatMap { line in (0..<20).map { "ad\(line)x\($0)" } }
    let now = Date()
    for (confidence, skipped) in [
      (AheadMark.Confidence.high, 1), (.medium, 1), (.low, 0),
    ] {
      let mark = AheadMark(
        kind: .ad, confidence: confidence, start: 100, end: 130,
        startWords: adWords.prefix(40).joined(separator: " "),
        endWords: adWords.suffix(40).joined(separator: " "))
      let file = AheadFile(
        writtenAt: now.timeIntervalSince1970,
        episodes: [
          AheadEntry(
            feed: "feed1", guid: "e1", title: "Title", marked: now.timeIntervalSince1970,
            ads: [mark])
        ])
      let layer = AheadScoreRow.layer(
        file, tuning: ShowTuning(), now: now, standingOn: ScoreEpisodeAds(),
        kept: ScoreEpisodeAds())
      let made = layer.apply(
        AdScoreInput(episode: episode, transcript: episode.transcript), soFar: [])
      XCTAssertEqual(made.count, skipped, "\(confidence)")
    }
  }

  // MARK: The stream replay and the rule

  func testTheStreamReplayHasALineForTheRow() throws {
    try fill()
    XCTAssertEqual(run(["--no-model", "--no-library", "--all", "--ahead", "--stream"]), 0, warned.joined())
    XCTAssertTrue(output.contains("Row \"\(rowName)\" as a stream"), output)
    XCTAssertNotNil(saved().last?.stream)
  }

  func testTheGoRuleIsTwentyMoreBreaksWithAtMostOneMoreSkipWithNoAd() {
    func totals(passed: Int, skips: Int) -> BarTotals {
      var bar = BarTotals()
      bar.breaks = 219
      bar.passed = passed
      bar.noAdSkips = skips
      return bar
    }
    let last = totals(passed: 140, skips: 20)
    XCTAssertTrue(AheadScoreRow.verdict(last: last, ahead: totals(passed: 160, skips: 21)).go)
    XCTAssertFalse(AheadScoreRow.verdict(last: last, ahead: totals(passed: 159, skips: 20)).go)
    XCTAssertFalse(AheadScoreRow.verdict(last: last, ahead: totals(passed: 170, skips: 22)).go)
    XCTAssertTrue(AheadScoreRow.verdict(last: last, ahead: totals(passed: 160, skips: 21)).line.hasPrefix("Verdict: go."))
  }

  func testTheOptionIsInTheUsageAndNeedsNoValue() {
    XCTAssertTrue(AdScoreCommand.usage.contains("[--ahead]"))
    if case .success(let options) = AdScoreCommand.parse(["x", "--ahead"]) {
      XCTAssertTrue(options.ahead)
    } else {
      XCTFail("--ahead did not parse")
    }
  }
}
