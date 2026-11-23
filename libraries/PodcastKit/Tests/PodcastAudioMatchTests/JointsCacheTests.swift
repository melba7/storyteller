import XCTest

@testable import PodcastAudioMatch

/// `joints.json`: the joints of each episode's file, found once, so the scorer needs no audio.
final class JointsCacheTests: XCTestCase {
  private var folder: URL!
  private var file: URL { folder.appendingPathComponent(JointsCache.fileName) }

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("joints-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  private func mp3(_ name: String, spliced: Bool) throws -> URL {
    var bytes = Fake.id3(size: 100) + Synth.frames(1500, kbps: 128)
    if spliced { bytes += Synth.frames(500, kbps: 64) + Synth.frames(1500, kbps: 128) }
    let url = folder.appendingPathComponent(name)
    try Data(bytes).write(to: url)
    return url
  }

  private func lines(_ body: (@escaping (String) -> Void) -> Int32) -> (code: Int32, said: [String]) {
    var said: [String] = []
    let code = body { said.append($0) }
    return (code, said)
  }

  func testTheFileHoldsTheJointsOfEachEpisodeAndComesBackTheSame() throws {
    let joints = Joints(times: [12.3, 45.6], seconds: 1234.5, steady: true, overflowed: false)
    try JointsCache(episodes: ["a": joints]).write(to: file)
    let json = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    XCTAssertEqual(json["version"] as? Int, 1)
    XCTAssertEqual(json["finder"] as? Int, JointFinder.version)
    let entry = try XCTUnwrap((json["episodes"] as? [String: [String: Any]])?["a"])
    XCTAssertEqual(entry["seconds"] as? Double, 1234.5)
    XCTAssertEqual(entry["steady"] as? Bool, true)
    XCTAssertEqual(entry["overflowed"] as? Bool, false)
    XCTAssertEqual(entry["times"] as? [Double], [12.3, 45.6])
    let back = JointsCache.load(from: file)
    XCTAssertEqual(back.cache.episodes, ["a": joints])
    XCTAssertNil(back.problem)
  }

  func testAMissingFileIsAnEmptyCacheWithNoComplaint() {
    let back = JointsCache.load(from: file)
    XCTAssertTrue(back.cache.episodes.isEmpty)
    XCTAssertNil(back.problem)
  }

  func testADamagedFileIsIgnoredWithOneLine() throws {
    for text in ["not json", "[]", "{\"version\": 2, \"episodes\": {}}", "{\"version\": 1}", ""] {
      try Data(text.utf8).write(to: file)
      let back = JointsCache.load(from: file)
      XCTAssertTrue(back.cache.episodes.isEmpty, text)
      XCTAssertNotNil(back.problem, text)
      XCTAssertFalse(back.problem?.contains("\n") ?? true, text)
    }
  }

  func testAFileMadeByAnotherFinderVersionOrNoneIsIgnoredWithOneLineAndMadeAgain() throws {
    let entries = "\"episodes\": {\"a\": {\"seconds\": 100, \"steady\": true, \"overflowed\": false, \"times\": [1]}}"
    let other = JointFinder.version + 1
    for head in ["{\"version\": 1, \"finder\": \(other), ", "{\"version\": 1, "] {
      try Data((head + entries + "}").utf8).write(to: file)
      let back = JointsCache.load(from: file)
      XCTAssertTrue(back.cache.episodes.isEmpty, head)
      XCTAssertNotNil(back.problem, head)
      XCTAssertFalse(back.problem?.contains("\n") ?? true, head)
      XCTAssertTrue(back.problem?.contains("finder") ?? false, head)
    }
    // The fill says so once and makes the joints again with the current finder.
    let spliced = try mp3("spliced.mp3", spliced: true)
    let run = lines { say in JointsCache.fill(folder: folder, audio: ["spliced": spliced], say: say) }
    XCTAssertEqual(run.code, 0)
    XCTAssertEqual(Set(JointsCache.load(from: file).cache.episodes.keys), ["spliced"])
  }

  func testAnEntryThatCannotBeUsedIsLeftOutAndTheRestStays() throws {
    let text = """
      {"version": 1, "finder": \(JointFinder.version), "episodes": {
        "good": {"seconds": 100, "steady": true, "overflowed": false, "times": [1, 2]},
        "no-times": {"seconds": 100, "steady": true, "overflowed": false},
        "bad-time": {"seconds": 100, "steady": true, "overflowed": false, "times": [-1]},
        "bad-seconds": {"seconds": 0, "steady": true, "overflowed": false, "times": []}}}
      """
    try Data(text.utf8).write(to: file)
    XCTAssertEqual(Array(JointsCache.load(from: file).cache.episodes.keys), ["good"])
  }

  func testTheFillFindsTheJointsOfEachFileOnceAndKeepsWhatWasThere() throws {
    let plain = try mp3("plain.mp3", spliced: false)
    let spliced = try mp3("spliced.mp3", spliced: true)
    let kept = Joints(times: [1], seconds: 50, steady: false)
    try JointsCache(episodes: ["old": kept]).write(to: file)
    let run = lines { say in
      JointsCache.fill(folder: folder, audio: ["plain": plain, "spliced": spliced], say: say)
    }
    XCTAssertEqual(run.code, 0)
    let cache = JointsCache.load(from: file).cache
    XCTAssertEqual(Set(cache.episodes.keys), ["old", "plain", "spliced"])
    XCTAssertEqual(cache.episodes["old"], kept)
    XCTAssertEqual(cache.episodes["spliced"], ScoreSounds.joints(in: spliced))
    XCTAssertEqual(cache.episodes["spliced"]?.times.count, 2)
    XCTAssertEqual(cache.episodes["plain"]?.times, [])
    XCTAssertTrue(run.said.joined().contains("2"), "\(run.said)")
    // Again: nothing new, and the audio is not read (the files are gone).
    try FileManager.default.removeItem(at: plain)
    try FileManager.default.removeItem(at: spliced)
    let again = lines { say in
      JointsCache.fill(folder: folder, audio: ["plain": plain, "spliced": spliced], say: say)
    }
    XCTAssertEqual(again.code, 0)
    XCTAssertEqual(JointsCache.load(from: file).cache, cache)
  }

  func testAFileThatCannotBeReadIsSaidAndTheOthersAreStillDone() throws {
    let spliced = try mp3("spliced.mp3", spliced: true)
    let gone = folder.appendingPathComponent("gone.mp3")
    let run = lines { say in
      JointsCache.fill(folder: folder, audio: ["gone": gone, "spliced": spliced], say: say)
    }
    XCTAssertEqual(run.code, 0)
    XCTAssertEqual(Set(JointsCache.load(from: file).cache.episodes.keys), ["spliced"])
    XCTAssertTrue(run.said.contains { $0.contains("gone") }, "\(run.said)")
  }

  func testADamagedFileIsSaidAndMadeAgain() throws {
    try Data("junk".utf8).write(to: file)
    let spliced = try mp3("spliced.mp3", spliced: true)
    let run = lines { say in JointsCache.fill(folder: folder, audio: ["spliced": spliced], say: say) }
    XCTAssertEqual(run.code, 0)
    XCTAssertTrue(run.said.contains { $0.contains(JointsCache.fileName) && $0.contains("ignored") })
    XCTAssertEqual(Set(JointsCache.load(from: file).cache.episodes.keys), ["spliced"])
  }

  func testNoAudioMakesNoFile() {
    let run = lines { say in JointsCache.fill(folder: folder, audio: [:], say: say) }
    XCTAssertEqual(run.code, 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
  }

  func testAFolderThatIsNotThereIsASetUpProblem() {
    let missing = folder.appendingPathComponent("nope")
    let run = lines { say in JointsCache.fill(folder: missing, audio: [:], say: say) }
    XCTAssertEqual(run.code, 2)
  }
}
