import XCTest

@testable import PodcastTranscripts

final class PartialJSONTests: XCTestCase {
  private var folder: URL!
  private let sha = String(repeating: "cd", count: 32)

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "partial-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private func partial(words: [TranscriptWord]) -> PartialTranscript {
    let identity = TranscriptIdentity(
      locale: "en-US", recogniser: "Fake", recogniserVersion: "1", osVersion: "26.0", sha256: sha)
    return PartialTranscript(identity: identity, duration: 600, reached: 300, words: words)
  }

  func testThereIsNoPartialJSONWithoutAPartialFile() {
    XCTAssertNil(TranscriptStore(folder: folder, sha256: sha).partialJSON())
  }

  func testThereIsNoPartialJSONWhenNoWordWasHeardYet() throws {
    let store = TranscriptStore(folder: folder, sha256: sha)
    try store.savePartial(partial(words: []))
    XCTAssertNil(store.partialJSON())
  }

  func testPartialJSONHoldsTheLinesOfTheWordsSoFar() throws {
    let store = TranscriptStore(folder: folder, sha256: sha)
    let words = [
      TranscriptWord(text: "Hello", start: 0, end: 0.3),
      TranscriptWord(text: "there.", start: 0.4, end: 0.7),
      TranscriptWord(text: "Next", start: 1.0, end: 1.3),
    ]
    try store.savePartial(partial(words: words))
    let json = try XCTUnwrap(store.partialJSON())
    let decoded = try JSONDecoder().decode(Transcript.self, from: Data(json.utf8))
    XCTAssertEqual(decoded.lines.map(\.text), ["Hello there.", "Next"])
    XCTAssertTrue(decoded.words.isEmpty)
  }
}
