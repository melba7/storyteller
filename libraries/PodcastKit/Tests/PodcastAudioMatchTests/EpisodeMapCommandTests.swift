import XCTest

@testable import PodcastAudioMatch

/// `podcast-ads --map`: an MP3 file and its marks in, the map's file out.
final class EpisodeMapCommandTests: XCTestCase {
  private var folder: URL!
  private let sha = String(repeating: "c", count: 64)

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "map-command-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

  private func path(_ name: String) -> String { folder.appendingPathComponent(name).path }

  private func write(_ name: String, _ data: Data) throws {
    try data.write(to: folder.appendingPathComponent(name))
  }

  private func run(_ arguments: [String]) -> (code: Int32, said: [String]) {
    var said: [String] = []
    let code = EpisodeMapCommand.run(arguments) { said.append($0) }
    return (code, said)
  }

  func testItWritesTheMapOfTheFileWithItsMarks() throws {
    try write("a.mp3", Data(Fake.id3(size: 50) + Marked.frames(0..<300)))
    try write("marks.json", Data(#"[{"start": 2.0, "end": 5.5, "kind": "promo"}]"#.utf8))
    let made = run([
      path("a.mp3"), "--out", path("map.json"), "--marks", path("marks.json"), "--sha256", sha,
      "--feed", "https://show.test/rss", "--guid", "g1",
    ])
    XCTAssertEqual(made.code, 0)
    XCTAssertEqual(made.said, ["Map written: 300 frames, 1 marks, 1 KB."])
    let map = try XCTUnwrap(EpisodeMap(data: Data(contentsOf: folder.appendingPathComponent("map.json"))))
    XCTAssertEqual(map.frames.count, 300)
    XCTAssertEqual(map.sha256, sha)
    XCTAssertEqual(map.feed, "https://show.test/rss")
    XCTAssertEqual(map.guid, "g1")
    XCTAssertEqual(map.marks, [EpisodeMapMark(start: 2.0, end: 5.5, kind: "promo")])
  }

  func testAFileThatIsNotMP3WritesNothingAndSaysSo() throws {
    try write("a.mp3", Data(repeating: 9, count: 4000))
    try write("marks.json", Data("[]".utf8))
    let made = run([path("a.mp3"), "--out", path("map.json"), "--marks", path("marks.json"), "--sha256", sha])
    XCTAssertEqual(made.code, 1)
    XCTAssertEqual(made.said.count, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: path("map.json")))
  }

  func testMarksThatCannotBeReadWriteNothing() throws {
    try write("a.mp3", Data(Marked.frames(0..<300)))
    try write("marks.json", Data("{}".utf8))
    let made = run([path("a.mp3"), "--out", path("map.json"), "--marks", path("marks.json"), "--sha256", sha])
    XCTAssertEqual(made.code, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: path("map.json")))
  }

  func testAWrongCommandIsExitTwo() {
    XCTAssertEqual(run([]).code, 2)
    XCTAssertEqual(run([path("a.mp3"), "--out", path("map.json")]).code, 2)
    XCTAssertEqual(
      run([path("a.mp3"), "--out", path("m"), "--marks", path("k"), "--sha256", "abc"]).code, 2)
    XCTAssertEqual(
      run([path("a.mp3"), "--out", path("m"), "--marks", path("k"), "--sha256", sha, "--loud"]).code, 2)
  }
}
