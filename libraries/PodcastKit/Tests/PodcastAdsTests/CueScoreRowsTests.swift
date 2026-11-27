import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// `podcast-teach score`: the rows "Plus opening lines" and "Plus filled holes", on made-up episodes
/// and on a tiny teaching folder.
final class CueScoreRowsTests: XCTestCase {
  private var folder: FolderWriter!
  private var printed: [String] = []
  private var warned: [String] = []
  private let marks = "Plus the Mac's marks from the night before"
  private let opening = "Plus opening lines"
  private let holes = "Plus filled holes"
  private let cueText = #"{"version": 1, "episodes": 5, "starts": ["now a word"], "returns": [], "shows": [], "common": [], "usual": []}"#

  override func setUpWithError() throws { folder = try FolderWriter() }
  override func tearDown() { folder.remove() }

  // MARK: The rows in a run

  /// One episode of 30 lines, one every 10 s. The ad is the lines 13 to 15 (120 to 150 s), which the
  /// Mac marked and made of invented words; the break to hear is 100 to 150 s, and the line at 100 s
  /// opens it with words the cue file knows.
  private func fill(cues: String?) throws {
    try folder.write(
      "episodes.json",
      #"{"version": 1, "episodes": [{"id": "e1", "feed": "https://one.test/rss", "show": "One", "title": "T1", "seconds": 300}]}"#
    )
    let text = (1...30).map { line -> String in
      let at = (line - 1) * 10
      let stamp = String(format: "[%d:%02d:%02d.0]", at / 3600, at % 3600 / 60, at % 60)
      let words =
        line == 11
        ? "now a word from tagzz"
        : (13...15).contains(line)
          ? (0..<20).map { "adline\(line)x\($0)" }.joined(separator: " ")
          : (0..<6).map { "talk\(line)x\($0)" }.joined(separator: " ")
      return "\(stamp) \(words)"
    }.joined(separator: "\n") + "\n"
    try folder.write("transcripts/e1.txt", text)
    try folder.write("labels/e1.json", labelJSON(segmentJSON(start: "120", end: "150")))
    try folder.write("labels-snapped/e1.json", labelJSON(segmentJSON(start: "100", end: "150")))
    if let cues { try folder.write("ad-cues.json", cues) }
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

  func testTheRowsComeLastAndTheOpeningLineMakesTheMarksRowPass() throws {
    try fill(cues: cueText)
    XCTAssertEqual(run(), 0, output + warned.joined())
    let rows = saved()
    XCTAssertEqual(rows.map(\.name).suffix(3), [marks, opening, holes])
    XCTAssertEqual(rows[rows.count - 3].bar?.passed, 0, "the marks start 20 s into the break")
    XCTAssertEqual(rows[rows.count - 2].bar?.passed, 1, "the opening line pulls the start back")
    XCTAssertEqual(rows[rows.count - 1].bar?.passed, 1)
    XCTAssertTrue(output.contains("\(opening): 1 of 1 breaks pass"), output)
    XCTAssertTrue(output.contains("\(holes): 1 of 1 breaks pass"), output)
    XCTAssertTrue(output.contains("ad-cues.json holds 1 opening and 0 return lines for every show"), output)
    XCTAssertTrue(output.contains("Why breaks fail in this row: no break fails."), output)
    XCTAssertTrue(
      output.contains("Verdict: no go. Both rows together: 1 more breaks pass than the row they stand on (10 more are needed)"), output)
  }

  func testWithoutTheMarksTheRowsStandOnTheLastFinderRow() throws {
    try fill(cues: cueText)
    XCTAssertEqual(run([]), 0, output + warned.joined())
    let rows = saved()
    XCTAssertEqual(rows.map(\.name).suffix(3), ["Plus per-show settings", opening, holes])
    XCTAssertEqual(rows.last?.bar?.passed, 0, "no finder of the phone finds invented words, so there is no skip to pull")
    XCTAssertTrue(output.contains("Verdict: no go. Both rows together: 0 more breaks pass"), output)
  }

  func testWithoutTheFileTheRowsAreLeftOutAndOneLineSaysSo() throws {
    try fill(cues: nil)
    XCTAssertEqual(run(), 0, output + warned.joined())
    XCTAssertEqual(saved().last?.name, marks)
    XCTAssertFalse(output.contains(opening))
    XCTAssertTrue(output.contains("left out, there is no ad-cues.json with cues"), output)
  }

  func testAFileThatHoldsNoCuesLeavesTheRowsOutToo() throws {
    try fill(cues: "not json")
    XCTAssertEqual(run(), 0)
    XCTAssertFalse(saved().contains { $0.name == opening })
  }

  func testTheStreamReplayHasANumberForEachRow() throws {
    try fill(cues: cueText)
    XCTAssertEqual(run(["--ahead", "--stream"]), 0, warned.joined())
    let rows = saved()
    XCTAssertNotNil(rows[rows.count - 2].stream)
    XCTAssertNotNil(rows[rows.count - 1].stream)
    XCTAssertTrue(output.contains("Row \"\(opening)\" as a stream"), output)
    XCTAssertTrue(output.contains("Row \"\(holes)\" as a stream"), output)
  }

  func testTheDumpStillHoldsTheLastFinderRow() throws {
    try fill(cues: cueText)
    let dump = folder.url.appendingPathComponent("dump.json").path
    XCTAssertEqual(run(["--ahead", "--dump", dump]), 0)
    let text = try String(contentsOfFile: dump, encoding: .utf8)
    XCTAssertFalse(text.contains("opening-lines"), text)
  }

  // MARK: The layers

  private let feed = "https://one.test/rss"

  private func episode(_ texts: [String]) -> TeachingEpisode {
    TeachingEpisode(
      id: "e1", feed: feed, show: "One", title: "T", transcript: makeTranscript(texts), truth: [],
      maybe: [], onShelf: true)
  }

  private func ad(
    _ start: Double, _ end: Double, _ confidence: AdConfidence = .sure, _ kind: AdKind = .ad
  ) -> FoundAd {
    FoundAd(start: start, end: end, kind: kind, advertiser: "", confidence: confidence, firstWords: "")
  }

  private func layers(
    onMarks: Bool, standingOn finders: ScoreEpisodeAds = ScoreEpisodeAds(), tuning: ShowTuning = ShowTuning(),
    kept: (ScoreEpisodeAds, ScoreEpisodeAds) = (ScoreEpisodeAds(), ScoreEpisodeAds())
  ) -> [AdScoreLayer] {
    CueScoreRows.layers(
      AdCues(data: Data(cueText.utf8)), tuning: tuning, onMarks: onMarks, standingOn: finders,
      kept: (kept.0, kept.1))
  }

  private var talking: [String] { (0..<20).map { "filler\($0)q" } }

  private func opened(_ text: String = "now a word from acme") -> TeachingEpisode {
    var texts = talking
    texts[5] = text  // 50 s
    return episode(texts)
  }

  private func result(_ layer: AdScoreLayer, _ episode: TeachingEpisode, soFar: [FoundAd]) -> [FoundAd] {
    layer.apply(AdScoreInput(episode: episode, transcript: episode.transcript), soFar: soFar)
  }

  func testTheFirstRowStandsOnTheFinderRowOrOnTheRowBeforeIt() {
    let finders = ScoreEpisodeAds()
    finders.put([ad(80, 100)], for: "e1")
    let one = opened()
    let onFinders = layers(onMarks: false, standingOn: finders)[0]
    let made = result(onFinders, one, soFar: [ad(150, 160)])
    XCTAssertEqual(made.map(\.start), [50])
    XCTAssertEqual(made.map(\.end), [100], "the row before is ignored, and the pulled stretch touches the ad")
    let onMarks = layers(onMarks: true, standingOn: finders)[0]
    XCTAssertEqual(result(onMarks, one, soFar: [ad(90, 110)]).map(\.end), [110])
    XCTAssertEqual(result(onMarks, one, soFar: [ad(90, 110)]).map(\.start), [50])
  }

  func testTheHeadOfAnEpisodeIsLeftAsItWas() {
    let one = opened()
    let head = AdScoreInput(episode: one, transcript: makeTranscript(Array(talking.prefix(10))))
    XCTAssertTrue(head.isHead)
    for layer in layers(onMarks: true) {
      XCTAssertEqual(layer.apply(head, soFar: [ad(80, 100)]), [ad(80, 100)])
    }
  }

  func testOnlySkipsOfAKindThePhoneSkipsAreHandedToTheFinder() {
    let one = opened()
    let rows = layers(onMarks: true)
    XCTAssertEqual(result(rows[0], one, soFar: [ad(80, 100, .guess)]), [ad(80, 100, .guess)])
    XCTAssertEqual(result(rows[0], one, soFar: [ad(80, 100, .unsure)]).map(\.start), [50])
    XCTAssertEqual(result(rows[0], one, soFar: [ad(80, 100, .sure, .credits)]), [ad(80, 100, .sure, .credits)])
  }

  func testAShowsSettingCanTurnTheFinderOffOrLeaveItAsking() {
    let one = opened()
    for level in ["off", "ask"] {
      let tuning = ShowTuning(
        text: #"{"version": 1, "default": {"finders": {"opening-lines": "\#(level)"}}, "shows": []}"#)
      let row = layers(onMarks: true, tuning: tuning)[0]
      XCTAssertEqual(result(row, one, soFar: [ad(80, 100)]), [ad(80, 100)], level)
    }
  }

  func testTheSecondRowFillsAHoleBetweenTheFirstRowsAds() {
    var texts = talking
    texts[3] = "zorbex is the thing"  // 30 s, in the first ad
    texts[5] = "zorbex smoothie tastes"  // 50 s, in the hole
    texts[7] = "zorbex again"  // 70 s, in the second ad
    let one = episode(texts)
    let kept = (ScoreEpisodeAds(), ScoreEpisodeAds())
    let rows = layers(onMarks: true, kept: kept)
    let soFar = [ad(30, 45), ad(65, 80)]
    XCTAssertEqual(result(rows[0], one, soFar: soFar), soFar, "no opening line")
    let made = result(rows[1], one, soFar: soFar)
    XCTAssertEqual(made.map(\.start), [30])
    XCTAssertEqual(made.map(\.end), [80])
    XCTAssertEqual(kept.1.ads(for: "e1"), made)
    XCTAssertEqual(kept.0.ads(for: "e1"), soFar)
  }

  func testTheGoRuleIsTenMoreBreaksWithAtMostTwoMoreSkipsWithNoAd() {
    func totals(passed: Int, skips: Int) -> BarTotals {
      var bar = BarTotals()
      bar.breaks = 219
      bar.passed = passed
      bar.noAdSkips = skips
      return bar
    }
    let last = totals(passed: 140, skips: 20)
    XCTAssertTrue(CueScoreRows.verdict(last: last, both: totals(passed: 150, skips: 22)).go)
    XCTAssertFalse(CueScoreRows.verdict(last: last, both: totals(passed: 149, skips: 20)).go)
    XCTAssertFalse(CueScoreRows.verdict(last: last, both: totals(passed: 160, skips: 23)).go)
    XCTAssertTrue(CueScoreRows.verdict(last: last, both: totals(passed: 150, skips: 20)).line.hasPrefix("Verdict: go."))
  }
}
