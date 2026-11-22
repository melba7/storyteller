import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// Scorecard rules: kinds the listener keeps, what each layer cuts, the episode's length and the
/// library file used.
final class ScorecardRulesTests: XCTestCase {
  // MARK: Kinds the settings do not skip

  func testASkipOverCreditsTheListenerKeepsIsAMistake() {
    let episode = scoreEpisode(truth: [(0, 10, "intro_credits")])
    let over = AdScore.score(episode: episode, found: [foundAd(0, 10)])
    XCTAssertEqual(over.cutSeconds, 10, accuracy: 1e-9)
    XCTAssertEqual(over.wrongSkips, 1)
    XCTAssertEqual(AdScore.showSeconds(episode, AdSkipSettings()), 100, accuracy: 1e-9)
    // With credits switched on the same stretch is a counted ad, not a mistake.
    let on = AdScore.score(
      episode: episode, found: [foundAd(0, 10)], settings: AdSkipSettings(skipCredits: true))
    XCTAssertEqual(on.cutSeconds, 0, accuracy: 1e-9)
    XCTAssertEqual(on.wrongSkips, 0)
  }

  func testAPlugTheListenerKeepsIsAMistakeWhenSkipped() {
    let episode = scoreEpisode(truth: [(10, 20, "host_ask")])
    let score = AdScore.score(
      episode: episode, found: [foundAd(10, 20)], settings: AdSkipSettings(skipOwnPlugs: false))
    XCTAssertEqual(score.cutSeconds, 10, accuracy: 1e-9)
    XCTAssertEqual(score.wrongSkips, 1)
  }

  func testMaybeStretchesStayNeutral() {
    let episode = scoreEpisode(truth: [(10, 20, "sponsor")], maybe: [(30, 40, "sponsor")])
    let score = AdScore.score(episode: episode, found: [foundAd(30, 40)])
    XCTAssertEqual(score.cutSeconds, 0, accuracy: 1e-9)
    XCTAssertEqual(score.wrongSkips, 0)
  }

  // MARK: What each layer adds

  func testEachLayerShowsItsCutSecondsToo() {
    let episode = scoreEpisode(truth: [(10, 20, "sponsor")])
    let card = AdScoreRun.run(episodes: [episode], habits: ShowHabits()) { _, _ in
      [foundAd(10, 20), foundAd(50, 59)]
    }
    let text = AdScoreReport.text(
      card, title: "T",
      results: [
        LayerResult(name: "Word rules", caughtShare: 0.25, cutSeconds: 0),
        LayerResult(name: "Plus promo rules", caughtShare: 0.5, cutSeconds: 9),
      ], previous: nil)
    XCTAssertTrue(
      text.contains(
        "What each layer adds: Word rules 25% caught, 0 s cut by mistake; Plus promo rules 50% caught (+25 points), 9 s cut by mistake."),
      text)
  }

  // MARK: The episode's length

  private func writeFolder(seconds: String?) throws -> FolderWriter {
    let writer = try FolderWriter()
    let extra = seconds.map { ", \"seconds\": \($0)" } ?? ""
    try writer.write(
      "episodes.json",
      "{\"version\": 1, \"episodes\": [{\"id\": \"e\", \"feed\": \"f\", \"show\": \"s\", \"title\": \"t\"\(extra)}]}"
    )
    try writer.write("transcripts/e.txt", sampleText)
    try writer.write("labels/e.json", labelJSON(segmentJSON(start: "5", end: "10")))
    return writer
  }

  private func episode(seconds: String?) throws -> TeachingEpisode {
    let writer = try writeFolder(seconds: seconds)
    defer { writer.remove() }
    var notes: [String] = []
    return try XCTUnwrap(TeachingFolder.episodes(in: writer.url, notes: &notes).first)
  }

  func testTheEpisodesSecondsAreItsLengthWhenTheyAreAboveZero() throws {
    let known = try episode(seconds: "1800.5")
    XCTAssertEqual(known.episodeLength, 1800.5)
    XCTAssertEqual(known.transcript.duration, 1800.5)
  }

  func testWithoutUsableSecondsTheLengthIsTheLastLinesStart() throws {
    for seconds in [nil, "0", "-5", "\"90\"", "null"] {
      let item = try episode(seconds: seconds)
      XCTAssertEqual(item.episodeLength, 60, "seconds \(seconds ?? "missing")")
    }
  }

  // MARK: Which library file

  private func libraryJSON(who: String) -> String {
    let text = (0..<40).map { "word\($0)" }.joined(separator: " ")
    return
      "{\"version\": 1, \"ads\": [{\"feed\": \"f\", \"scope\": \"show\", \"sort\": \"sponsor\", \"who\": \"\(who)\", \"text\": \"\(text)\", \"length\": 30, \"seen\": 3}]}"
  }

  func testTheShelfScoreReadsTheLibraryWithoutShelfAdsWhenItExists() throws {
    let writer = try FolderWriter()
    defer { writer.remove() }
    try writer.write("ad-library.json", libraryJSON(who: "Full"))
    let before = TeachingFolder.library(in: writer.url, now: Date(), scoringShelf: true)
    XCTAssertEqual(before.file, "ad-library.json", "no score file yet")
    XCTAssertEqual(before.known.ads.first?.advertiser, "Full")
    try writer.write("ad-library-score.json", libraryJSON(who: "NoShelf"))
    let shelf = TeachingFolder.library(in: writer.url, now: Date(), scoringShelf: true)
    XCTAssertEqual(shelf.file, "ad-library-score.json")
    XCTAssertEqual(shelf.known.ads.first?.advertiser, "NoShelf")
    let all = TeachingFolder.library(in: writer.url, now: Date(), scoringShelf: false)
    XCTAssertEqual(all.file, "ad-library.json")
    XCTAssertEqual(all.known.ads.first?.advertiser, "Full")
  }

  func testThePrintedScorecardSaysWhichLibraryFileWasUsed() throws {
    let writer = try writeFolder(seconds: nil)
    defer { writer.remove() }
    try writer.write("shelf.json", "{\"version\": 1, \"episodes\": [\"e\"]}")
    try writer.write("ad-library.json", libraryJSON(who: "A"))
    try writer.write("ad-library-score.json", libraryJSON(who: "A"))
    var printed: [String] = []
    XCTAssertEqual(
      AdScoreCommand.run([writer.url.path], out: { printed.append($0) }, err: { _ in }), 0)
    XCTAssertTrue(printed.joined().contains("Library: ad-library-score.json"), printed.joined())
    printed = []
    XCTAssertEqual(
      AdScoreCommand.run([writer.url.path, "--all"], out: { printed.append($0) }, err: { _ in }), 0)
    XCTAssertTrue(printed.joined().contains("Library: ad-library.json"), printed.joined())
    printed = []
    XCTAssertEqual(
      AdScoreCommand.run(
        [writer.url.path, "--no-library"], out: { printed.append($0) }, err: { _ in }), 0)
    XCTAssertFalse(printed.joined().contains("Library:"))
  }
}
