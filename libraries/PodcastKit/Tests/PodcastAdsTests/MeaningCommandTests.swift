import XCTest

@testable import PodcastAds

final class MeaningCommandTests: XCTestCase {
  private let askVector = [1.0, 0.1, 0, 0]
  private let talkVector = [0.0, 0.1, 1, 0]

  /// The sentence of one made line. Every line has its own numbers, so no two episodes repeat each
  /// other (the trainer leaves out an episode that repeats one on the shelf).
  private func sentence(_ episode: String, _ line: Int, ad: Bool) -> String {
    ad
      ? "Ask \(episode) l\(line) please leave us a review it helps \(episode) l\(line)."
      : "Talk \(episode) l\(line) rivers carry water to the sea at \(episode) l\(line)."
  }

  private func isAd(_ line: Int) -> Bool { (7...11).contains(line) }

  /// A teaching folder of made episodes: twenty lines of ten seconds, lines 8 to 12 (counted from
  /// 1) are a host's ask. `training` ids are plain, `shelf` ids are on the shelf.
  private func folder(
    training: Int = 8, shelf: Int = 2, labels: String = "labels", writeShelf: Bool = true,
    repeatOf: (String, String)? = nil
  ) throws -> (folder: URL, embedder: MadeEmbedder) {
    let root = try temporaryFolder()
    let files = FileManager.default
    for sub in ["transcripts", labels] {
      try files.createDirectory(at: root.appendingPathComponent(sub), withIntermediateDirectories: true)
    }
    var table = Made.table
    table[AdMeaningModel.probeSentences[0]] = [0.5, 0.5, 0.5, 0.5]
    table[AdMeaningModel.probeSentences[1]] = [0.5, -0.5, 0.5, -0.5]
    var entries: [[String: Any]] = []
    let ids = (1...training).map { "t\($0)" } + (0..<shelf).map { "s\($0 + 1)" }
    for id in ids {
      entries.append(["id": id, "feed": "https://feed.example/\(id)", "show": id, "title": id, "seconds": 200])
      var text = ""
      for line in 0..<20 {
        // An episode made to repeat another one has the other's sentences.
        let from = (repeatOf?.0 == id) ? repeatOf!.1 : id
        let said = sentence(from, line, ad: isAd(line))
        table[said] = isAd(line) ? askVector : talkVector
        text += String(format: "[0:%02d:%02d.0] %@\n", line * 10 / 60, line * 10 % 60, said)
      }
      try text.write(
        to: root.appendingPathComponent("transcripts/\(id).txt"), atomically: true, encoding: .utf8)
      let label: [String: Any] = [
        "segments": [["sort": "host_ask", "start": 70.0, "end": 120.0, "confidence": "high"]]
      ]
      try JSONSerialization.data(withJSONObject: label).write(
        to: root.appendingPathComponent("\(labels)/\(id).json"))
    }
    try JSONSerialization.data(withJSONObject: ["episodes": entries]).write(
      to: root.appendingPathComponent("episodes.json"))
    if writeShelf {
      let shelved = ids.filter { $0.hasPrefix("s") }
      try JSONSerialization.data(withJSONObject: ["version": 1, "episodes": shelved]).write(
        to: root.appendingPathComponent("shelf.json"))
    }
    return (root, MadeEmbedder(dimension: 4, revision: 7, table: table))
  }

  private struct Ran {
    var code: Int32
    var out: [String]
    var err: [String]
  }

  private func run(
    _ options: [String], _ folder: URL, embedder: LineEmbedder?, at now: Date = Date(timeIntervalSince1970: 1_000)
  ) -> Ran {
    var out: [String] = []
    var err: [String] = []
    let code = MeaningCommand.run(
      [folder.path] + options, embedder: embedder, now: now, out: { out.append($0) },
      err: { err.append($0) })
    return Ran(code: code, out: out, err: err)
  }

  /// A number read back from the file, whether it was written as a whole number or not.
  private func number(_ value: Any?) -> Double? {
    if let found = value as? Double { return found }
    if let found = value as? Int { return Double(found) }
    return nil
  }

  private func written(_ folder: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: folder.appendingPathComponent("ad-meaning.json"))
    return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  // MARK: A run

  func testARunWritesAModelThePhoneAccepts() throws {
    let made = try folder()
    let ran = run(["--min-episodes", "4"], made.folder, embedder: made.embedder)
    XCTAssertEqual(ran.code, 0, ran.err.joined(separator: "\n"))
    let url = made.folder.appendingPathComponent(AdMeaningModel.fileName)
    let model = try XCTUnwrap(AdMeaningModel.load(from: url))
    XCTAssertEqual(model.dimension, 4)
    XCTAssertEqual(model.revision, 7)
    XCTAssertEqual(model.state(for: made.embedder), .ready)

    let file = try written(made.folder)
    let trained = try XCTUnwrap(file["trained"] as? [String: Any])
    XCTAssertEqual(trained["episodes"] as? Int, 8)
    XCTAssertEqual(trained["shelf"] as? Int, 2)
    XCTAssertEqual(trained["lines"] as? Int, 160)
    XCTAssertEqual(trained["writtenAt"] as? Int, 1_000_000)
    let held = try XCTUnwrap(trained["heldOut"] as? [String: Any])
    XCTAssertEqual(held["episodes"] as? Int, 2)
    XCTAssertEqual(held["shows"] as? Int, 2)
    XCTAssertEqual(number(held["predictedAdSeconds"]), 100)
    XCTAssertEqual(number((held["anyAd"] as? [String: Any])?["precision"]), 1)
    XCTAssertTrue(ran.out.contains { $0.hasPrefix("Check on 2 held-out episodes from 2 shows") }, "\(ran.out)")
    XCTAssertTrue(ran.out.last?.hasPrefix("Wrote ") == true, "\(ran.out)")
  }

  func testASecondRunIsQuickBecauseTheVectorsAreKept() throws {
    let made = try folder()
    XCTAssertEqual(run(["--min-episodes", "4"], made.folder, embedder: made.embedder).code, 0)
    let first = try Data(contentsOf: made.folder.appendingPathComponent("ad-meaning.json"))
    let firstCalls = made.embedder.calls.count
    XCTAssertEqual(firstCalls, 10 * 20 + 2)  // every line once, and the two probes
    XCTAssertTrue(FileManager.default.fileExists(atPath: made.folder.appendingPathComponent("meaning-cache").path))

    XCTAssertEqual(run(["--min-episodes", "4"], made.folder, embedder: made.embedder).code, 0)
    XCTAssertEqual(made.embedder.calls.count - firstCalls, 2, "only the probes are embedded again")
    XCTAssertEqual(try Data(contentsOf: made.folder.appendingPathComponent("ad-meaning.json")), first)
  }

  func testADamagedCacheFileIsEmbeddedAgain() throws {
    let made = try folder()
    _ = run(["--min-episodes", "4"], made.folder, embedder: made.embedder)
    let cache = made.folder.appendingPathComponent("meaning-cache")
    let names = try FileManager.default.contentsOfDirectory(atPath: cache.path).filter { $0.hasPrefix("t3.") }
    XCTAssertEqual(names.count, 1)
    let file = cache.appendingPathComponent(names[0])
    try Data(try Data(contentsOf: file).prefix(10)).write(to: file)
    let before = made.embedder.calls.count
    XCTAssertEqual(run(["--min-episodes", "4"], made.folder, embedder: made.embedder).code, 0)
    XCTAssertEqual(made.embedder.calls.count - before, 20 + 2)
    // And there is still only one cache file for that episode.
    let again = try FileManager.default.contentsOfDirectory(atPath: cache.path).filter { $0.hasPrefix("t3.") }
    XCTAssertEqual(again.count, 1)
  }

  func testAnEpisodeThatRepeatsAShelfEpisodeIsLeftOutOfTraining() throws {
    let made = try folder(repeatOf: ("t1", "s1"))
    let ran = run(["--min-episodes", "4"], made.folder, embedder: made.embedder)
    XCTAssertEqual(ran.code, 0)
    XCTAssertTrue(ran.out.contains { $0.hasPrefix("Left 1 episode out of training") }, "\(ran.out)")
    let trained = try XCTUnwrap(try written(made.folder)["trained"] as? [String: Any])
    XCTAssertEqual(trained["episodes"] as? Int, 7)
  }

  func testTheLabelsFolderCanBeNamed() throws {
    let made = try folder(labels: "labels-snapped")
    let plain = run(["--min-episodes", "4"], made.folder, embedder: made.embedder)
    XCTAssertEqual(plain.code, 0)
    XCTAssertTrue(plain.out.joined().contains("No episode"), "\(plain.out)")
    XCTAssertFalse(FileManager.default.fileExists(atPath: made.folder.appendingPathComponent("ad-meaning.json").path))
    let named = run(["--min-episodes", "4", "--labels", "labels-snapped"], made.folder, embedder: made.embedder)
    XCTAssertEqual(named.code, 0, named.err.joined(separator: "\n"))
    XCTAssertEqual(try XCTUnwrap(try written(made.folder)["trained"] as? [String: Any])["episodes"] as? Int, 8)
  }

  // MARK: Not enough, or not here

  func testTooFewEpisodesWritesNothing() throws {
    let made = try folder()
    let ran = run([], made.folder, embedder: made.embedder)  // 20 are needed by default
    XCTAssertEqual(ran.code, 0)
    XCTAssertTrue(ran.out.joined().contains("Only 8 episodes"), "\(ran.out)")
    XCTAssertFalse(FileManager.default.fileExists(atPath: made.folder.appendingPathComponent("ad-meaning.json").path))
    XCTAssertEqual(made.embedder.calls, [], "nothing is embedded when there is too little to train on")
  }

  func testWithNoShelfNothingIsWritten() throws {
    let made = try folder(writeShelf: false)
    let ran = run(["--min-episodes", "4"], made.folder, embedder: made.embedder)
    XCTAssertEqual(ran.code, 0)
    XCTAssertTrue(ran.out.joined().contains("shelf"), "\(ran.out)")
    XCTAssertFalse(FileManager.default.fileExists(atPath: made.folder.appendingPathComponent("ad-meaning.json").path))
  }

  func testWithoutAMacItSaysSoAndExitsWithTwo() throws {
    let made = try folder()
    let ran = run(["--min-episodes", "4"], made.folder, embedder: nil)
    XCTAssertEqual(ran.code, 2)
    XCTAssertTrue(ran.err.joined().contains("needs a Mac"), "\(ran.err)")
    XCTAssertFalse(FileManager.default.fileExists(atPath: made.folder.appendingPathComponent("ad-meaning.json").path))
    // Even with no folder named: the first thing said is that it needs a Mac.
    var said: [String] = []
    XCTAssertEqual(MeaningCommand.run([], embedder: nil, now: Date(), out: { _ in }, err: { said.append($0) }), 2)
    XCTAssertEqual(said, [MeaningCommand.needsAMac])
  }

  func testAnEmbedderThatGivesNoVectorsIsASetUpProblem() throws {
    let made = try folder()
    let empty = MadeEmbedder(dimension: 4, revision: 7, table: [:])
    let ran = run(["--min-episodes", "4"], made.folder, embedder: empty)
    XCTAssertEqual(ran.code, 2)
    XCTAssertFalse(FileManager.default.fileExists(atPath: made.folder.appendingPathComponent("ad-meaning.json").path))
  }

  func testAnEmbedderWithNoRoomForNumbersIsASetUpProblem() throws {
    let made = try folder()
    for size in [0, -3, AdMeaningModel.maxDimension + 1] {
      let broken = MadeEmbedder(dimension: size, revision: 7, table: made.embedder.known)
      let ran = run(["--min-episodes", "4"], made.folder, embedder: broken)
      XCTAssertEqual(ran.code, 2, "\(size)")
      XCTAssertEqual(broken.calls, [], "\(size)")
    }
  }

  func testBadArgumentsAndFoldersAreSetUpProblems() throws {
    let made = try folder()
    var err: [String] = []
    XCTAssertEqual(MeaningCommand.run([], embedder: made.embedder, now: Date(), out: { _ in }, err: { err.append($0) }), 2)
    XCTAssertTrue(err.joined().contains("Usage"))
    for bad in [["--nope"], ["--min-episodes"], ["--min-episodes", "0"], ["--epochs", "x"], ["--labels"]] {
      XCTAssertEqual(run(bad, made.folder, embedder: made.embedder).code, 2, "\(bad)")
    }
    let nothing = try temporaryFolder()
    let ran = run([], nothing, embedder: made.embedder)
    XCTAssertEqual(ran.code, 2)
    XCTAssertTrue(ran.err.joined().contains("episodes.json"), "\(ran.err)")
  }
}
