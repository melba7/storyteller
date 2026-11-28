import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// `podcast-teach score --week`: the row "Plus this week's ad sounds", on a tiny teaching folder made
/// up here, with a made-up week finder (the real one, which keeps to the episodes of the week before,
/// is WeekSounds in PodcastAudioMatch and has its own tests).
final class WeekScoreRowTests: XCTestCase {
  private let text = "[0:00:00.0] hello and welcome\n[0:00:10.5] the weather is nice today\n[0:01:00.0] back to the show\n[0:01:30.0] and so it ends\n"
  private var folder: FolderWriter!
  private var printed: [String] = []
  private var warned: [String] = []
  private let rowName = "Plus this week's ad sounds"

  override func setUpWithError() throws { folder = try FolderWriter() }
  override func tearDown() { folder.remove() }

  /// Two episodes of two shows, each with one marked sponsor ad from 10 s to 40 s. Only the first
  /// has an MP3 file (it holds nothing: the made-up finders do not read it).
  private func fill() throws {
    try folder.write(
      "episodes.json",
      #"{"version": 1, "episodes": [{"id": "e1", "feed": "f1", "show": "One", "title": "T1", "file": "audio/e1.mp3"}, {"id": "e2", "feed": "f2", "show": "Two", "title": "T2"}]}"#
    )
    for id in ["e1", "e2"] {
      try folder.write("transcripts/\(id).txt", text)
      try folder.write("labels/\(id).json", labelJSON(segmentJSON(start: "10", end: "40")))
    }
    try folder.write("audio/e1.mp3", "not really audio")
  }

  /// A kit whose week finder finds the marked ad in whatever it is asked about, and says what it was.
  private func extras(_ calls: SoundCalls, finds: [ScoreSpan] = [ScoreSpan(start: 10, end: 40)]) -> ScoreExtras {
    let made = ScoreSoundKit(
      weekSounds: { url, episode in
        calls.ask("week \(url.lastPathComponent) \(episode)")
        return finds
      })
    return ScoreExtras(sounds: { _, _ in made })
  }

  private func run(_ extras: ScoreExtras, _ options: [String] = ["--no-model", "--no-library", "--all", "--week"])
    -> Int32
  {
    printed = []
    warned = []
    return AdScoreCommand.run(
      [folder.url.path] + options, extras: extras, out: { self.printed.append($0) },
      err: { self.warned.append($0) })
  }

  private var output: String { printed.joined(separator: "\n") }

  private func rows() -> [ScorecardRow] {
    ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json")).runs.last?.rows ?? []
  }

  func testTheRowIsThereOnlyWithTheFlagAndTheFinderIsAskedOnlyThen() throws {
    try fill()
    let calls = SoundCalls()
    XCTAssertEqual(run(extras(calls), ["--no-model", "--no-library", "--all"]), 0)
    XCTAssertFalse(rows().map(\.name).contains(rowName))
    XCTAssertEqual(calls.all, [])
    XCTAssertEqual(run(extras(calls)), 0, warned.joined())
    XCTAssertEqual(rows().last?.name, rowName)
    XCTAssertTrue(output.contains("\(rowName): 1 of 2 scored episodes"), output)
  }

  func testTheFinderIsAskedAboutTheEpisodesThatHaveAnMP3AndNoOthers() throws {
    try fill()
    let calls = SoundCalls()
    XCTAssertEqual(run(extras(calls)), 0)
    XCTAssertEqual(calls.all, ["week e1.mp3 e1"])
  }

  func testTheRowCatchesTheAdTheRowsBeforeItMissed() throws {
    try fill()
    XCTAssertEqual(run(extras(SoundCalls())), 0)
    let all = rows()
    let before = try XCTUnwrap(all.first { $0.name == "Plus per-show settings" })
    let week = try XCTUnwrap(all.last)
    XCTAssertEqual(week.name, rowName)
    XCTAssertEqual(before.total.caught, 0)
    XCTAssertGreaterThan(week.total.caught, 0)
    XCTAssertEqual(week.bar?.passed, 1)
  }

  func testTheRowsBeforeItAreTheSameWithTheFlag() throws {
    try fill()
    XCTAssertEqual(run(extras(SoundCalls()), ["--no-model", "--no-library", "--all"]), 0)
    let without = rows()
    XCTAssertEqual(run(extras(SoundCalls())), 0)
    let with = rows()
    XCTAssertEqual(with.dropLast().map(\.name), without.map(\.name))
    XCTAssertEqual(with.dropLast().map(\.total), without.map(\.total))
  }

  func testAWeekThatFindsNothingLeavesTheRowEqualToTheOneBefore() throws {
    try fill()
    XCTAssertEqual(run(extras(SoundCalls(), finds: [])), 0)
    let all = rows()
    XCTAssertEqual(all.last?.total, all[all.count - 2].total)
  }

  func testWithNoAudioCodeTheRowIsLeftOutAndTheReportSaysSo() throws {
    try fill()
    XCTAssertEqual(run(ScoreExtras()), 0)
    XCTAssertFalse(rows().map(\.name).contains(rowName))
    XCTAssertTrue(output.contains("\(rowName) is left out"), output)
  }

  func testWithNoMP3FileTheRowIsLeftOutAndTheReportSaysSo() throws {
    try fill()
    try folder.write(
      "episodes.json",
      #"{"version": 1, "episodes": [{"id": "e1", "feed": "f1", "show": "One", "title": "T1"}, {"id": "e2", "feed": "f2", "show": "Two", "title": "T2"}]}"#
    )
    XCTAssertEqual(run(extras(SoundCalls())), 0)
    XCTAssertFalse(rows().map(\.name).contains(rowName))
    XCTAssertTrue(output.contains("\(rowName) is left out"), output)
  }

  func testTheOptionIsInTheUsageAndNeedsNoValue() {
    XCTAssertTrue(AdScoreCommand.usage.contains("[--week]"))
    if case .success(let options) = AdScoreCommand.parse(["x", "--week"]) {
      XCTAssertTrue(options.week)
    } else {
      XCTFail("--week did not parse")
    }
  }

  func testTheStreamReplayHasTheRowToo() throws {
    try fill()
    XCTAssertEqual(
      run(extras(SoundCalls()), ["--no-model", "--no-library", "--all", "--week", "--stream"]), 0,
      warned.joined())
    XCTAssertNotNil(rows().last?.stream)
    XCTAssertTrue(output.contains("Row \"\(rowName)\" as a stream"), output)
  }

  // MARK: The verdict

  private func totals(passed: Int, skips: Int) -> BarTotals {
    var totals = BarTotals()
    totals.breaks = 100
    totals.passed = passed
    totals.noAdSkips = skips
    return totals
  }

  func testThreeMoreBreaksAndNoMoreWrongSkipsIsAGo() {
    XCTAssertTrue(WeekScoreRow.verdict(last: totals(passed: 50, skips: 4), week: totals(passed: 53, skips: 4)).go)
    XCTAssertTrue(WeekScoreRow.verdict(last: totals(passed: 50, skips: 4), week: totals(passed: 60, skips: 3)).go)
  }

  func testTwoMoreBreaksOrOneMoreWrongSkipIsNoGo() {
    XCTAssertFalse(WeekScoreRow.verdict(last: totals(passed: 50, skips: 4), week: totals(passed: 52, skips: 4)).go)
    let more = WeekScoreRow.verdict(last: totals(passed: 50, skips: 4), week: totals(passed: 60, skips: 5))
    XCTAssertFalse(more.go)
    XCTAssertTrue(more.line.hasPrefix("Verdict: no go. "), more.line)
    XCTAssertTrue(more.line.contains("1 more skips"), more.line)
  }
}
