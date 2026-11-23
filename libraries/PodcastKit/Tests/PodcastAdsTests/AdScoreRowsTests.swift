import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// `scorecard.json` with a row for every layer, and the report's new numbers.
final class AdScoreRowsTests: XCTestCase {
  /// A history file as the scorecard wrote it before rows and the two "heard" numbers existed.
  private let oldText = """
    {
      "runs" : [
        {
          "at" : 1700000000000,
          "title" : "Scorecard for Teaching: all 2 labelled episodes",
          "total" : {
            "adSeconds" : 120,
            "ads" : 6,
            "bySort" : {
              "host_ask" : { "ads" : 1, "caught" : 1, "heardSeconds" : 0, "seconds" : 10 },
              "intro_credits" : { "ads" : 0, "caught" : 0, "heardSeconds" : 0, "seconds" : 0 },
              "network_promo" : { "ads" : 1, "caught" : 0, "heardSeconds" : 10, "seconds" : 10 },
              "sponsor" : { "ads" : 4, "caught" : 3, "heardSeconds" : 23.5, "seconds" : 100 }
            },
            "caught" : 4,
            "cutSeconds" : 12.5,
            "episodes" : 2,
            "heardSeconds" : 33.5,
            "openingAds" : 1,
            "openingKnown" : 1,
            "showSeconds" : 3000,
            "shows" : 1,
            "wrongSkips" : 2
          }
        }
      ],
      "version" : 1
    }
    """

  private func file() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("rows-\(UUID().uuidString).json")
  }

  private func card(
    _ found: [FoundAd], feed: String = "feed1", show: String = "Show One"
  ) -> Scorecard {
    let episode = scoreEpisode(feed: feed, show: show, truth: [(20, 40, "sponsor")])
    return AdScoreRun.run(episodes: [episode], habits: ShowHabits()) { _, _ in found }
  }

  // MARK: Old files

  func testAScorecardFileFromBeforeRowsStillReads() throws {
    let url = file()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(oldText.utf8).write(to: url)
    var history = ScorecardHistory.load(from: url)
    XCTAssertEqual(history.runs.count, 1)
    let old = try XCTUnwrap(history.runs.first)
    XCTAssertEqual(old.at, 1_700_000_000_000)
    XCTAssertEqual(old.total.heardSeconds, 33.5)
    XCTAssertEqual(old.total.bySort["sponsor"]?.caught, 3)
    // The new numbers read as zero and there are no rows.
    XCTAssertEqual(old.total.heardBeforeSeconds, 0)
    XCTAssertEqual(old.total.heardAfterSeconds, 0)
    XCTAssertEqual(old.rows, [])
    // A new run is added after it, and both read back.
    let rows = [ScorecardRow(name: "Word rules", card: card([foundAd(24, 36)]))]
    history.append(ScorecardRun(at: 2, title: "new", rows: rows))
    try history.save(to: url)
    let again = ScorecardHistory.load(from: url)
    XCTAssertEqual(again.runs.map(\.at), [1_700_000_000_000, 2])
    XCTAssertEqual(again.runs.first, old)
    XCTAssertEqual(again.runs.last?.rows, rows)
  }

  func testTheFileTheCodeWritesNamesTheNewFieldsForTheMac() throws {
    let url = file()
    defer { try? FileManager.default.removeItem(at: url) }
    var history = ScorecardHistory()
    history.append(
      ScorecardRun(at: 1, title: "t", rows: [ScorecardRow(name: "Word rules", card: card([foundAd(24, 36)]))]))
    try history.save(to: url)
    let text = try String(contentsOf: url, encoding: .utf8)
    for key in ["\"rows\"", "\"name\"", "\"shows\"", "\"heardBeforeSeconds\"", "\"heardAfterSeconds\""] {
      XCTAssertTrue(text.contains(key), key)
    }
    XCTAssertEqual(ScorecardHistory.load(from: url).version, 1)
  }

  // MARK: Rows

  func testARunKeepsEveryRowsOwnTotalAndPerShowTotals() throws {
    let episodes = [
      scoreEpisode(id: "1", feed: "fa", show: "A", truth: [(20, 40, "sponsor")]),
      scoreEpisode(id: "2", feed: "fb", show: "B", truth: [(20, 40, "sponsor")]),
    ]
    let first = AdScoreRun.run(episodes: episodes, habits: ShowHabits()) { episode, _ in
      episode.id == "1" ? [foundAd(27, 40)] : []
    }
    let second = AdScoreRun.run(episodes: episodes, habits: ShowHabits()) { _, _ in [foundAd(20, 33)] }
    let run = ScorecardRun(
      at: 5, title: "t",
      rows: [ScorecardRow(name: "Word rules", card: first), ScorecardRow(name: "Plus X", card: second)])
    // The run's own total is the last row's, as before rows existed.
    XCTAssertEqual(run.total, second.total)
    XCTAssertEqual(run.rows.map(\.name), ["Word rules", "Plus X"])
    XCTAssertEqual(run.rows[0].total, first.total)
    XCTAssertEqual(run.rows[0].shows, first.shows)
    XCTAssertEqual(run.rows[1].shows.map(\.feed).sorted(), ["fa", "fb"])

    let url = file()
    defer { try? FileManager.default.removeItem(at: url) }
    var history = ScorecardHistory()
    history.append(run)
    try history.save(to: url)
    let back = try XCTUnwrap(ScorecardHistory.load(from: url).runs.first)
    XCTAssertEqual(back, run)
    // Show A's row 1 hears 7 seconds before the skip; show B's hears none (missed, not counted).
    let rowOne = back.rows.first?.shows.first { $0.feed == "fa" }?.total
    XCTAssertEqual(rowOne?.heardBeforeSeconds ?? -1, 7, accuracy: 1e-9)
    let rowOneB = back.rows.first?.shows.first { $0.feed == "fb" }?.total
    XCTAssertEqual(rowOneB?.heardBeforeSeconds ?? -1, 0, accuracy: 1e-9)
    XCTAssertEqual(rowOneB?.heardSeconds ?? -1, 20, accuracy: 1e-9)
    // Row 2 hears 7 seconds after the skip in each show.
    XCTAssertEqual(back.rows.last?.shows.map(\.total.heardAfterSeconds), [7, 7])
  }

  func testARunWithoutRowsHasAnEmptyTotalAndNoRows() {
    let run = ScorecardRun(at: 1, title: "t", rows: [])
    XCTAssertEqual(run.total, ScoreTotals())
    XCTAssertEqual(run.rows, [])
    let plain = ScorecardRun(at: 1, title: "t", total: ScoreTotals())
    XCTAssertEqual(plain.rows, [])
  }

  func testOnlyTheNewestRunsKeepTheirRows() {
    var history = ScorecardHistory()
    let rows = [ScorecardRow(name: "Word rules", card: card([foundAd(24, 36)]))]
    for at in 1...8 { history.append(ScorecardRun(at: Int64(at), title: "run \(at)", rows: rows)) }
    XCTAssertEqual(history.runs.count, 8)
    let kept = history.runs.map { !$0.rows.isEmpty }
    XCTAssertEqual(kept, [false, false, false, true, true, true, true, true])
    XCTAssertEqual(ScorecardHistory.mostRunsWithRows, 5)
    // The totals of the older runs stay.
    XCTAssertEqual(history.runs.first?.total, rows[0].total)
  }

  // MARK: The report

  func testTheReportPrintsTheTwoNewNumbersAndPerShowLines() {
    let scored = card([foundAd(24, 36)])
    let text = AdScoreReport.text(scored, title: "T", layers: [], previous: nil)
    let lines = text.components(separatedBy: "\n")
    // The three leading numbers stay where they were.
    XCTAssertEqual(lines[2], "Ads caught: 1 of 1 (100%).")
    XCTAssertEqual(lines[3], "Ad time still heard: 8 s.")
    XCTAssertTrue(lines[4].hasPrefix("Show time cut by mistake:"))
    XCTAssertEqual(
      lines[5], "Ads caught, ad time heard before the skip: 4 s, after the skip: 4 s.")
    XCTAssertTrue(
      lines.contains { $0.hasPrefix("  Show One") && $0.hasSuffix("heard 8 s, cut 0 s, caught ads heard before the skip 4 s, after it 4 s") },
      text)
  }

  func testTheLayerLineNeedsNumbersFromTheCaller() {
    let scored = card([foundAd(24, 36)])
    let without = AdScoreReport.text(
      scored, title: "T",
      results: [LayerResult(name: "Word rules", caughtShare: 1, cutSeconds: 0)], previous: nil)
    XCTAssertFalse(without.contains("by layer"))
    XCTAssertTrue(without.contains("What each layer adds: Word rules 100% caught, 0 s cut by mistake."))

    let better = card([foundAd(20, 35)])
    let with = AdScoreReport.text(
      better, title: "T",
      results: [LayerResult(name: "Word rules", total: scored.total), LayerResult(name: "Plus X", total: better.total)],
      previous: nil)
    XCTAssertTrue(
      with.contains(
        "Caught ads heard before and after the skips, by layer: Word rules 4 s before, 4 s after; Plus X 0 s before, 5 s after."),
      with)
    XCTAssertTrue(with.contains("What each layer adds: Word rules 100% caught, 0 s cut by mistake; Plus X 100% caught (+0 points), 0 s cut by mistake."), with)
  }

  func testALayerResultFromTotalsHasNoNaNWhenThereAreNoAds() {
    let result = LayerResult(name: "Empty", total: ScoreTotals())
    XCTAssertEqual(result.caughtShare, 0)
    XCTAssertEqual(result.cutSeconds, 0)
    XCTAssertEqual(result.heardBeforeSeconds, 0)
    XCTAssertEqual(result.heardAfterSeconds, 0)
  }
}
