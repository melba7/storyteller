import XCTest

@testable import PodcastTranscripts

/// A recogniser that hears one word every second ("w<second>", starting 0.1 s after the
/// second) in the stretch asked for.
private final class FakeRecogniser: PieceRecogniser, @unchecked Sendable {
  let name = "Fake"
  let version = "1"
  let osVersion = "26.0"
  var duration = 700.0
  var unsupported = false
  private let lock = NSLock()
  private var asked: [(Double, Double)] = []
  var requests: [(Double, Double)] { lock.withLock { asked } }

  func prepare(locale: String) async throws -> String {
    if unsupported { throw TranscriptError.notSupported("Language not supported") }
    return locale
  }

  func duration(of file: URL) throws -> Double { duration }

  func recognise(file: URL, locale: String, from: Double, to: Double) async throws -> [TranscriptWord] {
    lock.withLock { asked.append((from, to)) }
    return (Int(from.rounded(.up))..<Int(to.rounded(.down))).map {
      TranscriptWord(text: "w\($0)", start: Double($0) + 0.1, end: Double($0) + 0.6)
    }
  }
}

final class TranscriptRunnerTests: XCTestCase {
  private var folder: URL!
  private let sha = String(repeating: "ab", count: 32)
  private let audio = URL(fileURLWithPath: "/nowhere/audio.mp3")

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "transcripts-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: folder)
  }

  private var store: TranscriptStore { TranscriptStore(folder: folder, sha256: sha) }

  private func run(
    _ recogniser: FakeRecogniser, stopAfter pieces: Int? = nil
  ) async throws -> RunOutcome {
    let allowed = Allowance(pieces)
    return try await TranscriptRunner.run(
      audio: audio, sha256: sha, locale: "en-US", recogniser: recogniser, store: store,
      shouldContinue: { allowed.take() })
  }

  func testAFullRunWritesTheTranscriptAndRemovesThePartialFile() async throws {
    let outcome = try await run(FakeRecogniser())
    guard case .finished(let transcript) = outcome else { return XCTFail("not finished") }
    XCTAssertEqual(transcript.words.count, 700)
    XCTAssertEqual(Set(transcript.words.map(\.text)).count, 700, "no word doubled")
    XCTAssertEqual(transcript.words.first?.text, "w0")
    XCTAssertEqual(transcript.words.last?.text, "w699")
    XCTAssertEqual(transcript.identity.locale, "en-US")
    XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(sha).transcript.json").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.partialURL.path))
    XCTAssertEqual(store.status(), .done)
    XCTAssertEqual(store.loadTranscript(), transcript)
  }

  func testProgressIsSavedAfterEachPieceAndAStopResumesFromIt() async throws {
    let first = FakeRecogniser()
    let outcome = try await run(first, stopAfter: 2)
    XCTAssertEqual(outcome, .paused(reached: 180))
    let partial = try XCTUnwrap(store.loadPartial())
    XCTAssertEqual(partial.reached, 180)
    XCTAssertEqual(partial.words.count, 180)
    XCTAssertFalse(store.hasTranscript)

    let second = FakeRecogniser()
    let done = try await run(second)
    guard case .finished(let resumed) = done else { return XCTFail("not finished") }
    XCTAssertEqual(second.requests.first?.0, 178, "carries on 2 s before the saved time")
    XCTAssertEqual(second.requests.count, 2)

    let other = folder.appendingPathComponent("other")
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    let whole = try await TranscriptRunner.run(
      audio: audio, sha256: sha, locale: "en-US", recogniser: FakeRecogniser(),
      store: TranscriptStore(folder: other, sha256: sha))
    guard case .finished(let straight) = whole else { return XCTFail("not finished") }
    XCTAssertEqual(resumed.words, straight.words)
    XCTAssertEqual(resumed.lines, straight.lines)
  }

  func testARunUntilTheHeadStopsThereAndTheNextRunResumesAfterIt() async throws {
    let first = FakeRecogniser()
    let outcome = try await TranscriptRunner.run(
      audio: audio, sha256: sha, locale: "en-US", recogniser: first, store: store, until: 180)
    XCTAssertEqual(outcome, .paused(reached: 180))
    XCTAssertEqual(try XCTUnwrap(store.loadPartial()).reached, 180)
    XCTAssertFalse(store.hasTranscript)

    let second = FakeRecogniser()
    let rest = try await TranscriptRunner.run(
      audio: audio, sha256: sha, locale: "en-US", recogniser: second, store: store)
    guard case .finished = rest else { return XCTFail("not finished") }
    XCTAssertEqual(try XCTUnwrap(second.requests.first).0, 178, accuracy: 0.01, "after the head")
  }

  func testARunUntilAPointPastTheEndFinishesTheTranscript() async throws {
    let recogniser = FakeRecogniser()
    recogniser.duration = 100
    let outcome = try await TranscriptRunner.run(
      audio: audio, sha256: sha, locale: "en-US", recogniser: recogniser, store: store, until: 180)
    guard case .finished = outcome else { return XCTFail("\(outcome)") }
  }

  func testACorruptPartialFileMeansStartingOver() async throws {
    try Data("{not json".utf8).write(to: store.partialURL)
    let recogniser = FakeRecogniser()
    let outcome = try await run(recogniser)
    guard case .finished(let transcript) = outcome else { return XCTFail("not finished") }
    XCTAssertEqual(recogniser.requests.first?.0, 0)
    XCTAssertEqual(transcript.words.count, 700)
  }

  func testProgressIsReported() async throws {
    let seen = Collected()
    _ = try await TranscriptRunner.run(
      audio: audio, sha256: sha, locale: "en-US", recogniser: FakeRecogniser(), store: store,
      progress: { seen.add($0) })
    XCTAssertEqual(seen.values, [0, 8, 25, 68, 100])
  }

  func testAnUnsupportedLanguageThrowsBeforeAnyWork() async throws {
    let recogniser = FakeRecogniser()
    recogniser.unsupported = true
    do {
      _ = try await run(recogniser)
      XCTFail("should throw")
    } catch {
      XCTAssertEqual(error as? TranscriptError, .notSupported("Language not supported"))
    }
    XCTAssertTrue(recogniser.requests.isEmpty)
  }

  func testEmptyAudioFails() async throws {
    let recogniser = FakeRecogniser()
    recogniser.duration = 0
    do {
      _ = try await run(recogniser)
      XCTFail("should throw")
    } catch {
      XCTAssertEqual(error as? TranscriptError, .failed("The audio is empty."))
    }
  }

  // MARK: Files

  func testATranscriptSurvivesAJSONRoundTrip() throws {
    let transcript = Transcript(
      identity: TranscriptIdentity(
        locale: "de-DE", recogniser: "R", recogniserVersion: "3", osVersion: "26.1", sha256: sha),
      duration: 12.5,
      lines: [TranscriptLine(start: 0.5, end: 2, text: "Guten Tag.")],
      words: [
        TranscriptWord(text: "Guten", start: 0.5, end: 1),
        TranscriptWord(text: "Tag.", start: 1.1, end: 2),
      ])
    try store.finish(transcript)
    XCTAssertEqual(store.loadTranscript(), transcript)
    let json = try XCTUnwrap(store.transcriptJSON())
    XCTAssertEqual(try JSONDecoder().decode(Transcript.self, from: Data(json.utf8)), transcript)
  }

  func testAnUnreadableTranscriptIsNone() throws {
    try Data("nope".utf8).write(to: store.transcriptURL)
    XCTAssertNil(store.loadTranscript())
    XCTAssertNil(store.transcriptJSON())
    XCTAssertEqual(store.status(), .done, "the file is there; the app shows it and the reader copes")
  }

  func testASkipIsKeptAndReadBack() throws {
    XCTAssertEqual(store.status(), .waiting)
    try store.saveSkip(TranscriptSkip(reason: "Language not supported", locale: "xx"))
    XCTAssertEqual(store.status(), .notSupported(reason: "Language not supported"))
  }

  func testAMissingLanguageNeverErasesOneThatWasNoted() {
    let url = folder.appendingPathComponent("languages.json")
    let notes = TranscriptLanguages(url: url)
    notes.remember("de", for: "e1")
    notes.remember(nil, for: "e1")
    notes.remember("", for: "e1")
    XCTAssertEqual(TranscriptLanguages(url: url).language(for: "e1"), "de")
    notes.remember("fr", for: "e1")
    XCTAssertEqual(notes.language(for: "e1"), "fr")
    notes.remember(nil, for: "e2")
    XCTAssertNil(notes.language(for: "e2"))
  }

  func testLanguagesAreKeptAndPruned() {
    let url = folder.appendingPathComponent("languages.json")
    let notes = TranscriptLanguages(url: url)
    notes.note("de", for: "e1")
    notes.note("fr", for: "e2")
    XCTAssertEqual(TranscriptLanguages(url: url).language(for: "e1"), "de")
    notes.note(nil, for: "e1")
    notes.prune(keeping: ["e1"])
    let again = TranscriptLanguages(url: url)
    XCTAssertNil(again.language(for: "e1"))
    XCTAssertNil(again.language(for: "e2"))
  }
}

private final class Allowance: @unchecked Sendable {
  private let lock = NSLock()
  private var left: Int?
  init(_ pieces: Int?) { left = pieces }
  func take() -> Bool {
    lock.withLock {
      guard let value = left else { return true }
      if value <= 0 { return false }
      left = value - 1
      return true
    }
  }
}

private final class Collected: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [Int] = []
  func add(_ value: Int) { lock.withLock { items.append(value) } }
  var values: [Int] { lock.withLock { items } }
}
