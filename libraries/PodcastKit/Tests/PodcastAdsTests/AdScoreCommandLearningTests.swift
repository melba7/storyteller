import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// `podcast-teach score` when the rows have to learn from episodes that are not scored (the
/// shelf is one episode of a show, so the older ones only teach), and when two finders find the
/// same stretch.
final class AdScoreCommandLearningTests: XCTestCase {
  private var folder: FolderWriter!
  private var printed: [String] = []

  override func setUpWithError() throws { folder = try FolderWriter() }
  override func tearDown() { folder.remove() }

  private func run(_ extras: ScoreExtras = ScoreExtras(), _ options: [String] = ["--no-model", "--no-library"]) -> Int32 {
    printed = []
    return AdScoreCommand.run(
      [folder.url.path] + options, extras: extras, out: { self.printed.append($0) }, err: { _ in })
  }

  private var output: String { printed.joined(separator: "\n") }

  private func savedRows() -> [ScorecardRow] {
    ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json")).runs.last?.rows ?? []
  }

  private func right(_ row: ScorecardRow?) -> Double {
    guard let total = row?.total else { return -1 }
    return total.adSeconds - total.heardSeconds
  }

  /// The words as the lines of a transcript file, five seconds a line.
  private func transcriptText(_ words: [String]) -> String {
    Speech.lines(words).map { line in
      let seconds = Int(line.start)
      return String(format: "[%d:%02d:%02d.0] ", seconds / 3600, seconds / 60 % 60, seconds % 60) + line.text
    }.joined(separator: "\n") + "\n"
  }

  private func label(_ start: Double, _ end: Double, sort: String = "sponsor") -> String {
    labelJSON(segmentJSON(start: "\(start)", end: "\(end)", sort: sort))
  }

  // MARK: The shelf only teaches

  /// Two episodes of one show with the same plug of 40 words, the newer one on the shelf.
  private func fillShelf() throws {
    try folder.write(
      "episodes.json",
      "{\"version\": 1, \"episodes\": [{\"id\": \"e1\", \"feed\": \"f1\", \"show\": \"One\", \"title\": \"Old\"},"
        + "{\"id\": \"e2\", \"feed\": \"f1\", \"show\": \"One\", \"title\": \"New\"}]}")
    try folder.write("shelf.json", "{\"version\": 1, \"episodes\": [\"e2\"]}")
    let plug = Speech.plug(40)
    let old = Speech.episode(tag: "old", total: 1200, plugs: [(400, plug)])
    let new = Speech.episode(tag: "new", total: 1200, plugs: [(900, plug)])
    try folder.write("transcripts/e1.txt", transcriptText(old))
    try folder.write("transcripts/e2.txt", transcriptText(new))
    try folder.write("labels/e1.json", label(200, 220))
    try folder.write("labels/e2.json", label(450, 470))
  }

  func testAShelfEpisodeLearnsFromTheOlderEpisodesOfItsShowThatAreNotScored() throws {
    try fillShelf()
    XCTAssertEqual(run(), 0)
    XCTAssertTrue(output.contains("the 1 shelf episodes"), output)
    let rows = savedRows()
    XCTAssertEqual(rows.first?.total.episodes, 1)
    // Only the shelf episode is scored, and the plug of the older one is what finds its plug.
    let words = rows.first { $0.name == ScoreRows.repeatedWords }
    XCTAssertEqual(right(words), 20, accuracy: 5)
    XCTAssertEqual(words?.total.episodes, 1)
    // The row has its own line in the print, set against the row before it.
    XCTAssertTrue(output.contains("Plus repeated words: found 2"), output)
    XCTAssertTrue(output.contains("more wrong seconds."), output)
  }

  func testWithNothingOlderToLearnFromTheRepeatedWordsRowAddsNothing() throws {
    try fillShelf()
    try folder.write("shelf.json", "{\"version\": 1, \"episodes\": [\"e1\", \"e2\"]}")
    XCTAssertEqual(run(), 0)
    // Both are scored, in the order of the folder: the first has nothing before it, the second
    // has the first.
    XCTAssertEqual(right(savedRows().first { $0.name == ScoreRows.repeatedWords}), 20, accuracy: 5)
  }

  func testTheSoundRowsLearnFromTheEpisodesThatAreNotScoredAndAreAskedAboutThemFirst() throws {
    try fillShelf()
    try folder.write(
      "episodes.json",
      "{\"version\": 1, \"episodes\": [{\"id\": \"e1\", \"feed\": \"f1\", \"show\": \"One\", \"title\": \"Old\", \"file\": \"audio/e1.mp3\"},"
        + "{\"id\": \"e2\", \"feed\": \"f1\", \"show\": \"One\", \"title\": \"New\", \"file\": \"audio/e2.mp3\"}]}")
    try folder.write("audio/e1.mp3", "x")
    try folder.write("audio/e2.mp3", "x")
    let calls = SoundCalls()
    let kit = ScoreSoundKit(
      ownSounds: { _, _, episode, _ in calls.ask("own \(episode)"); return [] },
      repeatedSounds: { _, _, episode in calls.ask("repeat \(episode)"); return [] })
    XCTAssertEqual(run(ScoreExtras(sounds: { _, _ in kit })), 0)
    // The older episode teaches first; the joints rows do not run for it.
    XCTAssertEqual(calls.all, ["own e1", "repeat e1", "own e2", "repeat e2"])
    XCTAssertEqual(savedRows().first?.total.episodes, 1)
  }

  func testTheOwnHabitsAreReplayedOverEveryLabelledEpisodeNotOnlyTheShelf() throws {
    try folder.write(
      "episodes.json",
      "{\"version\": 1, \"episodes\": ["
        + (1...3).map { "{\"id\": \"e\($0)\", \"feed\": \"f1\", \"show\": \"One\", \"title\": \"T\($0)\"}" }
        .joined(separator: ",") + "]}")
    try folder.write("shelf.json", "{\"version\": 1, \"episodes\": [\"e3\"]}")
    for id in ["e1", "e2", "e3"] {
      try folder.write("transcripts/\(id).txt", "[0:00:00.0] plain talk\n[0:01:00.0] more plain talk\n[0:02:00.0] and so it ends\n")
      try folder.write("labels/\(id).json", label(70, 100))
    }
    try folder.write("habits.json", "{\"version\": 1, \"shows\": [{\"feed\": \"f1\", \"episodes\": 4, \"opensWithAd\": 0}]}")
    XCTAssertEqual(run(), 0)
    XCTAssertTrue(output.contains("Own habits agree with the Mac's habits for 1 of 1 show."), output)
  }

  // MARK: One stretch found by an ask-only finder and a skipping one

  private func meaningTranscript() -> String {
    let words = (1...12).map { number -> String in
      let even = number % 2 == 0
      if (4...8).contains(number) { return even ? Made.ask : Made.ask2 }
      return even ? Made.talk : Made.talk2
    }
    return words.enumerated().map {
      String(format: "[0:%02d:%02d.0] ", $0.offset / 6, ($0.offset % 6) * 10) + $0.element
    }.joined(separator: "\n") + "\n"
  }

  func testTheMeaningRowIsNotCutByARepeatFinderThatOnlyAsksAndTheSettingsKeepItWhole() throws {
    try folder.write(
      "episodes.json",
      "{\"version\": 1, \"episodes\": [{\"id\": \"e1\", \"feed\": \"f1\", \"show\": \"One\", \"title\": \"T\", \"file\": \"audio/e1.mp3\"}]}")
    try folder.write("audio/e1.mp3", "not really audio")
    try folder.write("transcripts/e1.txt", meaningTranscript())
    try folder.write("labels/e1.json", label(30, 80, sort: "host_ask"))
    try folder.write("show-settings.json", "{\"version\": 1}")
    try folder.write("ad-meaning.json", String(decoding: Made.file(), as: UTF8.self))
    // The repeat finder (it only asks, built in) finds a stretch that covers the start of the
    // meaning model's ad.
    let kit = ScoreSoundKit(repeatedSounds: { _, _, _ in [ScoreSpan(start: 5, end: 55, sort: "host_ask")] })
    XCTAssertEqual(run(ScoreExtras(sounds: { _, _ in kit }, embedder: { _ in Made.embedder() })), 0)
    let rows = savedRows()
    let meaning = rows.first { $0.name == ScoreRows.meaning }
    XCTAssertGreaterThan(right(meaning), 40)
    XCTAssertEqual(right(rows.last), right(meaning), accuracy: 1e-6)
    XCTAssertTrue(output.contains("The check holds."), output)
  }

  func testAFullRunHasEveryRowInTheRoundsOrder() throws {
    try folder.write(
      "episodes.json",
      "{\"version\": 1, \"episodes\": [{\"id\": \"e1\", \"feed\": \"f1\", \"show\": \"One\", \"title\": \"T\", \"file\": \"audio/e1.mp3\"}]}")
    try folder.write("audio/e1.mp3", "not really audio")
    try folder.write("transcripts/e1.txt", meaningTranscript())
    try folder.write("labels/e1.json", label(30, 80, sort: "host_ask"))
    try folder.write("ad-meaning.json", String(decoding: Made.file(), as: UTF8.self))
    XCTAssertEqual(
      run(ScoreExtras(sounds: { _, _ in ScoreSoundKit() }, embedder: { _ in Made.embedder() })), 0)
    XCTAssertEqual(
      savedRows().map(\.name),
      [
        "Word rules", "Plus promo rules", "Plus the meaning model", "Plus the phone's own sounds",
        "Plus repeated sounds", "Plus repeated words", "Plus joints", "Plus joints (steady files too)",
        "Plus per-show settings",
      ])
  }
}
