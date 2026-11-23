import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// `podcast-teach score` with the new rows: what is saved in scorecard.json, in which order, and
/// what it says when a row cannot be made. The sound finders are made up (the real ones are in
/// the podcast-teach tool); everything else is the command as it runs.
final class AdScoreCommandRowsTests: XCTestCase {
  /// Plain talk, so no rule finds anything and the sound finders are what adds.
  private let text = "[0:00:00.0] hello and welcome\n[0:00:10.5] the weather is nice today\n[0:01:00.0] back to the show\n[0:01:30.0] and so it ends\n"
  private var folder: FolderWriter!
  private var printed: [String] = []
  private var warned: [String] = []

  override func setUpWithError() throws { folder = try FolderWriter() }
  override func tearDown() { folder.remove() }

  /// Two episodes of two shows, each with one marked sponsor ad from 10 s to 40 s. Only the first
  /// has an MP3 file (it holds nothing: the made-up finders do not read it).
  private func fill(audio: Bool = true, transcript: String? = nil) throws {
    let first = audio ? ", \"file\": \"audio/e1.mp3\"" : ""
    try folder.write(
      "episodes.json",
      "{\"version\": 1, \"episodes\": [{\"id\": \"e1\", \"feed\": \"f1\", \"show\": \"One\", \"title\": \"T1\"\(first)},"
        + "{\"id\": \"e2\", \"feed\": \"f2\", \"show\": \"Two\", \"title\": \"T2\"}]}")
    for id in ["e1", "e2"] {
      try folder.write("transcripts/\(id).txt", transcript ?? text)
      try folder.write("labels/\(id).json", labelJSON(segmentJSON(start: "10", end: "40")))
    }
    if audio { try folder.write("audio/e1.mp3", "not really audio") }
  }

  private func run(
    _ extras: ScoreExtras = ScoreExtras(), _ options: [String] = ["--no-model", "--no-library", "--all"]
  ) -> Int32 {
    printed = []
    warned = []
    return AdScoreCommand.run(
      [folder.url.path] + options, extras: extras, out: { self.printed.append($0) },
      err: { self.warned.append($0) })
  }

  private var output: String { printed.joined(separator: "\n") }

  private func savedRows() -> [ScorecardRow] {
    ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json")).runs.last?.rows ?? []
  }

  /// A made-up kit: its own sounds find the marked ad in the first episode, and it says what it was asked.
  private func kit(_ calls: SoundCalls) -> ScoreSoundKit {
    ScoreSoundKit(
      ownSounds: { url, show, episode, _ in
        calls.ask("own \(url.lastPathComponent) \(show) \(episode)")
        return [ScoreSpan(start: 10, end: 40)]
      },
      repeatedSounds: { _, _, episode in
        calls.ask("repeat \(episode)")
        return []
      },
      snapJoints: { _, spans, steady in
        calls.ask("snap", steadyToo: steady)
        return spans
      })
  }

  private func extras(_ calls: SoundCalls) -> ScoreExtras {
    let made = kit(calls)
    return ScoreExtras(sounds: { _, _ in made })
  }

  // MARK: Rows saved

  func testEveryRowIsSavedWithTheTotalsOfEachShowAndTheRunHasTheLastRowsTotal() throws {
    try fill(audio: false)
    XCTAssertEqual(run(), 0)
    let rows = savedRows()
    XCTAssertEqual(rows.map(\.name), ["Word rules", "Plus promo rules", "Plus repeated words"])
    for row in rows {
      XCTAssertEqual(Set(row.shows.map(\.feed)), ["f1", "f2"], row.name)
      XCTAssertEqual(row.total.episodes, 2, row.name)
    }
    let history = ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json"))
    XCTAssertEqual(history.runs.last?.total, rows.last?.total)
    XCTAssertTrue(output.contains("What each layer adds: Word rules"), output)
    XCTAssertTrue(output.contains("Plus repeated words"), output)
  }

  func testAnOldScorecardFileWithNoRowsStillReadsAndTheNewRunIsAdded() throws {
    try fill(audio: false)
    try folder.write(
      "scorecard.json",
      "{\"version\": 1, \"runs\": [{\"at\": 1, \"title\": \"old\", \"total\": {\"episodes\": 1, \"shows\": 1, \"ads\": 1, \"caught\": 1, \"adSeconds\": 10, \"heardSeconds\": 0, \"cutSeconds\": 0, \"showSeconds\": 90, \"wrongSkips\": 0, \"bySort\": {}, \"openingAds\": 0, \"openingKnown\": 0}}]}")
    XCTAssertEqual(run(), 0)
    let history = ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json"))
    XCTAssertEqual(history.runs.count, 2)
    XCTAssertEqual(history.runs[0].rows, [])
    XCTAssertFalse(history.runs[1].rows.isEmpty)
    XCTAssertTrue(output.contains("Since the last scorecard"), output)
  }

  func testWhatTheMacsPublishGateReadsIsInEveryRowAndInEveryShowOfIt() throws {
    try fill(audio: false)
    XCTAssertEqual(run(), 0)
    let url = folder.url.appendingPathComponent("scorecard.json")
    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let run = try XCTUnwrap((root["runs"] as? [[String: Any]])?.last)
    // The run's time is in milliseconds since 1970, like the Mac's other files.
    XCTAssertGreaterThan(try XCTUnwrap(run["at"] as? Double), 1e12)
    for row in try XCTUnwrap(run["rows"] as? [[String: Any]]) {
      var totals = [try XCTUnwrap(row["total"] as? [String: Any])]
      totals += try XCTUnwrap(row["shows"] as? [[String: Any]]).compactMap { $0["total"] as? [String: Any] }
      for total in totals {
        for key in ["episodes", "adSeconds", "heardSeconds", "cutSeconds"] {
          XCTAssertNotNil(total[key] as? Double, "\(row["name"] ?? "") \(key)")
        }
        let sorts = try XCTUnwrap(total["bySort"] as? [String: [String: Any]])
        for sort in ["host_ask", "network_promo"] {
          XCTAssertNotNil(sorts[sort]?["seconds"] as? Double, sort)
          XCTAssertNotNil(sorts[sort]?["heardSeconds"] as? Double, sort)
        }
      }
    }
  }

  // MARK: Rows that need audio

  func testTheSoundRowsComeInTheRoundsOrderAndAnEpisodeWithNoAudioIsLeftOutWithANote() throws {
    try fill()
    let calls = SoundCalls()
    XCTAssertEqual(run(extras(calls)), 0)
    let rows = savedRows()
    XCTAssertEqual(
      rows.map(\.name),
      [
        "Word rules", "Plus promo rules", "Plus the phone's own sounds", "Plus repeated sounds",
        "Plus repeated words", "Plus joints", "Plus joints (steady files too)",
      ])
    // Only the first episode has audio: the finders were asked about it alone.
    XCTAssertEqual(calls.all.filter { $0.hasPrefix("own") }, ["own e1.mp3 f1 e1"])
    XCTAssertEqual(calls.all.filter { $0.hasPrefix("repeat") }, ["repeat e1"])
    XCTAssertEqual(calls.steady.filter { $0 }.count, 1)
    XCTAssertTrue(output.contains("1 of 2 episodes have no MP3 file (e2)"), output)
    // The own sounds found the marked ad of the first episode, and nothing else did.
    XCTAssertEqual(rows[1].total.caught, 0)
    XCTAssertEqual(rows[2].total.caught, 1)
    XCTAssertEqual(rows[2].total.adSeconds - rows[2].total.heardSeconds, 30, accuracy: 1e-9)
    // The joints rows are there with their verdict lines.
    XCTAssertTrue(output.contains("Joints: right seconds"), output)
    XCTAssertTrue(output.contains("Joints in steady files too: right seconds"), output)
  }

  func testWithNoAudioAtAllTheSoundRowsAreLeftOutAndTheNoteSaysSo() throws {
    try fill(audio: false)
    let calls = SoundCalls()
    XCTAssertEqual(run(extras(calls)), 0)
    XCTAssertEqual(savedRows().map(\.name), ["Word rules", "Plus promo rules", "Plus repeated words"])
    XCTAssertEqual(calls.all, [])
    XCTAssertTrue(output.contains("No episode has an MP3 file in the teaching folder"), output)
  }

  func testWithNoAudioCodeAtAllTheSoundRowsAreLeftOutToo() throws {
    try fill()
    XCTAssertEqual(run(), 0)
    XCTAssertFalse(savedRows().contains { ScoreRows.needingAudio.contains($0.name) })
    XCTAssertTrue(output.contains("no audio code"), output)
  }

  func testAFileThatIsNotMP3OrLeavesTheFolderIsNotAudio() throws {
    try folder.write(
      "episodes.json",
      "{\"version\": 1, \"episodes\": [{\"id\": \"e1\", \"feed\": \"f1\", \"show\": \"One\", \"title\": \"T\", \"file\": \"audio/e1.m4a\"},"
        + "{\"id\": \"e2\", \"feed\": \"f2\", \"show\": \"Two\", \"title\": \"T\", \"file\": \"audio/../e2.mp3\"}]}")
    for id in ["e1", "e2"] {
      try folder.write("transcripts/\(id).txt", text)
      try folder.write("labels/\(id).json", labelJSON(segmentJSON(start: "10", end: "40")))
    }
    try folder.write("audio/e1.m4a", "x")
    try folder.write("e2.mp3", "x")
    let calls = SoundCalls()
    XCTAssertEqual(run(extras(calls)), 0)
    XCTAssertEqual(calls.all, [])
    XCTAssertTrue(output.contains("No episode has an MP3 file"), output)
  }

  // MARK: The meaning model

  private func meaningTranscript() -> String {
    let words = (1...12).map { number -> String in
      let even = number % 2 == 0
      if (4...8).contains(number) { return even ? Made.ask : Made.ask2 }
      return even ? Made.talk : Made.talk2
    }
    return words.enumerated().map { "[0:\(String(format: "%02d", $0.offset / 6)):\(String(format: "%02d", ($0.offset % 6) * 10)).0] \($0.element)" }
      .joined(separator: "\n") + "\n"
  }

  func testTheMeaningRowNeedsTheModelFileAndAnEmbedderAndFollowsTheRepeatedWordsRow() throws {
    try fill(audio: false, transcript: meaningTranscript())
    // No file: no row, and the note says why.
    XCTAssertEqual(run(), 0)
    XCTAssertFalse(savedRows().contains { $0.name == ScoreRows.meaning })
    XCTAssertTrue(output.contains("no ad-meaning.json"), output)
    // A file but no embedder (a build without Apple's sentence embedding): still no row.
    try folder.write("ad-meaning.json", String(decoding: Made.file(), as: UTF8.self))
    XCTAssertEqual(run(), 0)
    XCTAssertFalse(savedRows().contains { $0.name == ScoreRows.meaning })
    XCTAssertTrue(output.contains("needs a Mac"), output)
    // With an embedder the row is there, straight after the repeated words.
    XCTAssertEqual(run(ScoreExtras(embedder: { _ in Made.embedder() })), 0)
    let names = savedRows().map(\.name)
    XCTAssertEqual(names.last, "Plus the meaning model")
    XCTAssertEqual(names.dropLast().last, "Plus repeated words")
    XCTAssertTrue(output.contains("The meaning model read 2 episodes"), output)
  }

  func testAMeaningFileThatDoesNotReadIsSaidSo() throws {
    try fill(audio: false)
    try folder.write("ad-meaning.json", "{ nonsense")
    XCTAssertEqual(run(ScoreExtras(embedder: { _ in Made.embedder() })), 0)
    XCTAssertFalse(savedRows().contains { $0.name == ScoreRows.meaning })
    XCTAssertTrue(output.contains("ad-meaning.json could not be read"), output)
  }

  // MARK: The settings

  func testTheSettingsRowIsTheLastOneAndSaysWhetherTheCheckHolds() throws {
    try fill()
    try folder.write(
      "show-settings.json", "{\"version\": 1, \"default\": {\"finders\": {\"own-sound\": \"off\"}}}")
    let calls = SoundCalls()
    XCTAssertEqual(run(extras(calls)), 0)
    let rows = savedRows()
    XCTAssertEqual(rows.last?.name, "Plus per-show settings")
    XCTAssertEqual(rows.count, 8)
    // Own sounds are off, so the first episode's marked ad is not skipped any more.
    XCTAssertEqual(rows.last?.total.caught, 0)
    XCTAssertTrue(output.contains("Per-show settings: right seconds"), output)
    XCTAssertTrue(output.contains("The check does not hold: right seconds fell by 30 s."), output)
    let history = ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json"))
    XCTAssertEqual(history.runs.last?.total, rows.last?.total)
  }

  func testWithNoSettingsFileThereIsNoSettingsRow() throws {
    try fill(audio: false)
    XCTAssertEqual(run(), 0)
    XCTAssertFalse(savedRows().contains { $0.name == ScoreRows.settings })
    XCTAssertTrue(output.contains("no show-settings.json"), output)
  }

  func testSettingsThatSkipEverythingHoldTheCheck() throws {
    try fill()
    try folder.write("show-settings.json", "{\"version\": 1}")
    XCTAssertEqual(run(extras(SoundCalls())), 0)
    // The built-in default only asks for the repeat finders, which found nothing here.
    XCTAssertTrue(output.contains("The check holds."), output)
  }

  // MARK: Questions and habits

  func testTheQuestionsLineAndTheHabitsNoteArePrinted() throws {
    let asking = ["plain", "plain", "mid", "mid", "mid", "mid", "plain", "plain", "plain", "plain"]
    let lines = asking.enumerated().map { "[0:00:\(String(format: "%02d", $0.offset * 6)).0] \($0.element)" }
    try fill(audio: false, transcript: lines.joined(separator: "\n") + "\n")
    func key(_ feature: String) -> String { String(AdWordModel.bucket(feature, buckets: 262144)) }
    let weights: [String: Any] = [
      key("#bias"): [5.0, 0.0, 0.0, 0.0, 0.0], key("u:hi"): [-7.0, 7.0, 0.0, 0.0, 0.0],
      key("u:mid"): [-2.5, 2.5, 0.0, 0.0, 0.0],
    ]
    let model: [String: Any] = [
      "version": 1, "buckets": 262144, "classes": AdWordModel.classes, "weights": weights,
    ]
    try folder.write("ad-model.json", String(decoding: try JSONSerialization.data(withJSONObject: model), as: UTF8.self))
    try folder.write("habits.json", "{\"version\": 1, \"shows\": [{\"feed\": \"f1\", \"episodes\": 4, \"opensWithAd\": 0}]}")
    XCTAssertEqual(run(ScoreExtras(), ["--no-library", "--all"]), 0)
    XCTAssertTrue(output.contains("Questions: 2 questions over"), output)
    XCTAssertTrue(output.contains("Starting gate for the question note"), output)
    XCTAssertTrue(output.contains("Own habits agree with the Mac's habits for 0 of 0 shows"), output)
  }

  func testWithNoWordModelTheQuestionsAreNotCounted() throws {
    try fill(audio: false)
    XCTAssertEqual(run(), 0)
    XCTAssertTrue(output.contains("Questions: not counted"), output)
    XCTAssertTrue(output.contains("Own habits were not compared"), output)
  }
}
