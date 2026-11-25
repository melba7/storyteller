import XCTest

@testable import PodcastAudioMatch

/// `podcast-teach edges` on a tiny teaching folder made in the test, with made-up sound in place
/// of the decoder of a Mac: the files it reads, the files it writes, and picking up where it was.
final class EdgeCommandTests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "edges-\(UUID().uuidString)")
    for name in ["audio", "labels", "labels-snapped"] {
      try FileManager.default.createDirectory(
        at: folder.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    // a and b sound different between 20 and 50 s, and 25 and 45 s. g is steady. c is not on the
    // shelf, d is in the exam and e has no audio file.
    try put(
      "episodes.json",
      #"{"version": 1, "episodes": ["#
        + ["a", "b", "c", "d", "e", "g"].map { #"{"id": "\#($0)", "file": "audio/\#($0).mp3"}"# }
        .joined(
          separator: ",") + "]}")
    try put("shelf.json", #"{"episodes": ["a", "b", "d", "e", "g"]}"#)
    try put("exam.json", #"{"episodes": ["d"]}"#)
    for id in ["a", "b", "c", "d", "g"] { try put("audio/\(id).mp3", "not really an mp3") }
    try put("labels/a.json", label(19, 51))
    try put("labels-snapped/a.json", label(20, 50))
    try put("labels/b.json", label(24, 46))
    try put("labels-snapped/b.json", label(25, 45))
  }

  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  private func label(_ start: Double, _ end: Double) -> String {
    #"{"segments": [{"sort": "sponsor", "start": \#(start), "end": \#(end), "confidence": "high"}]}"#
  }

  private func put(_ name: String, _ text: String) throws {
    try Data(text.utf8).write(to: folder.appendingPathComponent(name))
  }

  private struct Shares: Decodable {
    var points: Int
    var within: [Int]
    var share: [Double]
  }

  private struct Report: Decodable {
    var version: Int
    var episodes: Int
    var leftOut: Int
    var reaches: [Double]
    var rule: String
    var edges: Shares
    var random: Shares
    var verdict: String
  }

  private struct Peaks: Decodable {
    var version: Int
    var episodes: [String: Entry]

    struct Entry: Decodable {
      var seconds: Double
      var peaks: [[Double]]
    }
  }

  private func read<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(contentsOf: folder.appendingPathComponent(name)))
  }

  /// The made-up sound of each file, and which files were read.
  private final class Sound: @unchecked Sendable {
    var reads: [String] = []
    var broken: Set<String> = []

    func signal(_ id: String) -> [Float] {
      switch id {
      case "a":
        return EdgeSynth.noise(20, 0.05, seed: 1) + EdgeSynth.noise(30, 0.3, seed: 2)
          + EdgeSynth.noise(20, 0.05, seed: 3)
      case "b":
        return EdgeSynth.tone(25, hz: 440, 0.2) + EdgeSynth.noise(20, 0.2, seed: 4)
          + EdgeSynth.tone(25, hz: 440, 0.2)
      default:
        return EdgeSynth.noise(70, 0.1, seed: 5)
      }
    }

    var reader: EdgeReader {
      EdgeReader(sampleRate: EdgeSynth.rate) { url, feed in
        let id = url.deletingPathExtension().lastPathComponent
        self.reads.append(id)
        if self.broken.contains(id) { throw CocoaError(.fileReadCorruptFile) }
        let samples = self.signal(id)
        for start in stride(from: 0, to: samples.count, by: 3000) {
          feed(Array(samples[start..<min(start + 3000, samples.count)]))
        }
      }
    }
  }

  private func run(
    _ sound: Sound?, _ arguments: [String]? = nil
  ) async -> (code: Int32, out: [String], err: [String]) {
    var out: [String] = []
    var err: [String] = []
    let code = await EdgeCommand.run(
      arguments ?? [folder.path], reader: sound?.reader, out: { out.append($0) },
      err: { err.append($0) })
    return (code, out, err)
  }

  // MARK: The run

  func testItReadsTheShelfWritesBothFilesAndSaysWhatItFound() async throws {
    let sound = Sound()
    let done = await run(sound)
    XCTAssertEqual(done.code, 0, "\(done.err)")
    XCTAssertEqual(sound.reads, ["a", "b", "g"])

    let edges: Peaks = try read("edges.json")
    XCTAssertEqual(edges.version, 1)
    XCTAssertEqual(edges.episodes.keys.sorted(), ["a", "b", "g"])
    XCTAssertEqual(edges.episodes["a"]?.seconds, 70)
    let times = try XCTUnwrap(edges.episodes["a"]).peaks.map { $0[0] }
    XCTAssertEqual(times.count, 2, "\(times)")
    XCTAssertEqual(times[0], 20, accuracy: 1)
    XCTAssertEqual(times[1], 50, accuracy: 1)
    XCTAssertEqual(edges.episodes["g"]?.peaks.count, 0, "a steady sound has no peak")

    let report: Report = try read("edges-report.json")
    XCTAssertEqual(report.version, 1)
    XCTAssertEqual(report.episodes, 2)
    XCTAssertEqual(report.leftOut, 0)
    XCTAssertEqual(report.reaches, [1, 2, 5])
    XCTAssertEqual(report.edges.points, 4)
    XCTAssertEqual(report.edges.within, [4, 4, 4])
    XCTAssertEqual(report.edges.share, [1, 1, 1])
    XCTAssertEqual(report.random.points, 4)
    XCTAssertEqual(report.verdict, report.random.within[0] * 10 <= 4 ? "go" : "no go")
    XCTAssertTrue(report.rule.contains("70%"))

    let said = done.out.joined(separator: "\n")
    XCTAssertTrue(said.contains("4 exact edges in 2 episodes"), said)
    XCTAssertTrue(said.contains("within 1 second of 4 of 4 (100%)"), said)
    XCTAssertTrue(said.contains(report.verdict == "go" ? "Verdict: Go." : "Verdict: No go."), said)
    XCTAssertTrue(said.contains("the shares would be about 10%, 20%, 50%."), said)
    XCTAssertTrue(said.contains("1 shelf episode has no audio file"), said)
  }

  func testAnEpisodeThatIsNotOnTheShelfOrIsInTheExamIsNotRead() async {
    let sound = Sound()
    _ = await run(sound)
    XCTAssertFalse(sound.reads.contains("c"))
    XCTAssertFalse(sound.reads.contains("d"))
  }

  func testNamesThatLeaveTheTeachingFolderAreNeverRead() async throws {
    try put(
      "episodes.json",
      #"{"version": 1, "episodes": [{"id": "a", "file": "audio/a.mp3"}, {"id": "h", "file": "../h.mp3"}, {"id": "i", "file": "/etc/i.mp3"}, {"id": "j", "file": "audio/j.wav"}, {"id": "../k", "file": "audio/a.mp3"}]}"#
    )
    try put("shelf.json", #"{"episodes": ["a", "h", "i", "j", "../k"]}"#)
    try put("audio/j.wav", "not really a wav")
    let sound = Sound()
    let done = await run(sound)
    XCTAssertEqual(done.code, 0, "\(done.err)")
    XCTAssertEqual(sound.reads, ["a"])
    XCTAssertTrue(done.out.joined().contains("1 shelf episode with an MP3 file"), "\(done.out)")
  }

  func testAnotherRunReadsNothingAgainAndWritesTheSameReport() async throws {
    _ = await run(Sound())
    let before: Report = try read("edges-report.json")
    let again = Sound()
    let done = await run(again)
    XCTAssertEqual(done.code, 0)
    XCTAssertEqual(again.reads, [])
    let after: Report = try read("edges-report.json")
    XCTAssertEqual(after.edges.within, before.edges.within)
    XCTAssertEqual(after.random.within, before.random.within)
    XCTAssertEqual(after.verdict, before.verdict)
  }

  func testAStoppedRunCarriesOnWithTheEpisodesThatAreLeft() async throws {
    let sound = Sound()
    sound.broken = ["b"]
    let first = await run(sound)
    XCTAssertEqual(first.code, 1)
    XCTAssertTrue(first.err.contains { $0.hasPrefix("b: could not be read") }, "\(first.err)")
    let kept: Peaks = try read("edges.json")
    XCTAssertEqual(kept.episodes.keys.sorted(), ["a", "g"], "what was done is kept")
    XCTAssertEqual(try read("edges-report.json", as: Report.self).episodes, 1)

    let mended = Sound()
    let second = await run(mended)
    XCTAssertEqual(second.code, 0, "\(second.err)")
    XCTAssertEqual(mended.reads, ["b"])
    XCTAssertEqual(try read("edges-report.json", as: Report.self).episodes, 2)
  }

  func testAnEpisodeWithNoExactEdgeStillGetsItsPeaks() async throws {
    try FileManager.default.removeItem(at: folder.appendingPathComponent("labels-snapped/b.json"))
    _ = await run(Sound())
    XCTAssertEqual(try read("edges.json", as: Peaks.self).episodes["b"]?.peaks.count, 2)
    XCTAssertEqual(try read("edges-report.json", as: Report.self).episodes, 1)
  }

  func testWithNoExactEdgeAtAllTheReportSaysThereIsNoVerdict() async throws {
    for id in ["a", "b"] {
      try FileManager.default.removeItem(at: folder.appendingPathComponent("labels-snapped/\(id).json"))
    }
    let done = await run(Sound())
    XCTAssertEqual(done.code, 0, "\(done.err)")
    let report: Report = try read("edges-report.json")
    XCTAssertEqual(report.verdict, "no verdict")
    XCTAssertEqual(report.edges.points, 0)
    XCTAssertEqual(report.edges.share, [0, 0, 0])
    XCTAssertTrue(done.out.joined(separator: "\n").contains("No exact edge could be measured"), "\(done.out)")
  }

  func testAFileThatIsDamagedOrMadeByAnotherVersionIsMadeAgainWithOneLine() async throws {
    for text in [
      "not json", #"{"version": 2, "episodes": {}}"#,
      #"{"version": 1, "finder": 0, "episodes": {}}"#,
    ] {
      try put("edges.json", text)
      let sound = Sound()
      let done = await run(sound)
      XCTAssertEqual(done.code, 0, text)
      XCTAssertEqual(sound.reads, ["a", "b", "g"], text)
      XCTAssertEqual(done.err.filter { $0.contains("edges.json") }.count, 1, "\(done.err)")
    }
  }

  // MARK: Set-up problems

  private func assertSetUpProblem(
    _ arguments: [String]? = nil, _ words: String, file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    let sound = Sound()
    let done = await run(sound, arguments)
    XCTAssertEqual(done.code, 2, "\(done.err)", file: file, line: line)
    XCTAssertTrue(
      done.err.joined(separator: "\n").contains(words), "\(done.err)", file: file, line: line)
    XCTAssertEqual(
      sound.reads, [], "nothing is read before a set-up problem is said", file: file, line: line)
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: folder.appendingPathComponent("edges.json").path),
      file: file, line: line)
  }

  func testWithoutADecoderItSaysSoAndReadsNothing() async {
    let done = await run(nil)
    XCTAssertEqual(done.code, 2)
    XCTAssertTrue(done.err.joined().contains("Mac"), "\(done.err)")
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: folder.appendingPathComponent("edges.json").path))
  }

  func testTheUsageIsSaidForNoFolderOrAnOptionItDoesNotHave() async {
    await assertSetUpProblem([], "Usage: podcast-teach edges <teaching folder>")
    await assertSetUpProblem(
      [folder.path, "--all"], "Usage: podcast-teach edges <teaching folder>")
    await assertSetUpProblem(
      [folder.path, folder.path], "Usage: podcast-teach edges <teaching folder>")
  }

  func testAFolderThatIsNotThereIsSaid() async {
    await assertSetUpProblem(
      [folder.appendingPathComponent("nope").path], "There is no teaching folder")
  }

  func testWithNoShelfThereIsNothingToMeasure() async throws {
    try FileManager.default.removeItem(at: folder.appendingPathComponent("shelf.json"))
    await assertSetUpProblem(nil, "shelf.json")
  }

  func testWithNoSecondDownloadItPointsAtTheStepThatMakesOne() async throws {
    try FileManager.default.removeItem(at: folder.appendingPathComponent("labels-snapped"))
    await assertSetUpProblem(nil, "second download")
  }

  func testAnExamFileThatCannotBeReadStopsTheRunBecauseTheExamMustStaySealed() async throws {
    try put("exam.json", "nonsense")
    await assertSetUpProblem(nil, "exam.json")
  }
}
