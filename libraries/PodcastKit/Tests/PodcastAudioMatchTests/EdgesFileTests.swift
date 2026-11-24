import XCTest

@testable import PodcastAudioMatch

/// `edges.json`: the peaks of each shelf episode, written once and read back the same.
final class EdgesFileTests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "edges-file-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  private var url: URL { folder.appendingPathComponent(EdgesFile.fileName) }

  func testWhatIsWrittenComesBackTheSame() throws {
    let peaks = [EdgePeak(time: 20, strength: 13.95), EdgePeak(time: 50.5, strength: 8)]
    let file = EdgesFile(episodes: [
      "a": EdgesFile.Entry(seconds: 70, peaks: peaks), "b": EdgesFile.Entry(seconds: 5, peaks: []),
    ])
    try file.write(in: folder)
    let back = EdgesFile.load(in: folder)
    XCTAssertNil(back.problem)
    XCTAssertEqual(back.file, file)
    XCTAssertEqual(back.file.episodes["a"]?.edgePeaks, peaks)
    let text = try String(contentsOf: url, encoding: .utf8)
    XCTAssertTrue(text.contains("\"finder\":\(EdgeSound.version)"), text)
    XCTAssertTrue(text.contains("[20,13.95]"), text)
  }

  func testAMissingFileIsEmptyWithNoComplaint() {
    let back = EdgesFile.load(in: folder)
    XCTAssertTrue(back.file.episodes.isEmpty)
    XCTAssertNil(back.problem)
  }

  func testAFileThatCannotBeUsedIsEmptyWithOneLine() throws {
    let bad = [
      "", "not json", "[]", #"{"version": 1, "finder": 1}"#,
      #"{"version": 2, "finder": 1, "episodes": {}}"#,
      #"{"version": 1, "finder": 99, "episodes": {}}"#,
      #"{"version": 1, "finder": 1, "episodes": {"a": {"seconds": 5, "peaks": [[1]]}}}"#,
      #"{"version": 1, "finder": 1, "episodes": {"a": {"seconds": -5, "peaks": []}}}"#,
      #"{"version": 1, "finder": 1, "episodes": {"a": {"peaks": []}}}"#,
    ]
    for text in bad {
      try Data(text.utf8).write(to: url)
      let back = EdgesFile.load(in: folder)
      XCTAssertTrue(back.file.episodes.isEmpty, text)
      XCTAssertNotNil(back.problem, text)
      XCTAssertFalse(back.problem?.contains("\n") ?? true, text)
    }
  }
}
