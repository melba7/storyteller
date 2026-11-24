import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// `podcast-teach score --stream --speech N`: the stream replay at the speech pace the phone
/// measured (see PlayDiary), not at the assumed standard one.
final class StreamSpeechTests: XCTestCase {
  private let text = "[0:00:00.0] hello and welcome\n[0:00:10.5] the weather is nice today\n[0:01:00.0] back to the show\n[0:01:30.0] and so it ends\n"
  private var folder: FolderWriter!
  private var printed: [String] = []
  private var warned: [String] = []

  override func setUpWithError() throws { folder = try FolderWriter() }
  override func tearDown() { folder.remove() }

  private func fill() throws {
    try folder.write(
      "episodes.json",
      "{\"version\": 1, \"episodes\": [{\"id\": \"e1\", \"feed\": \"f1\", \"show\": \"S\", \"title\": \"T\"}]}")
    try folder.write("transcripts/e1.txt", text)
    try folder.write("labels/e1.json", labelJSON(segmentJSON(start: "10", end: "40")))
  }

  private func score(_ options: [String]) -> Int32 {
    printed = []
    warned = []
    return AdScoreCommand.run(
      [folder.url.path, "--no-model", "--all"] + options, out: { self.printed.append($0) },
      err: { self.warned.append($0) })
  }

  private var output: String { printed.joined(separator: "\n") }

  private func ad(_ start: Double, _ end: Double) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "", confidence: .sure, firstWords: "")
  }

  private func episode() -> TeachingEpisode {
    TeachingEpisode(
      id: "e", feed: "f", show: "S", title: "T", transcript: makeTranscript(talk(60)),
      truth: [TeachingTruth(start: 200, end: 260, sort: "sponsor")], maybe: [], onShelf: true)
  }

  private func run(speech: Double?) -> StreamNumbers {
    StreamScore.run(
      episodes: [episode()], habits: ShowHabits(), settings: AdSkipSettings(), models: nil,
      speech: speech, whole: { _ in [self.ad(200, 260)] },
      detect: { _, transcript in
        transcript.duration >= 300 ? [self.ad(200, min(260, transcript.duration))] : []
      }
    ).finders
  }

  // MARK: The option

  func testTheOptionTakesASpeechPaceThatIsAPositiveNumber() throws {
    let given = try AdScoreCommand.parse(["f", "--stream", "--speech", "14.5"]).get()
    XCTAssertEqual(given.speech, 14.5)
    XCTAssertNil(try AdScoreCommand.parse(["f", "--stream"]).get().speech)
    XCTAssertTrue(AdScoreCommand.usage.contains("--speech N"))
    for bad in ["0", "-3", "abc", "nan", "inf", ""] {
      switch AdScoreCommand.parse(["f", "--stream", "--speech", bad]) {
      case .success: XCTFail("--speech \(bad) was taken")
      case .failure(let problem): XCTAssertTrue(problem.message.contains("--speech"), problem.message)
      }
    }
    if case .success = AdScoreCommand.parse(["f", "--stream", "--speech"]) { XCTFail() }
  }

  func testSpeechWithoutStreamIsRefusedInsteadOfIgnored() {
    guard case .failure(let problem) = AdScoreCommand.parse(["f", "--speech", "12"]) else {
      return XCTFail("--speech without --stream was taken")
    }
    XCTAssertTrue(problem.message.contains("--stream"), problem.message)
  }

  // MARK: The replay

  func testTheMeasuredPaceIsTheStandardPaceWithTheMeasuredSpeech() {
    let pace = StreamPace.measured(speech: 30)
    XCTAssertEqual(pace.name, "measured")
    XCTAssertEqual(pace.speech, 30)
    // Everything but the speech speed is the standard pace's.
    var expected = StreamPace.standard
    expected.name = "measured"
    expected.speech = 30
    XCTAssertEqual(pace, expected)
    XCTAssertTrue(pace.summary.hasPrefix("measured: 1 s to the first byte, 40 s of audio"))
  }

  func testASlowPhoneMissesTheAdThatTheAssumedPaceCatches() {
    XCTAssertEqual(run(speech: nil).standard.passed, 1)
    XCTAssertNil(run(speech: nil).speech)
    let slow = run(speech: 0.5)
    XCTAssertEqual(slow.standard.breaks, 1)
    XCTAssertEqual(slow.standard.passed, 0)
    XCTAssertEqual(slow.speech, 0.5)
    // Asking for the assumed speed gives the assumed numbers, marked as given.
    XCTAssertEqual(run(speech: 12).standard, run(speech: nil).standard)
    // The slow pace and the ready numbers are not changed by it.
    XCTAssertEqual(run(speech: 0.5).slow, run(speech: nil).slow)
    XCTAssertEqual(run(speech: 0.5).ready, run(speech: nil).ready)
  }

  func testTheCommandPrintsAndSavesThePaceItReplayedAt() throws {
    try fill()
    XCTAssertEqual(score(["--stream", "--speech", "30"]), 0, warned.joined())
    XCTAssertTrue(
      output.contains(
        "measured: 1 s to the first byte, 40 s of audio downloaded and 30 s transcribed per second"),
      output)
    XCTAssertTrue(output.contains("as a stream (measured pace)"), output)
    XCTAssertTrue(output.contains("measured on the phone"), output)
    XCTAssertFalse(output.contains("not measured yet"), output)
    let saved = ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json"))
    XCTAssertEqual(saved.runs.last?.rows.last?.stream?.speech, 30)
  }

  func testTheCommandWithoutTheOptionIsTheReplayItWas() throws {
    try fill()
    XCTAssertEqual(score(["--stream"]), 0, warned.joined())
    XCTAssertTrue(output.contains("standard: 1 s to the first byte"), output)
    XCTAssertTrue(output.contains("as a stream (standard pace)"), output)
    XCTAssertTrue(output.contains("not measured yet"), output)
    let saved = ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json"))
    XCTAssertNil(saved.runs.last?.rows.last?.stream?.speech)
  }
}
