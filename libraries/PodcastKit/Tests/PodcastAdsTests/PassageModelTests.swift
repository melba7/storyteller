import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// The passage model in the scorecard: reading `passage-model.json` (the answers the Mac's
/// `teach_passage.py` makes: five probabilities for every line, no words), turning them into ads
/// with the word model's decoder, and the row "Plus the passage model" of `podcast-teach score`.
final class PassageModelTests: XCTestCase {
  private let text = "[0:00:00.0] hello and welcome\n[0:00:10.5] the weather is nice today\n[0:01:00.0] back to the show\n[0:01:30.0] and so it ends\n"
  private let none = [1.0, 0, 0, 0, 0]
  private let sponsor = [0.0, 1, 0, 0, 0]
  private var folder: FolderWriter!
  private var printed: [String] = []
  private var warned: [String] = []

  override func setUpWithError() throws { folder = try FolderWriter() }
  override func tearDown() { folder.remove() }

  /// Two episodes of two shows, each with one marked sponsor ad from 10 s to 40 s.
  private func fill() throws {
    try folder.write(
      "episodes.json",
      "{\"version\": 1, \"episodes\": [{\"id\": \"e1\", \"feed\": \"f1\", \"show\": \"One\", \"title\": \"T1\"},"
        + "{\"id\": \"e2\", \"feed\": \"f2\", \"show\": \"Two\", \"title\": \"T2\"}]}")
    for id in ["e1", "e2"] {
      try folder.write("transcripts/\(id).txt", text)
      try folder.write("labels/\(id).json", labelJSON(segmentJSON(start: "10", end: "40")))
    }
  }

  /// The file the Mac writes. `episodes` maps an episode to the rows of its lines.
  private func writePassage(
    _ episodes: [String: [[Double]]], version: Int = 1, decoder: Int = 2,
    classes: String = "[\"none\",\"sponsor\",\"network_promo\",\"host_ask\",\"intro_credits\"]",
    thresholds: String = "{\"start\":0.6,\"stay\":0.4,\"sure\":0.85}"
  ) throws {
    let body = episodes.sorted { $0.key < $1.key }.map { id, rows in
      "\"\(id)\":{\"lines\":\(rows.count),\"rows\":\(rows)}"
    }.joined(separator: ",")
    try folder.write(
      "passage-model.json",
      "{\"version\":\(version),\"model\":\"test-model\",\"decoder\":\(decoder),\"classes\":\(classes),\"thresholds\":\(thresholds),\"trained\":{},\"episodes\":{\(body)}}"
    )
  }

  /// The two middle lines of the four-line text are a sponsor read.
  private var middleAd: [[Double]] { [none, sponsor, sponsor, none] }

  private func score(_ options: [String] = []) -> Int32 {
    printed = []
    warned = []
    return AdScoreCommand.run(
      [folder.url.path, "--no-model", "--all"] + options, out: { self.printed.append($0) },
      err: { self.warned.append($0) })
  }

  private var output: String { printed.joined(separator: "\n") }

  private func lastRun() -> ScorecardRun? {
    ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json")).runs.last
  }

  private func loaded() -> Result<PassageAnswers?, TeachingFolderError> { PassageAnswers.load(in: folder.url) }

  // MARK: The file

  func testAFileIsReadWithItsRowsPerEpisodeAndTheWordModelsCutOffs() throws {
    try writePassage(["e1": middleAd, "e2": [none, none]])
    guard case .success(let saved?) = loaded() else { return XCTFail("\(loaded())") }
    XCTAssertEqual(saved.model, "test-model")
    XCTAssertEqual(saved.episodes["e1"]?.rows, middleAd)
    XCTAssertEqual(saved.episodes["e2"]?.lines, 2)
    XCTAssertEqual(saved.thresholds, AdWordModel.Thresholds())
  }

  func testNoFileIsNilAndNotAProblem() throws {
    guard case .success(let found) = loaded() else { return XCTFail() }
    XCTAssertNil(found)
  }

  func testAFileThatCannotBeTrustedIsAPlainSentenceAndIsLeftAlone() throws {
    let url = folder.url.appendingPathComponent("passage-model.json")
    try Data("not json".utf8).write(to: url)
    guard case .failure(let problem) = loaded() else { return XCTFail() }
    XCTAssertTrue(problem.message.contains("damaged"), problem.message)
    XCTAssertEqual(try String(contentsOf: url), "not json")
    let bad: [(String, () throws -> Void)] = [
      ("another version", { try self.writePassage(["e1": self.middleAd], version: 2) }),
      ("another decoder", { try self.writePassage(["e1": self.middleAd], decoder: 1) }),
      ("other classes", { try self.writePassage(["e1": self.middleAd], classes: "[\"none\",\"ad\"]") }),
      ("a row of four", { try self.writePassage(["e1": [[1.0, 0, 0, 0]]]) }),
      ("a chance above one", { try self.writePassage(["e1": [[1.5, 0, 0, 0, 0]]]) }),
      ("a negative chance", { try self.writePassage(["e1": [[-0.2, 1.2, 0, 0, 0]]]) }),
      ("a start under half", { try self.writePassage(["e1": self.middleAd], thresholds: "{\"start\":0.3}") }),
      ("a cut-off over one", { try self.writePassage(["e1": self.middleAd], thresholds: "{\"stay\":2}") }),
    ]
    for (what, write) in bad {
      try write()
      guard case .failure(let sentence) = loaded() else { return XCTFail(what) }
      XCTAssertTrue(sentence.message.contains("passage-model.json"), what)
    }
  }

  func testTheNumberOfLinesMustMatchTheRowsOfAnEpisode() throws {
    try folder.write(
      "passage-model.json",
      "{\"version\":1,\"model\":\"m\",\"decoder\":2,\"classes\":[\"none\",\"sponsor\",\"network_promo\",\"host_ask\",\"intro_credits\"],\"episodes\":{\"e1\":{\"lines\":3,\"rows\":[[1,0,0,0,0]]}}}"
    )
    guard case .failure = loaded() else { return XCTFail() }
  }

  // MARK: The decoder

  /// Six lines of ten seconds each.
  private func sixLines() -> Transcript {
    var lines = ""
    for n in 0..<6 {
      lines += String(format: "[0:00:%02d.0] this is the %d line of some plain talk about nothing\n", n * 10, n + 1)
    }
    return TeachingFolder.transcript(fromText: lines, duration: 60)
  }

  func testTheRowsGoThroughTheWordModelsVersionTwoDecoderSoAStartWidensBack() throws {
    // Lines 3 and 4 are sure; line 2 is at 0.45, which is over `stay` (0.4): the version 2
    // decoder widens the start back over it, the version 1 decoder would not.
    let rows = [0.0, 0.45, 0.9, 0.9, 0.3, 0.0].map { [1 - $0, $0, 0, 0, 0] }
    let transcript = sixLines()
    let ads = PassageScoreRow.ads(
      rows: rows, thresholds: AdWordModel.Thresholds(), transcript: transcript)
    XCTAssertEqual(ads.count, 1)
    XCTAssertEqual(ads[0].kind, .ad)
    XCTAssertEqual(ads[0].start, 10, accuracy: 1, "\(ads)")
    XCTAssertEqual(ads[0].end, 40, accuracy: 1, "\(ads)")
    let lines = AdChunker.number(transcript.lines)
    let version1 = AdWordModel.decode(rows: rows, lines: lines, thresholds: AdWordModel.Thresholds())
    XCTAssertEqual(version1.first?.firstLine, 3)
    XCTAssertEqual(AdWordModel.decodeTwo(rows: rows, lines: lines, thresholds: AdWordModel.Thresholds()).first?.firstLine, 2)
  }

  func testTheAdsAreOnlyEverUnsureAndSayWhoMadeThem() throws {
    let rows = [0.0, 0.0, 1.0, 1.0, 1.0, 0.0].map { [1 - $0, $0, 0, 0, 0] }
    let ads = PassageScoreRow.ads(
      rows: rows, thresholds: AdWordModel.Thresholds(), transcript: sixLines())
    XCTAssertEqual(ads.map(\.confidence), [.unsure])
    XCTAssertEqual(ads.map(\.source), ["passage-model"])
  }

  func testEachClassBecomesItsOwnKind() throws {
    func kind(_ row: [Double]) -> [AdKind] {
      let rows = [[1.0, 0, 0, 0, 0], row, row, row, [1.0, 0, 0, 0, 0], [1.0, 0, 0, 0, 0]]
      return PassageScoreRow.ads(rows: rows, thresholds: AdWordModel.Thresholds(), transcript: sixLines())
        .map(\.kind)
    }
    XCTAssertEqual(kind([0, 1, 0, 0, 0]), [.ad])
    XCTAssertEqual(kind([0, 0, 1, 0, 0]), [.promo])
    XCTAssertEqual(kind([0, 0, 0, 1, 0]), [.ownPlug])
    XCTAssertEqual(kind([0, 0, 0, 0, 1]), [.credits])
  }

  func testPlainTalkMakesNoAds() throws {
    let ads = PassageScoreRow.ads(
      rows: Array(repeating: none, count: 6), thresholds: AdWordModel.Thresholds(), transcript: sixLines())
    XCTAssertEqual(ads, [])
  }

  // MARK: The row

  func testWithNoFileTheScorecardHasNoPassageRow() throws {
    try fill()
    XCTAssertEqual(score(), 0, warned.joined())
    XCTAssertFalse(output.contains("passage"))
    XCTAssertEqual(lastRun()?.rows.map(\.name), ["Word rules", "Plus promo rules", "Plus repeated words", "Plus per-show settings"])
  }

  func testTheRowComesAfterTheLastFinderRowAndFindsTheAdTheFindersMissed() throws {
    try fill()
    XCTAssertEqual(score(), 0)
    let before = lastRun()
    try writePassage(["e1": middleAd, "e2": middleAd])
    XCTAssertEqual(score(), 0, warned.joined())
    let run = lastRun()
    XCTAssertEqual(run?.rows.count, 5)
    XCTAssertEqual(run?.rows.last?.name, "Plus the passage model")
    XCTAssertEqual(run?.rows.dropLast().map(\.name), before?.rows.map(\.name))
    XCTAssertEqual(run?.rows.dropLast().map(\.total), before?.rows.map(\.total))
    XCTAssertEqual(run?.total, before?.total)
    XCTAssertEqual(before?.rows.last?.total.caught, 0)
    XCTAssertEqual(run?.rows.last?.total.caught, 2)
    XCTAssertEqual(run?.rows.last?.bar?.breaks, 2)
    XCTAssertTrue(output.contains("Plus the passage model: 2 of 2 scored episodes have an answer"), output)
    XCTAssertTrue(output.contains("last finder row"), output)
    XCTAssertTrue(output.contains("at least 10 more breaks"), output)
    XCTAssertTrue(output.contains("both label sets"), output)
  }

  func testAnEpisodeWithNoAnswerStaysAsTheLastFinderRow() throws {
    try fill()
    try writePassage(["e1": middleAd])
    XCTAssertEqual(score(), 0, warned.joined())
    XCTAssertTrue(output.contains("1 of 2 scored episodes have an answer"), output)
    let rows = lastRun()?.rows ?? []
    XCTAssertEqual(rows.last?.total.caught, 1)
    let second = rows.last?.shows.first { $0.feed == "f2" }
    let before = rows[rows.count - 2].shows.first { $0.feed == "f2" }
    XCTAssertEqual(second?.total, before?.total)
  }

  func testAnswersThatDoNotMatchTheTranscriptAreLeftOutWithANote() throws {
    try fill()
    try writePassage(["e1": [none, sponsor, sponsor]])  // three lines for a four-line transcript
    XCTAssertEqual(score(), 0, warned.joined())
    XCTAssertEqual(lastRun()?.rows.count, 4)
    XCTAssertFalse(output.contains("Plus the passage model:"), output)
    XCTAssertTrue(output.contains("1 episode"), output)
    XCTAssertTrue(output.contains("do not match"), output)
  }

  func testADamagedFileLeavesTheRowOutAndTheScorecardStillRuns() throws {
    try fill()
    let url = folder.url.appendingPathComponent("passage-model.json")
    try Data("not json".utf8).write(to: url)
    XCTAssertEqual(score(["--stream"]), 0, warned.joined())
    XCTAssertEqual(printed.filter { $0.contains("passage-model.json") && $0.contains("could not be read") }.count, 1, output)
    XCTAssertFalse(output.contains("Plus the passage model:"))
    XCTAssertEqual(lastRun()?.rows.count, 4)
    XCTAssertTrue(output.contains("Stream replay:"), output)
    XCTAssertEqual(try String(contentsOf: url), "not json")
  }

  func testAnswersForOtherEpisodesMakeNoRow() throws {
    try fill()
    try writePassage(["zz": middleAd])
    XCTAssertEqual(score(), 0)
    XCTAssertEqual(lastRun()?.rows.count, 4)
    XCTAssertFalse(output.contains("Plus the passage model:"))
  }

  // MARK: Next to Apple's row

  private func writeApple() throws {
    var apple = AppleAnswers(model: "m 1")
    apple.episodes["e1"] = .init(
      ads: [.init(start: 10, end: 40, kind: .ad, confidence: .sure)], refusedPieces: 0, seconds: 1)
    try apple.save(in: folder.url)
  }

  func testTheRowStandsOnTheLastFinderRowAndNotOnApplesRow() throws {
    try fill()
    try writePassage(["e1": middleAd, "e2": middleAd])
    XCTAssertEqual(score(), 0)
    let passageAlone = lastRun()?.rows.last
    try writeApple()
    XCTAssertEqual(score(), 0, warned.joined())
    let both = lastRun()?.rows ?? []
    // Apple has two rows now (as the phone places its answers, and if every show let it skip), and
    // the passage row stands on neither: on the last finder row.
    XCTAssertEqual(
      both.map(\.name).suffix(3),
      [
        "Plus Apple's model (asked on the Mac)", "Plus Apple's model, if every show let it skip",
        "Plus the passage model",
      ])
    XCTAssertEqual(both.count, 7)
    // The passage row is what it was with no Apple file, and has no Apple ads in it.
    XCTAssertEqual(both.last?.total, passageAlone?.total)
    XCTAssertEqual(both.last?.bar, passageAlone?.bar)
    // Apple asks by default, so its row is the row before it; the other row has its answer.
    XCTAssertEqual(both[4].total, both[3].total)
    XCTAssertEqual(both[5].total.caught, 1)
    XCTAssertTrue(output.contains("Plus Apple's model (asked on the Mac): 1 of 2 scored episodes"), output)
    XCTAssertTrue(output.contains("Plus the passage model: 2 of 2 scored episodes"), output)
  }

  func testAppleKeepsItsStreamNumbersWhenThePassageRowIsThereToo() throws {
    try fill()
    try writeApple()
    try writePassage(["e1": middleAd])
    XCTAssertEqual(score(["--stream"]), 0, warned.joined())
    let rows = lastRun()?.rows ?? []
    XCTAssertEqual(rows.count, 7)
    XCTAssertNotNil(rows[3].stream)
    XCTAssertNotNil(rows[4].stream)
    XCTAssertEqual(rows[4].name, "Plus Apple's model (asked on the Mac)")
    XCTAssertNil(rows[5].stream)
    XCTAssertNil(rows[6].stream)
    XCTAssertTrue(output.contains("Stream replay:"), output)
  }
}
