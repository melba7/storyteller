import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// The scorecard's Apple row follows the phone: Apple's answers go through the per-show settings
/// before they are joined, so under the built-in default (Apple's model asks) the row is the row
/// before it, and a show set to skip gets what it got before. A second row keeps what every show
/// would get if it skipped, which is what the Mac's settings step reads.
final class AppleRowTuningTests: XCTestCase {
  private let text = "[0:00:00.0] hello and welcome\n[0:00:10.5] the weather is nice today\n[0:01:00.0] back to the show\n[0:01:30.0] and so it ends\n"
  private var folder: FolderWriter!
  private var printed: [String] = []

  override func setUpWithError() throws { folder = try FolderWriter() }
  override func tearDown() { folder.remove() }

  /// Two episodes of two shows ("fe1" and "fe2") with an ad marked from 10 to 40 s.
  private func fill() throws {
    let ids = ["e1", "e2"]
    let entries = ids.map { "{\"id\": \"\($0)\", \"feed\": \"f\($0)\", \"show\": \"S\($0)\", \"title\": \"T\"}" }
    try folder.write("episodes.json", "{\"version\": 1, \"episodes\": [\(entries.joined(separator: ","))]}")
    for id in ids {
      try folder.write("transcripts/\(id).txt", text)
      try folder.write("labels/\(id).json", labelJSON(segmentJSON(start: "10", end: "40")))
    }
    // Apple's model finds the marked ad (to within half a second at the start), in both episodes,
    // so its answer passes the bar where nothing else found the break.
    var saved = AppleAnswers(model: "fake-model 7")
    for id in ids {
      saved.episodes[id] = .init(
        ads: [.init(start: 10.5, end: 40, kind: .ad, confidence: .sure)], refusedPieces: 0, seconds: 1)
    }
    try saved.save(in: folder.url)
  }

  private func settings(_ text: String) throws { try folder.write("show-settings.json", text) }

  private func score(_ options: [String] = []) -> Int32 {
    printed = []
    return AdScoreCommand.run(
      [folder.url.path, "--no-model", "--all"] + options, out: { self.printed.append($0) },
      err: { _ in })
  }

  private var output: String { printed.joined(separator: "\n") }

  private func rows() -> [ScorecardRow] {
    ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json")).runs.last?.rows ?? []
  }

  private func row(_ name: String) throws -> ScorecardRow {
    try XCTUnwrap(rows().first { $0.name == name }, "no row \(name) in \(rows().map(\.name))")
  }

  /// The row that comes just before Apple's.
  private func rowBeforeApple() throws -> ScorecardRow {
    let all = rows()
    let at = try XCTUnwrap(all.firstIndex { $0.name == AppleScoreRow.name })
    return all[at - 1]
  }

  private func same(_ a: ScorecardRow, _ b: ScorecardRow, _ message: String = "") {
    XCTAssertEqual(a.total, b.total, message)
    XCTAssertEqual(a.shows, b.shows, message)
    XCTAssertEqual(a.bar, b.bar, message)
  }

  // MARK: The built-in default

  func testUnderTheBuiltInDefaultTheAppleRowIsTheRowBeforeIt() throws {
    try fill()
    XCTAssertEqual(score(), 0)
    let before = try rowBeforeApple()
    XCTAssertEqual(before.name, ScoreRows.settings)
    same(try row(AppleScoreRow.name), before)
    // Apple's answers are not nothing: if every show skipped them the row would change.
    let all = try row(AppleScoreRow.skippingName)
    XCTAssertNotEqual(all.total.heardSeconds, before.total.heardSeconds)
    XCTAssertGreaterThan(all.bar?.passed ?? 0, before.bar?.passed ?? 0)
  }

  func testWithNoSettingsFileTheBuiltInDefaultAsksToo() throws {
    try fill()
    XCTAssertEqual(score(), 0)
    XCTAssertTrue(output.contains("no show-settings.json"), output)
    XCTAssertTrue(output.contains("2 ask and 0 skip"), output)
  }

  func testTheReportSaysHowManyAnswersAskedAndSkipped() throws {
    try fill()
    try settings(#"{"version": 1, "shows": [{"feed": "fe1", "finders": {"apple-model": "skip"}}]}"#)
    XCTAssertEqual(score(), 0)
    XCTAssertTrue(output.contains("1 ask and 1 skip"), output)
    XCTAssertTrue(output.contains("Apple's answers"), output)
    try settings(#"{"version": 1, "default": {"finders": {"apple-model": "off"}}}"#)
    XCTAssertEqual(score(), 0)
    XCTAssertTrue(output.contains("0 ask and 0 skip"), output)
    XCTAssertTrue(output.contains("2 are dropped"), output)
  }

  // MARK: A show set to skip

  func testAShowSetToSkipGetsWhatItGotBefore() throws {
    try fill()
    try settings(#"{"version": 1, "shows": [{"feed": "fe1", "finders": {"apple-model": "skip"}}]}"#)
    XCTAssertEqual(score(), 0)
    let before = try rowBeforeApple()
    let tuned = try row(AppleScoreRow.name)
    XCTAssertNotEqual(tuned.total, before.total)
    XCTAssertGreaterThan(tuned.bar?.passed ?? 0, before.bar?.passed ?? 0)
    let all = try row(AppleScoreRow.skippingName)
    XCTAssertLessThan(tuned.total.heardSeconds, before.total.heardSeconds)
    XCTAssertGreaterThan(tuned.total.heardSeconds, all.total.heardSeconds, "the other show still asks")
    // The skipping show's own totals are what every show gets when all of them skip.
    let skipper = try XCTUnwrap(tuned.shows.first { $0.feed == "fe1" })
    XCTAssertEqual(skipper, all.shows.first { $0.feed == "fe1" })
    let asker = try XCTUnwrap(tuned.shows.first { $0.feed == "fe2" })
    XCTAssertEqual(asker, before.shows.first { $0.feed == "fe2" })
  }

  func testTheDefaultBlockCanLetEveryShowSkipAndThenTheTwoAppleRowsAgree() throws {
    try fill()
    try settings(#"{"version": 1, "default": {"finders": {"apple-model": "skip"}}}"#)
    XCTAssertEqual(score(), 0)
    same(try row(AppleScoreRow.name), try row(AppleScoreRow.skippingName))
    XCTAssertTrue(output.contains("0 ask and 2 skip"), output)
  }

  func testASortThatOnlyAsksStillMovesAnAnswerOutOfTheSkips() throws {
    try fill()
    try settings(#"{"version": 1, "default": {"finders": {"apple-model": "skip"}}}"#)
    XCTAssertEqual(score(), 0)
    let skipping = try row(AppleScoreRow.name)
    try settings(
      #"{"version": 1, "default": {"finders": {"apple-model": "skip"}, "sorts": {"sponsor": "ask"}}}"#)
    XCTAssertEqual(score(), 0)
    same(try row(AppleScoreRow.name), try rowBeforeApple(), "the sponsor sort asks, so nothing skips")
    XCTAssertNotEqual(skipping.total, try row(AppleScoreRow.name).total)
  }

  // MARK: The second row and the shows' bars

  func testTheSkippingRowKeepsAppleAsItWasForTheSettingsStep() throws {
    try fill()
    XCTAssertEqual(score(), 0)
    let names = rows().map(\.name)
    XCTAssertEqual(
      Array(names.suffix(2)), [AppleScoreRow.name, AppleScoreRow.skippingName],
      "the phone's row first, then the what-if row")
    XCTAssertTrue(output.contains(AppleScoreRow.skippingName), output)
  }

  func testEachShowOfARowKeepsItsOwnBarThatAddsUpToTheRowsBar() throws {
    try fill()
    XCTAssertEqual(score(), 0)
    for each in rows() {
      let bars = each.shows.compactMap(\.bar)
      XCTAssertEqual(bars.count, each.shows.count, each.name)
      XCTAssertEqual(bars.map(\.breaks).reduce(0, +), each.bar?.breaks, each.name)
      XCTAssertEqual(bars.map(\.passed).reduce(0, +), each.bar?.passed, each.name)
      XCTAssertEqual(bars.map(\.noAdSkips).reduce(0, +), each.bar?.noAdSkips, each.name)
    }
  }

  func testAScorecardSavedBeforeTheShowsHadABarStillReads() throws {
    let old = #"{"feed": "f", "show": "S", "total": {"episodes": 1, "shows": 1, "ads": 0, "caught": 0, "adSeconds": 0, "heardSeconds": 0, "cutSeconds": 0, "showSeconds": 0, "wrongSkips": 0, "bySort": {}, "openingAds": 0, "openingKnown": 0}}"#
    let show = try JSONDecoder().decode(ShowScore.self, from: Data(old.utf8))
    XCTAssertNil(show.bar)
  }

  // MARK: The stream block

  func testTheStreamBlockSaysWhichEpisodesWaitedForTheModel() throws {
    try fill()
    XCTAssertEqual(score(["--stream"]), 0)
    XCTAssertTrue(output.contains("waits in 0 of 2 episodes"), output)
    try settings(#"{"version": 1, "shows": [{"feed": "fe1", "finders": {"apple-model": "skip"}}]}"#)
    XCTAssertEqual(score(["--stream"]), 0)
    XCTAssertTrue(output.contains("waits in 1 of 2 episodes"), output)
    XCTAssertNotNil(try row(AppleScoreRow.name).stream)
  }

  func testUnderTheDefaultTheAppleRowsStreamNumbersAreTheRowBeforesToo() throws {
    try fill()
    XCTAssertEqual(score(["--stream"]), 0)
    let before = try rowBeforeApple()
    XCTAssertEqual(try row(AppleScoreRow.name).stream, before.stream)
  }
}
