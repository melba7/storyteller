import XCTest

@testable import PodcastTranscripts

final class WordTimesTests: XCTestCase {
  private func transcript() -> Transcript {
    let identity = TranscriptIdentity(
      locale: "en-US", recogniser: "Fake", recogniserVersion: "1", osVersion: "26.0",
      sha256: String(repeating: "ab", count: 32))
    let words = [
      TranscriptWord(text: "Hello", start: 0.0, end: 0.3),
      TranscriptWord(text: "there.", start: 0.4, end: 0.71234),
      TranscriptWord(text: "A", start: 5.0, end: 5.2),
      TranscriptWord(text: "new", start: 5.3, end: 5.5),
      TranscriptWord(text: "line.", start: 5.6, end: 6.0449),
    ]
    return Transcript(
      identity: identity, duration: 10, lines: LineRule.lines(from: words), words: words)
  }

  func testTheTimesOfEachWordAndEachLineAreKeptWithoutTheText() {
    let times = WordTimes(transcript())
    XCTAssertEqual(times.version, WordTimes.currentVersion)
    XCTAssertEqual(times.duration, 10)
    XCTAssertEqual(times.words.count, 5)
    XCTAssertEqual(times.words[1], [0.4, 0.712])
    // A line is where the line's first word starts and where its last word ends.
    XCTAssertEqual(times.lines, [[0.0, 0.712], [5.0, 6.045]])
  }

  func testTheFileIsReadBackAsItWasWritten() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "words-\(UUID().uuidString).words.json")
    defer { try? FileManager.default.removeItem(at: url) }
    let times = WordTimes(transcript())
    try times.write(to: url)
    let loaded = try JSONDecoder().decode(WordTimes.self, from: Data(contentsOf: url))
    XCTAssertEqual(loaded, times)
    let text = try String(contentsOf: url, encoding: .utf8)
    XCTAssertFalse(text.contains("Hello"), "the side file holds times only, never the words")
  }

  func testNoPartFileIsLeftBehind() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "words-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try WordTimes(transcript()).write(to: folder.appendingPathComponent("a.words.json"))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["a.words.json"])
  }
}
