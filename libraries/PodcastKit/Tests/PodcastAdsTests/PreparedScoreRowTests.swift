import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// `podcast-teach score --prepared`: the row "Prepared copy", on a tiny teaching folder made up here.
final class PreparedScoreRowTests: XCTestCase {
  private var folder: FolderWriter!
  private var printed: [String] = []
  private var warned: [String] = []
  private let rowName = "Prepared copy"

  override func setUpWithError() throws { folder = try FolderWriter() }
  override func tearDown() { folder.remove() }

  private func transcript(_ tag: String) -> String {
    (1...30).map { line in
      let at = (line - 1) * 10
      let stamp = String(format: "[%d:%02d:%02d.0]", at / 3600, at % 3600 / 60, at % 60)
      return "\(stamp) " + (0..<6).map { "\(tag)talk\(line)x\($0)" }.joined(separator: " ")
    }.joined(separator: "\n") + "\n"
  }

  /// Two shows, one episode each, 300 s. e1 has an ad from 100 to 130 s, e2 one from 150 to 190 s.
  private func fill() throws {
    try folder.write(
      "episodes.json",
      #"{"version": 1, "episodes": [{"id": "e1", "feed": "https://one.test/rss", "show": "One", "title": "T1", "seconds": 300}, {"id": "e2", "feed": "https://two.test/rss", "show": "Two", "title": "T2", "seconds": 300}]}"#
    )
    try folder.write("transcripts/e1.txt", transcript("a"))
    try folder.write("transcripts/e2.txt", transcript("b"))
    try folder.write("labels/e1.json", labelJSON(segmentJSON(start: "100", end: "130")))
    try folder.write("labels/e2.json", labelJSON(segmentJSON(start: "150", end: "190")))
  }

  private func run(_ options: [String] = ["--no-model", "--no-library", "--all", "--prepared"]) -> Int32 {
    printed = []
    warned = []
    return AdScoreCommand.run(
      [folder.url.path] + options, out: { self.printed.append($0) }, err: { self.warned.append($0) })
  }

  private var output: String { printed.joined(separator: "\n") }

  private func row() -> ScorecardRow? {
    ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json")).runs.last?.rows
      .first { $0.name == rowName }
  }

  func testTheRowIsThereOnlyWithTheFlag() throws {
    try fill()
    XCTAssertEqual(run(["--no-model", "--no-library", "--all"]), 0)
    XCTAssertNil(row())
    XCTAssertFalse(output.contains(rowName), output)
    XCTAssertEqual(run(), 0, warned.joined())
    XCTAssertNotNil(row())
    XCTAssertTrue(output.contains("\(rowName): 2 scored episodes"), output)
  }

  func testAHighAndAMediumMarkAreSkippedAtTheirOwnTimesAndPassTheirBreaks() throws {
    try fill()
    try folder.write("labels/e2.json", labelJSON(segmentJSON(start: "150", end: "190", confidence: "medium")))
    XCTAssertEqual(run(), 0, warned.joined())
    let bar = try XCTUnwrap(row()?.bar)
    XCTAssertEqual(bar.breaks, 2)
    XCTAssertEqual(bar.passed, 2)
    XCTAssertEqual(bar.noAdSkips, 0)
    XCTAssertTrue(output.contains("2 ads that skip, 0 questions"), output)
    XCTAssertTrue(output.contains("Why breaks fail in this row: no break fails."), output)
  }

  func testNothingOfThePhonesOwnFindersIsAddedToIt() throws {
    try fill()
    XCTAssertEqual(run(), 0)
    let earlier = try XCTUnwrap(
      ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json")).runs.last?.rows
        .first { $0.name == "Plus per-show settings" })
    XCTAssertEqual(earlier.bar?.passed, 0, "no finder finds invented words")
    XCTAssertEqual(row()?.bar?.passed, 2)
  }

  func testALowMarkOnlyAsksSoItPassesNoBreak() throws {
    try fill()
    try folder.write("labels/e1.json", labelJSON(segmentJSON(start: "100", end: "130", confidence: "low")))
    XCTAssertEqual(run(), 0)
    XCTAssertEqual(row()?.bar?.passed, 1, "only e2's high mark passes")
    XCTAssertTrue(output.contains("1 ads that skip, 1 questions"), output)
  }

  func testAnIntroOrCreditsLabelIsNotSkipped() throws {
    try fill()
    try folder.write("labels/e1.json", labelJSON(segmentJSON(start: "100", end: "130", sort: "intro_credits")))
    XCTAssertEqual(run(), 0)
    XCTAssertTrue(output.contains("1 marks, 1 ads that skip"), output)
    XCTAssertEqual(row()?.bar?.noAdSkips, 0)
  }

  func testTheSnappedLabelsGiveTheTimesWhenTheRunScoresThem() throws {
    try fill()
    try folder.write("labels-snapped/e1.json", labelJSON(segmentJSON(start: "101", end: "131")))
    try folder.write("labels-snapped/e2.json", labelJSON(segmentJSON(start: "150", end: "190")))
    XCTAssertEqual(run(["--no-model", "--no-library", "--all", "--prepared", "--labels", "labels-snapped"]), 0)
    XCTAssertEqual(row()?.bar?.passed, 2)
  }

  func testAnEpisodeWithNoLabelIsNotScoredAndSoNotCounted() throws {
    try fill()
    try folder.write("transcripts/e3.txt", transcript("c"))
    try folder.write(
      "episodes.json",
      #"{"version": 1, "episodes": [{"id": "e1", "feed": "https://one.test/rss", "show": "One", "title": "T1", "seconds": 300}, {"id": "e2", "feed": "https://two.test/rss", "show": "Two", "title": "T2", "seconds": 300}, {"id": "e3", "feed": "https://three.test/rss", "show": "Three", "title": "T3", "seconds": 300}]}"#
    )
    XCTAssertEqual(run(), 0)
    XCTAssertTrue(output.contains("\(rowName): 2 scored episodes"), output)
    XCTAssertEqual(row()?.bar?.breaks, 2)
  }

  func testTheOptionIsInTheUsageAndNeedsNoValue() {
    XCTAssertTrue(AdScoreCommand.usage.contains("[--prepared]"))
    if case .success(let options) = AdScoreCommand.parse(["x", "--prepared"]) {
      XCTAssertTrue(options.prepared)
    } else {
      XCTFail("--prepared did not parse")
    }
  }

  func testTheOtherRowsAreTheSameWithTheFlagAndTheTotalIsTheLastFinderRow() throws {
    try fill()
    XCTAssertEqual(run(["--no-model", "--no-library", "--all", "--ahead"]), 0)
    let without = ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json")).runs.last
    XCTAssertEqual(run(["--no-model", "--no-library", "--all", "--ahead", "--prepared"]), 0)
    let with = try XCTUnwrap(
      ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json")).runs.last)
    XCTAssertEqual(with.rows.dropLast().map(\.name), without?.rows.map(\.name))
    XCTAssertEqual(with.rows.dropLast().map(\.total), without?.rows.map(\.total))
    XCTAssertEqual(with.total, without?.total)
    XCTAssertEqual(with.rows.last?.name, rowName)
  }

  func testALateAdPassesWhenTheStatedLengthIsShorterThanTheRealCopy() throws {
    // episodes.json says 200 s, but the transcript runs to 300 s: the copy is as long as its audio.
    try folder.write(
      "episodes.json",
      #"{"version": 1, "episodes": [{"id": "e1", "feed": "https://one.test/rss", "show": "One", "title": "T1", "seconds": 200}]}"#
    )
    try folder.write("transcripts/e1.txt", transcript("a"))
    try folder.write("labels/e1.json", labelJSON(segmentJSON(start: "250", end: "290")))
    XCTAssertEqual(run(), 0, warned.joined())
    XCTAssertEqual(row()?.bar?.breaks, 1)
    XCTAssertEqual(row()?.bar?.passed, 1, "the mark is not cut to the stated length")
  }
}
