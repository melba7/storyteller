import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// `podcast-teach score`: the row "Plus playbook lines", on a made-up episode and a tiny teaching
/// folder. The row is there only when the cue file holds phrases.
final class CueScorePlaybookRowTests: XCTestCase {
  private var folder: FolderWriter!
  private var printed: [String] = []
  private var warned: [String] = []
  private let holes = "Plus filled holes"
  private let playbook = "Plus playbook lines"
  private let feed = "https://one.test/rss"
  private let cueText = #"{"version": 1, "episodes": 5, "starts": [], "returns": [], "shows": [{"feed": "https://one.test/rss", "phrases": ["a word from", "mail bag time"]}], "common": [], "usual": []}"#

  override func setUpWithError() throws { folder = try FolderWriter() }
  override func tearDown() { folder.remove() }

  /// One episode of 30 lines, one every 10 s. The Mac marked 120 to 150 s, the break to hear is 100
  /// to 150 s, and the line at 100 s holds a phrase of the show's playbook.
  private func fill() throws {
    try folder.write(
      "episodes.json",
      #"{"version": 1, "episodes": [{"id": "e1", "feed": "https://one.test/rss", "show": "One", "title": "T1", "seconds": 300}]}"#
    )
    let text = (1...30).map { line -> String in
      let at = (line - 1) * 10
      let stamp = String(format: "[%d:%02d:%02d.0]", at / 3600, at % 3600 / 60, at % 60)
      let words =
        line == 11
        ? "and now a word from tagzz"
        : (13...15).contains(line)
          ? (0..<20).map { "adline\(line)x\($0)" }.joined(separator: " ")
          : (0..<6).map { "talk\(line)x\($0)" }.joined(separator: " ")
      return "\(stamp) \(words)"
    }.joined(separator: "\n") + "\n"
    try folder.write("transcripts/e1.txt", text)
    try folder.write("labels/e1.json", labelJSON(segmentJSON(start: "120", end: "150")))
    try folder.write("labels-snapped/e1.json", labelJSON(segmentJSON(start: "100", end: "150")))
    try folder.write("ad-cues.json", cueText)
  }

  private func run(_ extra: [String] = ["--ahead"]) -> Int32 {
    printed = []
    warned = []
    return AdScoreCommand.run(
      [folder.url.path, "--no-model", "--no-library", "--all", "--labels", "labels-snapped"] + extra,
      out: { self.printed.append($0) }, err: { self.warned.append($0) })
  }

  private var output: String { printed.joined(separator: "\n") }

  private func saved() -> [ScorecardRow] {
    ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json")).runs.last?.rows ?? []
  }

  func testTheRowComesAfterTheHolesAndThePhraseLineMakesTheBreakPass() throws {
    try fill()
    XCTAssertEqual(run(), 0, output + warned.joined())
    let rows = saved()
    XCTAssertEqual(rows.map(\.name).suffix(3), ["Plus opening lines", holes, playbook])
    XCTAssertEqual(rows[rows.count - 2].bar?.passed, 0, "the marks start 20 s into the break")
    XCTAssertEqual(rows[rows.count - 1].bar?.passed, 1, "the phrase line pulls the start back")
    XCTAssertTrue(output.contains("\(playbook): 1 of 1 breaks pass"), output)
    XCTAssertTrue(output.contains("It also holds 2 playbook phrases for 1 show."), output)
    XCTAssertTrue(
      output.contains("Verdict: no go. Both rows together: 0 more breaks pass than the row they stand on"),
      "the first verdict is still about the holes row: " + output)
    XCTAssertTrue(
      output.contains(
        "Playbook verdict: not kept. 1 more breaks pass than in \"\(holes)\" (4 more are needed), with 0 more skips with no ad (none more is allowed)."),
      output)
  }

  func testTheStreamReplayHasANumberForTheRow() throws {
    try fill()
    XCTAssertEqual(run(["--ahead", "--stream"]), 0, warned.joined())
    let rows = saved()
    XCTAssertNotNil(rows[rows.count - 1].stream)
    XCTAssertNotNil(rows[rows.count - 2].stream)
    XCTAssertTrue(output.contains("Row \"\(playbook)\" as a stream"), output)
  }

  // MARK: The layer

  private func ad(_ start: Double, _ end: Double, _ confidence: AdConfidence = .sure) -> FoundAd {
    FoundAd(start: start, end: end, kind: .ad, advertiser: "", confidence: confidence, firstWords: "")
  }

  private var episode: TeachingEpisode {
    var texts = (0..<20).map { "filler\($0)q" }
    texts[5] = "it is mail bag time"  // 50 s
    return TeachingEpisode(
      id: "e1", feed: feed, show: "One", title: "T", transcript: makeTranscript(texts), truth: [],
      maybe: [], onShelf: true)
  }

  private func layers(_ text: String, tuning: ShowTuning = ShowTuning(), playbook: ScoreEpisodeAds = ScoreEpisodeAds())
    -> [AdScoreLayer]
  {
    CueScoreRows.layers(
      AdCues(data: Data(text.utf8)), tuning: tuning, onMarks: true, standingOn: ScoreEpisodeAds(),
      kept: (ScoreEpisodeAds(), ScoreEpisodeAds()), playbook: playbook)
  }

  func testThereIsAThirdLayerOnlyWhenTheFileHoldsPhrases() {
    XCTAssertEqual(layers(cueText).map(\.name), ["Plus opening lines", holes, playbook])
    let none = #"{"version": 1, "starts": ["now a word"], "returns": [], "shows": [], "common": [], "usual": []}"#
    XCTAssertEqual(layers(none).map(\.name), ["Plus opening lines", holes])
  }

  func testTheLayerPullsTheSkipsOfTheRowBeforeItAndKeepsItsAds() {
    let kept = ScoreEpisodeAds()
    let row = layers(cueText, playbook: kept)[2]
    let one = episode
    let input = AdScoreInput(episode: one, transcript: one.transcript)
    let made = row.apply(input, soFar: [ad(80, 100)])
    XCTAssertEqual(made.map(\.start), [50])
    XCTAssertEqual(made.map(\.end), [100], "the pulled part touches the ad and is joined with it")
    XCTAssertEqual(kept.ads(for: "e1"), made)
    XCTAssertEqual(row.apply(input, soFar: [ad(80, 100, .guess)]), [ad(80, 100, .guess)], "not a skip of the phone")
    let head = AdScoreInput(episode: one, transcript: makeTranscript((0..<10).map { "filler\($0)q" }))
    XCTAssertEqual(row.apply(head, soFar: [ad(80, 100)]), [ad(80, 100)], "the head is left as it was")
  }

  func testTheOpeningLinesSettingTurnsTheLayerOff() {
    let tuning = ShowTuning(
      text: #"{"version": 1, "default": {"finders": {"opening-lines": "off"}}, "shows": []}"#)
    let one = episode
    let row = layers(cueText, tuning: tuning)[2]
    XCTAssertEqual(
      row.apply(AdScoreInput(episode: one, transcript: one.transcript), soFar: [ad(80, 100)]), [ad(80, 100)])
  }

  func testTheKeepRuleIsFourMoreBreaksAndNoMoreSkipsWithNoAd() {
    func totals(passed: Int, skips: Int) -> BarTotals {
      var bar = BarTotals()
      bar.breaks = 219
      bar.passed = passed
      bar.noAdSkips = skips
      return bar
    }
    let before = totals(passed: 140, skips: 20)
    XCTAssertTrue(CueScoreRows.playbookVerdict(holes: before, playbook: totals(passed: 144, skips: 20)).kept)
    XCTAssertTrue(CueScoreRows.playbookVerdict(holes: before, playbook: totals(passed: 150, skips: 18)).kept)
    XCTAssertFalse(CueScoreRows.playbookVerdict(holes: before, playbook: totals(passed: 143, skips: 20)).kept)
    XCTAssertFalse(CueScoreRows.playbookVerdict(holes: before, playbook: totals(passed: 150, skips: 21)).kept)
    XCTAssertTrue(
      CueScoreRows.playbookVerdict(holes: before, playbook: totals(passed: 146, skips: 19)).line
        .hasPrefix("Playbook verdict: kept. 6 more breaks pass"))
  }
}
