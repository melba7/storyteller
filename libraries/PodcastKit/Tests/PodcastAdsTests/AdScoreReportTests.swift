import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

final class AdScoreReportTests: XCTestCase {
  private func card(_ episodes: [TeachingEpisode], _ detect: @escaping (TeachingEpisode) -> [FoundAd]) -> Scorecard {
    AdScoreRun.run(episodes: episodes, habits: ShowHabits()) { episode, _ in detect(episode) }
  }

  func testReportLeadsWithTheThreeNumbers() {
    let episode = scoreEpisode(truth: [(10, 20, "sponsor"), (40, 50, "host_ask"), (70, 80, "sponsor")])
    let scored = card([episode]) { _ in [foundAd(10, 20), foundAd(90, 99)] }
    let text = AdScoreReport.text(
      scored, title: "Scorecard test", layers: [("Word rules", 0.25), ("Plus promo rules", 0.5)],
      previous: nil)
    let lines = text.components(separatedBy: "\n")
    XCTAssertEqual(lines[0], "Scorecard test")
    XCTAssertEqual(lines[2], "Ads caught: 1 of 3 (33%).")
    XCTAssertEqual(lines[3], "Ad time still heard: 20 s.")
    XCTAssertEqual(
      lines[4], "Show time cut by mistake: 9 s (12.9% of the show), in 1 wrong skip.")
    XCTAssertTrue(text.contains("Sponsor ads: caught 1 of 2 (50%), 10 s still heard."))
    XCTAssertTrue(text.contains("Host asks: caught 0 of 1 (0%)"))
    XCTAssertTrue(text.contains("Network and house promos: none marked."))
    XCTAssertTrue(text.contains("Intros and credits (not skipped unless you turn that on)"))
    XCTAssertTrue(text.contains("Openings: 1 ad in the first 30 seconds; the first look finds 1 of them (100%)."))
    XCTAssertTrue(text.contains("What each layer adds: Word rules 25%, Plus promo rules 50% (+25 points)."))
    XCTAssertFalse(text.contains("Since the last scorecard"))
  }

  func testZeroAdsReadsSensibly() {
    let scored = card([scoreEpisode()]) { _ in [] }
    let text = AdScoreReport.text(scored, title: "T", layers: [], previous: nil)
    XCTAssertTrue(text.contains("No marked ads in these episodes."))
    XCTAssertTrue(text.contains("Ad time still heard: 0 s."))
    XCTAssertFalse(text.contains("nan"))
    XCTAssertFalse(text.contains("What each layer adds"))
    let none = AdScoreReport.text(
      AdScoreRun.run(episodes: [], habits: ShowHabits()) { _, _ in [] }, title: "T", layers: [],
      previous: nil)
    XCTAssertTrue(none.contains("(0% of the show)"))
  }

  func testComparisonWithThePreviousRun() {
    let episode = scoreEpisode(truth: [(10, 20, "sponsor"), (40, 50, "sponsor")])
    var old = card([episode]) { _ in [] }.total
    old.caught = 0
    old.heardSeconds = 75
    let scored = card([episode]) { _ in [foundAd(10, 20)] }
    let text = AdScoreReport.text(
      scored, title: "T", layers: [], previous: ScorecardRun(at: 1, title: "old", total: old))
    XCTAssertTrue(
      text.contains(
        "Since the last scorecard: ads caught 50% (was 0%), ad time heard 10 s (was 1 min 15 s), show time cut 0 s (was 0 s)."))
  }

  func testOpeningsLine() {
    let episode = scoreEpisode(truth: [(2, 12, "sponsor")])
    let scored = AdScoreRun.run(episodes: [episode], habits: ShowHabits()) { _, transcript in
      transcript.duration < 100 ? [foundAd(0, 10)] : []
    }
    let text = AdScoreReport.text(scored, title: "T", layers: [], previous: nil)
    XCTAssertTrue(text.contains("Openings: 1 ad in the first 30 seconds; the first look finds 1 of them (100%)."))
  }

  func testTheTableShowsAtMost25ShowsWorstFirst() {
    let episodes = (1...30).map {
      scoreEpisode(id: "e\($0)", feed: "feed\($0)", show: "Show \($0)", truth: [(10, 10 + Double($0), "sponsor")])
    }
    let scored = card(episodes) { _ in [] }
    let text = AdScoreReport.text(scored, title: "T", layers: [], previous: nil)
    let rows = text.components(separatedBy: "\n").filter { $0.hasPrefix("  Show ") }
    XCTAssertEqual(rows.count, 25)
    XCTAssertTrue(rows[0].hasPrefix("  Show 30"))
    XCTAssertTrue(text.contains("and 5 more shows."))
  }

  func testTimeWords() {
    XCTAssertEqual(AdScoreReport.time(0), "0 s")
    XCTAssertEqual(AdScoreReport.time(59.4), "59 s")
    XCTAssertEqual(AdScoreReport.time(60), "1 min 00 s")
    XCTAssertEqual(AdScoreReport.time(185), "3 min 05 s")
  }

  // MARK: History

  private func run(_ at: Int64) -> ScorecardRun {
    ScorecardRun(at: at, title: "run \(at)", total: ScoreTotals())
  }

  private func file() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("scorecard-\(UUID().uuidString).json")
  }

  func testHistoryAppendsAndSaves() throws {
    let url = file()
    defer { try? FileManager.default.removeItem(at: url) }
    var history = ScorecardHistory.load(from: url)
    XCTAssertEqual(history.runs, [])
    history.append(run(1))
    history.append(run(2))
    try history.save(to: url)
    let again = ScorecardHistory.load(from: url)
    XCTAssertEqual(again.runs.map(\.at), [1, 2])
    XCTAssertEqual(again.version, 1)
  }

  func testHistoryKeepsTheNewest50() {
    var history = ScorecardHistory()
    for at in 1...55 { history.append(run(Int64(at))) }
    XCTAssertEqual(history.runs.count, 50)
    XCTAssertEqual(history.runs.first?.at, 6)
    XCTAssertEqual(history.runs.last?.at, 55)
  }

  func testADamagedHistoryStartsEmpty() throws {
    let url = file()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("{ not json".utf8).write(to: url)
    XCTAssertEqual(ScorecardHistory.load(from: url).runs, [])
    try Data("{\"version\": 9, \"runs\": []}".utf8).write(to: url)
    XCTAssertEqual(ScorecardHistory.load(from: url).runs, [])
  }
}
