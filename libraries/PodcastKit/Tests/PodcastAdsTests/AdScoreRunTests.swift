import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

final class AdScoreRunTests: XCTestCase {
  private func habits(_ json: String) -> ShowHabits {
    ShowHabits(data: Data(json.utf8)) ?? ShowHabits()
  }

  func testHeadKeepsLinesAndWordsThatEndByThen() {
    let transcript = makeTranscript(talk(5))  // lines of 9 seconds every 10 seconds
    let head = AdScoreRun.head(of: transcript, seconds: 20)
    XCTAssertEqual(head.lines.count, 2)
    XCTAssertTrue(head.words.allSatisfy { $0.end <= 20 })
    XCTAssertEqual(head.words.count, transcript.words.filter { $0.end <= 20 }.count)
    XCTAssertEqual(head.duration, 20)
    XCTAssertEqual(AdScoreRun.head(of: transcript, seconds: 18.9).lines.count, 1)
  }

  func testTotalsAddUpAndShowsAreWorstFirst() {
    let one = scoreEpisode(id: "1", feed: "fa", show: "A", truth: [(10, 20, "sponsor")])
    let two = scoreEpisode(
      id: "2", feed: "fb", show: "B", truth: [(10, 20, "sponsor"), (40, 50, "host_ask")],
      maybe: [(70, 80, "sponsor")])
    let three = scoreEpisode(id: "3", feed: "fa", show: "A", truth: [(60, 70, "network_promo")])
    let card = AdScoreRun.run(episodes: [one, two, three], habits: ShowHabits()) { episode, _ in
      episode.id == "1" ? [foundAd(10, 20), foundAd(80, 90)] : []
    }
    XCTAssertEqual(card.episodes.map(\.id), ["1", "2", "3"])
    XCTAssertEqual(card.total.episodes, 3)
    XCTAssertEqual(card.total.shows, 2)
    XCTAssertEqual(card.total.ads, 4)
    XCTAssertEqual(card.total.caught, 1)
    XCTAssertEqual(card.total.adSeconds, 40, accuracy: 1e-9)
    XCTAssertEqual(card.total.heardSeconds, 30, accuracy: 1e-9)
    XCTAssertEqual(card.total.cutSeconds, 10, accuracy: 1e-9)
    XCTAssertEqual(card.total.wrongSkips, 1)
    // 300 seconds, less 40 of ads and 10 of neutral.
    XCTAssertEqual(card.total.showSeconds, 250, accuracy: 1e-9)
    XCTAssertEqual(card.total.bySort["sponsor"]?.ads, 2)
    XCTAssertEqual(card.total.bySort["sponsor"]?.caught, 1)
    XCTAssertEqual(card.total.bySort["host_ask"]?.ads, 1)
    // Show B hears 20 seconds of ads, show A hears 10.
    XCTAssertEqual(card.shows.map(\.feed), ["fb", "fa"])
    XCTAssertEqual(card.shows[0].show, "B")
    XCTAssertEqual(card.shows[1].total.episodes, 2)
    XCTAssertEqual(card.shows[1].total.ads, 2)
    XCTAssertEqual(card.shows[1].total.heardSeconds, 10, accuracy: 1e-9)
  }

  func testOpeningIsKnownWhenTheFirstLookOverlapsIt() {
    let episode = scoreEpisode(truth: [(2, 12, "sponsor"), (20, 28, "sponsor")])
    var lookedAt: [Double] = []
    let card = AdScoreRun.run(episodes: [episode], habits: ShowHabits()) { _, transcript in
      if transcript.duration < 100 {
        lookedAt.append(transcript.duration)
        return [foundAd(0, 8)]
      }
      return []
    }
    XCTAssertEqual(lookedAt, [15])
    XCTAssertEqual(card.episodes[0].openingAds, 2)
    XCTAssertEqual(card.episodes[0].openingKnown, 1)
    XCTAssertEqual(card.total.openingAds, 2)
    XCTAssertEqual(card.total.openingKnown, 1)
  }

  func testTheFirstLookFollowsTheShowsHabit() {
    let known = habits(
      "{\"version\":1,\"shows\":[{\"id\":\"feed1\",\"episodes\":5,\"opensWithAd\":5,\"openingEnds\":40}]}")
    var lookedAt: [Double] = []
    _ = AdScoreRun.run(
      episodes: [scoreEpisode(truth: [(2, 12, "sponsor")])], habits: known
    ) { _, transcript in
      if transcript.duration < 100 { lookedAt.append(transcript.duration) }
      return []
    }
    XCTAssertEqual(lookedAt, [50])
  }

  func testNoOpeningAdsMeansNoSecondLook() {
    var calls = 0
    let card = AdScoreRun.run(
      episodes: [scoreEpisode(truth: [(50, 60, "sponsor")])], habits: ShowHabits()
    ) { _, _ in
      calls += 1
      return []
    }
    XCTAssertEqual(calls, 1)
    XCTAssertEqual(card.total.openingAds, 0)
  }

  func testAnEmptyRunHasEmptyTotals() {
    let card = AdScoreRun.run(episodes: [], habits: ShowHabits()) { _, _ in [] }
    XCTAssertEqual(card.episodes, [])
    XCTAssertEqual(card.shows, [])
    XCTAssertEqual(card.total.ads, 0)
    XCTAssertEqual(card.total.bySort.count, 4)
  }

  func testTheScoreCommandWritesTheScorecardFileWithoutCrashing() throws {
    let folder = try FolderWriter()
    defer { folder.remove() }
    try folder.write(
      "episodes.json",
      "{\"version\": 1, \"episodes\": [{\"id\": \"e1\", \"feed\": \"f1\", \"show\": \"One\", \"title\": \"T\"}]}")
    try folder.write("transcripts/e1.txt", sampleText + "[0:01:30.0] and so it ends\n")
    try folder.write(
      "labels/e1.json", labelJSON(segmentJSON(start: "10", end: "40")))
    var printed: [String] = []
    var warned: [String] = []
    let code = AdScoreCommand.run(
      [folder.url.path], out: { printed.append($0) }, err: { warned.append($0) })
    XCTAssertEqual(code, 0)
    XCTAssertTrue(printed.joined().contains("Scorecard for"))
    XCTAssertTrue(printed.joined().contains("all 1 labelled episodes (there is no shelf yet)"))
    let history = ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json"))
    XCTAssertEqual(history.runs.count, 1)
    XCTAssertEqual(history.runs[0].total.ads, 1)
    // A second run is added and compared with the first.
    printed = []
    XCTAssertEqual(
      AdScoreCommand.run([folder.url.path, "--no-model", "--no-library", "--all"], out: { printed.append($0) }, err: { _ in }),
      0)
    XCTAssertTrue(printed.joined().contains("Since the last scorecard"))
    XCTAssertEqual(ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json")).runs.count, 2)
  }

  func testTheScoreCommandSaysWhatIsWrongWithTheSetUp() throws {
    let folder = try FolderWriter()
    defer { folder.remove() }
    var warned: [String] = []
    XCTAssertEqual(AdScoreCommand.run([], out: { _ in }, err: { warned.append($0) }), 2)
    XCTAssertEqual(AdScoreCommand.run(["--bogus"], out: { _ in }, err: { _ in }), 2)
    XCTAssertEqual(AdScoreCommand.run([folder.url.path], out: { _ in }, err: { warned.append($0) }), 2)
    XCTAssertTrue(warned.last?.contains("episodes.json") ?? false)
    try folder.write("episodes.json", "{\"version\": 1, \"episodes\": []}")
    var printed: [String] = []
    XCTAssertEqual(AdScoreCommand.run([folder.url.path], out: { printed.append($0) }, err: { _ in }), 0)
    XCTAssertTrue(printed.joined().contains("No episode"))
  }
}
