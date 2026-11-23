import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// Apple's model in the scorecard: the cache of its answers, `podcast-teach apple` with a fake
/// detector, the extra row and the stream block of `podcast-teach score --stream`.
final class AppleModelTests: XCTestCase {
  private let text = "[0:00:00.0] hello and welcome\n[0:00:10.5] the weather is nice today\n[0:01:00.0] back to the show\n[0:01:30.0] and so it ends\n"
  private var folder: FolderWriter!
  private var printed: [String] = []
  private var warned: [String] = []

  override func setUpWithError() throws { folder = try FolderWriter() }
  override func tearDown() { folder.remove() }

  private func fill(ids: [String] = ["e1", "e2"]) throws {
    let entries = ids.map { "{\"id\": \"\($0)\", \"feed\": \"f\($0)\", \"show\": \"S\($0)\", \"title\": \"T\"}" }
    try folder.write("episodes.json", "{\"version\": 1, \"episodes\": [\(entries.joined(separator: ","))]}")
    for id in ids {
      try folder.write("transcripts/\(id).txt", text)
      try folder.write("labels/\(id).json", labelJSON(segmentJSON(start: "10", end: "40")))
    }
  }

  /// A model that says lines 2 to 2 are a sponsor ad.
  private let model = FakeDetector(name: "fake-model", version: "7", tokenBudget: 1000) { _ in
    [range(2, 2)]
  }

  private func apple(_ options: [String] = [], detector: AdDetector? = nil) async -> Int32 {
    printed = []
    warned = []
    return await AppleCommand.run(
      [folder.url.path] + options, detector: detector, out: { self.printed.append($0) },
      err: { self.warned.append($0) })
  }

  private func score(_ options: [String] = []) -> Int32 {
    printed = []
    warned = []
    return AdScoreCommand.run(
      [folder.url.path, "--no-model", "--all"] + options, out: { self.printed.append($0) },
      err: { self.warned.append($0) })
  }

  private var output: String { printed.joined(separator: "\n") }
  private var cacheURL: URL { folder.url.appendingPathComponent("apple-model.json") }

  private func lastRun() -> ScorecardRun? {
    ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json")).runs.last
  }

  // MARK: The cache and the command

  func testTheCacheRoundTripsAndKeepsNoTranscriptText() throws {
    var saved = AppleAnswers(model: "m 1")
    saved.episodes["a"] = .init(
      ads: [.init(start: 1, end: 31, kind: .ad, confidence: .sure)], refusedPieces: 0, seconds: 41.2)
    try saved.save(in: folder.url)
    guard case .success(let loaded) = AppleAnswers.load(in: folder.url) else { return XCTFail() }
    XCTAssertEqual(loaded, saved)
    let raw = try String(contentsOf: cacheURL)
    XCTAssertTrue(raw.contains("\"confidence\" : \"sure\""), raw)
    XCTAssertFalse(raw.contains("firstWords"))
    XCTAssertEqual(loaded?.ads(for: "a")?.first?.end, 31)
    XCTAssertNil(loaded?.ads(for: "b"))
  }

  func testTheCommandAsksEachEpisodeSavesAtOnceAndCarriesOnWhereItWas() async throws {
    try fill()
    let code = await apple(["--limit", "1"], detector: model)
    XCTAssertEqual(code, 0, warned.joined())
    XCTAssertTrue(output.contains("1 of 2 episodes have answers"), output)
    guard case .success(let one) = AppleAnswers.load(in: folder.url) else { return XCTFail() }
    XCTAssertEqual(one?.episodes.count, 1)
    XCTAssertEqual(one?.model, "fake-model 7")
    let code1 = await apple(detector: model)
    XCTAssertEqual(code1, 0)
    XCTAssertTrue(output.contains("2 of 2 episodes have answers"), output)
    XCTAssertEqual(printed.filter { $0.contains(" ads, ") }.count, 1)  // only the one that was left
    guard case .success(let both) = AppleAnswers.load(in: folder.url) else { return XCTFail() }
    XCTAssertEqual(both?.episodes.count, 2)
    XCTAssertEqual(both?.episodes["e1"]?.ads.count, 1)
    XCTAssertEqual(both?.episodes["e1"]?.ads.first?.kind, .ad)
  }

  func testWithNoModelOnThisSystemItSaysSoAndExitsWithTwo() async throws {
    try fill()
    let code2 = await apple(detector: nil)
    XCTAssertEqual(code2, 2)
    XCTAssertTrue(warned.joined().contains("not available"), warned.joined())
    XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
  }

  func testADamagedOrForeignCacheIsASetUpProblemAndIsLeftAlone() async throws {
    try fill()
    try Data("not json".utf8).write(to: cacheURL)
    let code3 = await apple(detector: model)
    XCTAssertEqual(code3, 2)
    XCTAssertTrue(warned.joined().contains("damaged"))
    XCTAssertEqual(try String(contentsOf: cacheURL), "not json")
    try AppleAnswers(model: "other 1").save(in: folder.url)
    let code4 = await apple(detector: model)
    XCTAssertEqual(code4, 2)
    XCTAssertTrue(warned.joined().contains("other 1"))
  }

  func testADamagedCacheLeavesTheAppleRowOutAndTheScorecardStillRuns() throws {
    try fill()
    try Data("not json".utf8).write(to: cacheURL)
    XCTAssertEqual(score(["--stream"]), 0, warned.joined())
    XCTAssertEqual(printed.filter { $0.contains("could not be read") }.count, 1, output)
    XCTAssertTrue(output.contains("podcast-teach apple"), output)
    XCTAssertFalse(output.contains("Plus Apple's model"))
    XCTAssertTrue(output.contains("Stream replay:"), output)
    XCTAssertEqual(lastRun()?.rows.count, 4)
    XCTAssertEqual(try String(contentsOf: cacheURL), "not json")
  }

  func testWhenEveryEpisodeAlreadyHasAnAnswerTheCommandSaysSo() async throws {
    try fill()
    _ = await apple(detector: model)
    let code = await apple(detector: model)
    XCTAssertEqual(code, 0)
    XCTAssertTrue(output.contains("Every episode already had an answer"), output)
  }

  func testAModelThatCannotBeUsedStopsTheRunAndKeepsWhatWasAsked() async throws {
    try fill()
    let broken = FakeDetector(name: "fake-model", version: "7", tokenBudget: 1000) { _ in
      throw AdDetectorError.unavailable(.appleIntelligenceOff)
    }
    let code5 = await apple(detector: broken)
    XCTAssertEqual(code5, 2)
    XCTAssertTrue(warned.joined().contains("Apple Intelligence is off"))
  }

  func testWithExamOnlyTheExamEpisodesAreAsked() async throws {
    try fill(ids: ["e1", "e2", "e3"])
    try folder.write("exam.json", "{\"version\": 1, \"episodes\": [\"e3\"]}")
    let code6 = await apple(["--exam"], detector: model)
    XCTAssertEqual(code6, 0, warned.joined())
    guard case .success(let loaded) = AppleAnswers.load(in: folder.url) else { return XCTFail() }
    XCTAssertEqual(Array(loaded?.episodes.keys ?? [:].keys), ["e3"])
  }

  // MARK: The scorecard

  func testWithNoCacheTheScorecardHasNoAppleRowAndNoStreamField() throws {
    try fill()
    XCTAssertEqual(score(), 0)
    XCTAssertFalse(output.contains("Apple's model"))
    XCTAssertFalse(output.contains("Stream replay"))
    let run = lastRun()
    XCTAssertEqual(run?.rows.count, 4)
    XCTAssertTrue(run?.rows.allSatisfy { $0.stream == nil } ?? false)
    XCTAssertFalse(try String(contentsOf: folder.url.appendingPathComponent("scorecard.json")).contains("\"stream\""))
  }

  func testTheAppleRowComesAfterTheOthersAndTheRunsTotalStaysTheFindersLastRow() async throws {
    try fill()
    XCTAssertEqual(score(), 0)
    let before = lastRun()
    let code7 = await apple(["--limit", "1"], detector: model)
    XCTAssertEqual(code7, 0)
    XCTAssertEqual(score(), 0)
    let run = lastRun()
    XCTAssertEqual(run?.rows.count, 5)
    XCTAssertEqual(run?.rows.last?.name, "Plus Apple's model (asked on the Mac)")
    XCTAssertEqual(run?.rows.dropLast().map(\.name), before?.rows.map(\.name))
    XCTAssertEqual(run?.rows.dropLast().map(\.total), before?.rows.map(\.total))
    XCTAssertEqual(run?.total, before?.total)
    XCTAssertTrue(output.contains("1 of 2 scored episodes have an answer"), output)
    XCTAssertTrue(output.contains("Why breaks fail in the last row"), output)
  }

  func testStreamAddsItsBlockAndSavesTheNumbersOnlyWithTheFlag() async throws {
    try fill()
    let code8 = await apple(detector: model)
    XCTAssertEqual(code8, 0)
    XCTAssertEqual(score(["--stream"]), 0, warned.joined())
    XCTAssertTrue(output.contains("Stream replay: every episode is played from the start"), output)
    XCTAssertTrue(output.contains("standard: 1 s to the first byte"), output)
    XCTAssertTrue(output.contains("At the slow pace:"), output)
    XCTAssertTrue(output.contains("Ready (everything known at the start"), output)
    XCTAssertTrue(output.contains("\"ready\" here means the same player with everything known"), output)
    XCTAssertTrue(output.contains("waits for Apple's model"), output)
    XCTAssertTrue(output.contains("Speech at 6 times real time"), output)
    XCTAssertTrue(output.contains("not measured yet"), output)
    let rows = lastRun()?.rows ?? []
    XCTAssertEqual(rows.count, 5)
    XCTAssertNil(rows[0].stream)
    XCTAssertNotNil(rows[3].stream)
    XCTAssertNotNil(rows[4].stream)
    XCTAssertEqual(rows[3].stream?.standard.breaks, rows[3].bar?.breaks)
  }
}
