import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// The bar in `podcast-teach score` (its block, its saved rows, `--dump`, `--exam`) and in
/// `podcast-teach agree`, on a small made-up teaching folder.
final class AdBarCommandTests: XCTestCase {
  private let text = "[0:00:00.0] hello and welcome\n[0:00:10.5] the weather is nice today\n[0:01:00.0] back to the show\n[0:01:30.0] and so it ends\n"
  private var folder: FolderWriter!
  private var printed: [String] = []
  private var warned: [String] = []

  override func setUpWithError() throws { folder = try FolderWriter() }
  override func tearDown() { folder.remove() }

  /// Episodes e1 and e2, each with one sponsor ad from 10 s to 40 s that plain talk never finds.
  private func fill(ids: [String] = ["e1", "e2"]) throws {
    let entries = ids.map { "{\"id\": \"\($0)\", \"feed\": \"f\($0)\", \"show\": \"S\($0)\", \"title\": \"T\"}" }
    try folder.write("episodes.json", "{\"version\": 1, \"episodes\": [\(entries.joined(separator: ","))]}")
    for id in ids {
      try folder.write("transcripts/\(id).txt", text)
      try folder.write("labels/\(id).json", labelJSON(segmentJSON(start: "10", end: "40")))
    }
  }

  private func score(_ options: [String] = ["--all"]) -> Int32 {
    printed = []
    warned = []
    return AdScoreCommand.run(
      [folder.url.path, "--no-model"] + options, out: { self.printed.append($0) },
      err: { self.warned.append($0) })
  }

  private var output: String { printed.joined(separator: "\n") }

  private func lastRun() -> ScorecardRun? {
    ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json")).runs.last
  }

  func testTheBarBlockFollowsTheScorecardAndEveryRowCarriesTheBar() throws {
    try fill()
    XCTAssertEqual(score(), 0)
    XCTAssertTrue(output.contains("The bar: an ad break passes when it is skipped with no tap"), output)
    XCTAssertTrue(output.contains("Why breaks fail in the last row: missed 2."), output)
    XCTAssertTrue(output.contains("First 3 minutes: 0 of 2 pass. Later: 0 of 0 pass."), output)
    let bars = lastRun()?.rows.map(\.bar) ?? []
    XCTAssertEqual(bars.count, 4)
    for bar in bars {
      XCTAssertEqual(bar?.breaks, 2)
      XCTAssertEqual(bar?.count(.missed), 2)
    }
  }

  func testARowSavedWithoutTheBarStillLoadsAndANewOneRoundTrips() throws {
    let old = """
      {"name": "Word rules", "total": {"episodes": 1, "shows": 1, "ads": 1, "caught": 1, "adSeconds": 10, "heardSeconds": 0, "cutSeconds": 0, "showSeconds": 90, "wrongSkips": 0, "bySort": {}, "openingAds": 0, "openingKnown": 0}, "shows": []}
      """
    let row = try JSONDecoder().decode(ScorecardRow.self, from: Data(old.utf8))
    XCTAssertNil(row.bar)
    var bar = BarTotals()
    bar.breaks = 3
    bar.passed = 2
    bar.causes["missed"] = 1
    bar.noAdSeconds = 12.5
    let kept = ScorecardRow(name: "x", total: row.total, shows: [], bar: bar)
    let again = try JSONDecoder().decode(ScorecardRow.self, from: JSONEncoder().encode(kept))
    XCTAssertEqual(again, kept)
    XCTAssertFalse(String(decoding: try JSONEncoder().encode(row), as: UTF8.self).contains("bar"))
  }

  func testDumpHoldsTheLastRowsAdsAndTheMarksButNoText() throws {
    try fill()
    let file = folder.url.appendingPathComponent("dump.json")
    XCTAssertEqual(score(["--all", "--dump", file.path]), 0)
    let list = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
    XCTAssertEqual(list.count, 2)
    XCTAssertEqual(Set(list[0].keys), ["id", "feed", "show", "duration", "found", "truth", "maybe"])
    XCTAssertEqual(list[0]["id"] as? String, "e1")
    let truth = try XCTUnwrap(list[0]["truth"] as? [[String: Any]])
    XCTAssertEqual(truth.first?["sort"] as? String, "sponsor")
    XCTAssertEqual(truth.first?["end"] as? Double, 40)
    XCTAssertFalse(String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("weather"))
  }

  func testDumpThatCannotBeWrittenIsAnErrorWithExitCodeTwo() throws {
    try fill()
    XCTAssertEqual(score(["--all", "--dump", folder.url.appendingPathComponent("no/such/dir/d.json").path]), 2)
    XCTAssertTrue(warned.joined().contains("The dump could not be written"), warned.joined())
  }

  // MARK: The sealed exam

  func testExamEpisodesAreInvisibleUnlessAskedFor() throws {
    try fill(ids: ["e1", "e2", "e3"])
    try folder.write("exam.json", "{\"episodes\": [\"e3\"]}")
    XCTAssertEqual(score(), 0)
    XCTAssertEqual(lastRun()?.total.episodes, 2)
    XCTAssertFalse(output.contains("sealed exam"))
    XCTAssertEqual(score(), 0)
    XCTAssertEqual(lastRun()?.rows.first?.bar?.breaks, 2)
  }

  func testExamRunScoresOnlyTheExamAndNamesItInTheTitle() throws {
    try fill(ids: ["e1", "e2", "e3"])
    try folder.write("exam.json", "{\"episodes\": [\"e3\"]}")
    XCTAssertEqual(score(["--exam"]), 0)
    XCTAssertEqual(lastExam()?.total.episodes, 1)
    XCTAssertTrue(lastExam()?.title.contains("sealed exam") == true, lastExam()?.title ?? "")
    XCTAssertEqual(lastExam()?.rows.first?.bar?.breaks, 1)
  }

  func testExamRunReadsTheScoreLibraryLikeTheShelfDoes() throws {
    try fill(ids: ["e1", "e2"])
    try folder.write("exam.json", "{\"episodes\": [\"e2\"]}")
    let words = (0..<40).map { "word\($0)" }.joined(separator: " ")
    let library =
      "{\"version\": 1, \"ads\": [{\"feed\": \"f\", \"scope\": \"show\", \"sort\": \"sponsor\", \"who\": \"A\", \"text\": \"\(words)\", \"length\": 30, \"seen\": 3}]}"
    try folder.write("ad-library.json", library)
    try folder.write("ad-library-score.json", library)
    XCTAssertEqual(score(["--exam"]), 0)
    XCTAssertTrue(output.contains("Library: ad-library-score.json"), output)
    XCTAssertEqual(score(["--all"]), 0)
    XCTAssertTrue(output.contains("Library: ad-library.json"), output)
  }

  func testWithNoExamFileOrADamagedOne() throws {
    try fill()
    XCTAssertEqual(score(["--exam"]), 2)
    try folder.write("exam.json", "{broken")
    XCTAssertEqual(score(), 2)
    XCTAssertTrue(warned.joined().contains("exam.json"), warned.joined())
  }

  // MARK: agree

  func testAgreeScoresTheBarBothWaysOverTheEpisodesMarkedTwice() throws {
    try fill(ids: ["e1", "e2", "e3"])
    try folder.write("labels-second/e1.json", labelJSON(segmentJSON(start: "10", end: "40")))
    try folder.write("labels-second/e2.json", labelJSON(segmentJSON(start: "10", end: "25")))
    var said: [String] = []
    XCTAssertEqual(
      AdAgreeCommand.run([folder.url.path], out: { said.append($0) }, err: { _ in }), 0)
    let all = said.joined(separator: "\n")
    XCTAssertTrue(all.contains("2 episodes are marked in both"), all)
    XCTAssertTrue(all.contains("labels as truth, labels-second as the skips: 2 breaks, 1 pass (50.0%)."), all)
    XCTAssertTrue(all.contains("labels-second as truth, labels as the skips: 2 breaks, 1 pass (50.0%)."), all)
    XCTAssertTrue(all.contains("Mean of the two rates: 50.0%."), all)
    XCTAssertTrue(all.contains("the most any finder can score"), all)
  }

  func testAgreeWithNoEpisodeMarkedTwiceSaysSoAndExitsZero() throws {
    try fill()
    var said: [String] = []
    XCTAssertEqual(
      AdAgreeCommand.run([folder.url.path, "--second", "other"], out: { said.append($0) }, err: { _ in }), 0)
    XCTAssertTrue(said.joined().contains("No episode"), said.joined())
  }

  // MARK: The sealed exam, the second round

  func testPlainRunWithoutAllLeavesTheExamOutOfTheScoreAndOutOfWhatTeaches() throws {
    // Three episodes of one show with the same plug. e1 is the exam, e3 is the shelf.
    let plug = Speech.plug(40)
    try folder.write(
      "episodes.json",
      "{\"version\": 1, \"episodes\": [{\"id\": \"e1\", \"feed\": \"f1\", \"show\": \"One\", \"title\": \"A\"},"
        + "{\"id\": \"e2\", \"feed\": \"f1\", \"show\": \"One\", \"title\": \"B\"},"
        + "{\"id\": \"e3\", \"feed\": \"f1\", \"show\": \"One\", \"title\": \"C\"}]}")
    try folder.write("shelf.json", "{\"version\": 1, \"episodes\": [\"e3\"]}")
    for (id, at, tag) in [("e1", 400, "a"), ("e2", 500, "b"), ("e3", 900, "c")] {
      let words = Speech.episode(tag: tag, total: 1200, plugs: [(at, plug)])
      let lines = Speech.lines(words).map { line -> String in
        let seconds = Int(line.start)
        return String(format: "[%d:%02d:%02d.0] ", seconds / 3600, seconds / 60 % 60, seconds % 60)
          + line.text
      }
      try folder.write("transcripts/\(id).txt", lines.joined(separator: "\n") + "\n")
      try folder.write(
        "labels/\(id).json", labelJSON(segmentJSON(start: "\(at / 2)", end: "\(at / 2 + 20)")))
    }
    func repeated(_ exam: String) -> (episodes: Int, right: Double) {
      try? folder.write("exam.json", "{\"episodes\": [\(exam)]}")
      XCTAssertEqual(score(["--no-library"]), 0)
      let run = lastRun()
      let total = run?.rows.first { $0.name == ScoreRows.repeatedWords }?.total
      return (run?.total.episodes ?? -1, (total?.adSeconds ?? 0) - (total?.heardSeconds ?? 0))
    }
    // With e2 and e1 free to teach, the plug of e3 is found; with e1 and e2 both sealed, nothing
    // is left to teach from and nothing is found.
    let open = repeated("\"e1\"")
    XCTAssertEqual(open.episodes, 1)
    XCTAssertEqual(open.right, 20, accuracy: 5)
    let sealed = repeated("\"e1\", \"e2\"")
    XCTAssertEqual(sealed.episodes, 1)
    XCTAssertEqual(sealed.right, 0, accuracy: 5)
    XCTAssertFalse(output.contains("sealed exam"))
  }

  func testExamRunScoresTheExamAndNothingElse() throws {
    try fill(ids: ["e1", "e2", "e3", "e4"])
    try folder.write("exam.json", "{\"episodes\": [\"e3\", \"e4\"]}")
    XCTAssertEqual(score(["--exam", "--all"]), 0)
    XCTAssertEqual(lastExam()?.total.episodes, 2)
    XCTAssertEqual(lastExam()?.rows.first?.bar?.breaks, 2)
  }

  private func lastExam() -> ScorecardRun? {
    ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard-exam.json")).runs.last
  }

  func testExamRunsHaveTheirOwnScorecardFile() throws {
    try fill(ids: ["e1", "e2", "e3"])
    try folder.write("exam.json", "{\"episodes\": [\"e3\"]}")
    let plain = folder.url.appendingPathComponent("scorecard.json")
    XCTAssertEqual(score(), 0)
    let before = try Data(contentsOf: plain)
    // An exam run saves into its own file and leaves the plain one as it was.
    XCTAssertEqual(score(["--exam"]), 0)
    XCTAssertEqual(try Data(contentsOf: plain), before)
    XCTAssertEqual(lastExam()?.total.episodes, 1)
    XCTAssertFalse(output.contains("Since the last scorecard"), output)
    // The next exam run is compared with the last exam run, not with the plain one.
    XCTAssertEqual(score(["--exam"]), 0)
    XCTAssertTrue(output.contains("Since the last scorecard"), output)
    XCTAssertEqual(try Data(contentsOf: plain), before)
    let exams = ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard-exam.json"))
    XCTAssertEqual(exams.runs.count, 2)
    // A plain run never reads or writes the exam file.
    let examBefore = try Data(contentsOf: folder.url.appendingPathComponent("scorecard-exam.json"))
    XCTAssertEqual(score(), 0)
    XCTAssertTrue(output.contains("Since the last scorecard"), output)
    XCTAssertEqual(
      try Data(contentsOf: folder.url.appendingPathComponent("scorecard-exam.json")), examBefore)
    XCTAssertEqual(ScorecardHistory.load(from: plain).runs.count, 2)
  }

  func testOnlyExamEpisodesMarkedAndNoExamFlagSaysSo() throws {
    try fill(ids: ["e1", "e2"])
    try folder.write("exam.json", "{\"episodes\": [\"e1\", \"e2\"]}")
    XCTAssertEqual(score(), 0)
    XCTAssertTrue(output.contains("are on the exam"), output)
    XCTAssertTrue(output.contains("--exam scores them"), output)
    XCTAssertFalse(output.contains("has both a transcript and a label yet"), output)
  }

  func testADumpThatCannotBeWrittenStillSavesTheScorecard() throws {
    try fill()
    let bad = folder.url.appendingPathComponent("no/such/dir/d.json").path
    XCTAssertEqual(score(["--all", "--dump", bad]), 2)
    XCTAssertTrue(warned.joined().contains("The dump could not be written"), warned.joined())
    XCTAssertEqual(lastRun()?.total.episodes, 2)
  }

  // MARK: agree, the second round

  func testAgreeComparesEpisodesOnTheExam() throws {
    try fill(ids: ["e1", "e2"])
    try folder.write("exam.json", "{\"episodes\": [\"e1\", \"e2\"]}")
    try folder.write("labels-second/e1.json", labelJSON(segmentJSON(start: "10", end: "40")))
    try folder.write("labels-second/e2.json", labelJSON(segmentJSON(start: "10", end: "40")))
    var said: [String] = []
    XCTAssertEqual(
      AdAgreeCommand.run([folder.url.path], out: { said.append($0) }, err: { _ in }), 0)
    XCTAssertTrue(said.joined().contains("2 episodes are marked in both"), said.joined())
    XCTAssertTrue(said.joined().contains("Mean of the two rates: 100.0%."), said.joined())
  }

  func testAgreeMeanIsOverTheDirectionsThatHaveBreaks() {
    var passing = BarTotals()
    passing.breaks = 2
    passing.passed = 2
    XCTAssertEqual(AdAgreeCommand.mean(passing, BarTotals()) ?? -1, 1, accuracy: 1e-9)
    XCTAssertEqual(AdAgreeCommand.mean(BarTotals(), passing) ?? -1, 1, accuracy: 1e-9)
    var half = BarTotals()
    half.breaks = 2
    half.passed = 1
    XCTAssertEqual(AdAgreeCommand.mean(passing, half) ?? -1, 0.75, accuracy: 1e-9)
    XCTAssertNil(AdAgreeCommand.mean(BarTotals(), BarTotals()))
  }

  func testAgreeWithNoBreakInEitherMarkingHasNothingToCompare() throws {
    try fill(ids: ["e1"])
    try folder.write("labels/e1.json", labelJSON(segmentJSON(start: "10", end: "15")))
    try folder.write("labels-second/e1.json", labelJSON(segmentJSON(start: "10", end: "16")))
    var said: [String] = []
    XCTAssertEqual(
      AdAgreeCommand.run([folder.url.path], out: { said.append($0) }, err: { _ in }), 0)
    XCTAssertTrue(said.joined().contains("nothing to compare"), said.joined())
    XCTAssertFalse(said.joined().contains("Mean of the two rates"), said.joined())
  }
}
