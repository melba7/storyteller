import XCTest

@testable import PodcastAds

/// A stand-in for an error of the model's own types, which has a name and a case.
enum DiaryFakeError: Error { case rateLimited(String) }

/// The ad finder's diary: what it did and which errors it met, with no transcript words.
final class AdDiaryTests: XCTestCase {
  private func object(_ line: String) throws -> [String: Any] {
    try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], line)
  }

  private func numbered(_ count: Int) -> String {
    (1...count).map { "line \($0)" }.joined(separator: "\n") + "\n"
  }

  // MARK: The file's text

  func testTheDiaryKeepsOnlyTheNewestLines() {
    let kept = AdDiary.trimmed(numbered(600), maxLines: 500)
    let lines = kept.split(separator: "\n").map(String.init)
    XCTAssertEqual(lines.count, 500)
    XCTAssertEqual(lines.first, "line 101")
    XCTAssertEqual(lines.last, "line 600")
    XCTAssertTrue(kept.hasSuffix("\n"))
    // A shorter text stays as it is, blank lines go, and the cap is 500 unless told otherwise.
    XCTAssertEqual(AdDiary.trimmed("a\n\nb\n", maxLines: 500), "a\nb\n")
    XCTAssertEqual(AdDiary.trimmed(numbered(10)), numbered(10))
    XCTAssertEqual(AdDiary.trimmed(numbered(501)).split(separator: "\n").count, 500)
    XCTAssertEqual(AdDiary.trimmed(""), "")
  }

  func testAppendingKeepsTheNewestLinesToo() {
    var text = ""
    for number in 1...510 {
      text = AdDiary.appending(
        AdDiary.line(at: Double(number), episodeId: "e1", what: "step \(number)"), to: text)
    }
    let lines = text.split(separator: "\n")
    XCTAssertEqual(lines.count, AdDiary.maxLines)
    XCTAssertTrue(lines.last?.contains("step 510") == true)
    XCTAssertTrue(lines.first?.contains("step 11\"") == true, "\(lines.first ?? "")")
  }

  func testTheSameStepIsNotWrittenTwiceInARow() {
    func add(_ id: String, _ what: String, _ text: String) -> String {
      AdDiary.appending(AdDiary.line(at: 1, episodeId: id, what: what), to: text)
    }
    var text = add("e1", "partial pass: 2 ads", "")
    text = add("e1", "partial pass: 2 ads", text)
    XCTAssertEqual(text.split(separator: "\n").count, 1)
    // Another episode, another step, or the step again after something else are written.
    text = add("e2", "partial pass: 2 ads", text)
    text = add("e2", "partial pass: 3 ads", text)
    text = add("e2", "partial pass: 2 ads", text)
    XCTAssertEqual(text.split(separator: "\n").count, 4)
  }

  // MARK: One line

  func testALineHasNoTranscriptWords() throws {
    let line = AdDiary.line(
      at: 1_763_500_000.1234, episodeId: "3F2A9C1B-77D0-4E0B-9A56-0A1B2C3D4E5F",
      what: "full pass ended: 2 ads, 1 pieces refused")
    XCTAssertFalse(line.contains("\n"))
    let found = try object(line)
    // Only a time, a short episode id, the mark and the kind: no words of the episode.
    XCTAssertEqual(Set(found.keys), ["time", "episode", "what", "kind"])
    XCTAssertEqual(found["kind"] as? String, "diary")
    XCTAssertEqual(found["episode"] as? String, "3F2A9C1B")
    XCTAssertEqual(found["what"] as? String, "full pass ended: 2 ads, 1 pieces refused")
    XCTAssertEqual(try XCTUnwrap(found["time"] as? Double), 1_763_500_000.123, accuracy: 0.0005)
  }

  func testALineHasNoAddressesPathsOrKeys() throws {
    let what = """
      head scan ended: Error Domain=NSURLErrorDomain "x" \
      NSErrorFailingURLStringKey=https://cdn.example.com/a/b.mp3?token=abc \
      file:///var/mobile/Containers/x.mp3 mo@example.com www.example.com \
      \(String(repeating: "k", count: 90)) done
      """
    let line = AdDiary.line(at: 1, episodeId: "e1", what: what)
    for forbidden in ["example.com", "https", "/var", "mo@", "kkkk", "token"] {
      XCTAssertFalse(line.contains(forbidden), "\(forbidden) in \(line)")
    }
    let text = try XCTUnwrap(try object(line)["what"] as? String)
    XCTAssertTrue(text.hasPrefix("head scan ended: Error"), text)
    XCTAssertTrue(text.hasSuffix("done"), text)
  }

  func testALongMarkIsCutAndStaysOneLine() throws {
    let many = (1...100).map { "word\($0)" }.joined(separator: "\n")
    let line = AdDiary.line(at: 1, episodeId: "e1", what: many)
    XCTAssertFalse(line.contains("\n"))
    let text = try XCTUnwrap(try object(line)["what"] as? String)
    XCTAssertLessThanOrEqual(text.count, AdDiary.maxWhatLength)
    XCTAssertTrue(text.hasPrefix("word1 word2"), text)
    let empty = try object(AdDiary.line(at: 1, episodeId: "e1", what: "  \n "))
    XCTAssertEqual(empty["what"] as? String, "(nothing)")
  }

  func testAnEpisodeIdIsShortAndPlain() throws {
    func shown(_ id: String) throws -> String {
      try XCTUnwrap(try object(AdDiary.line(at: 1, episodeId: id, what: "x"))["episode"] as? String)
    }
    XCTAssertEqual(try shown("file-1"), "file-1")
    XCTAssertEqual(try shown("https://example.com/feed/episode-1"), "httpsexa")
    XCTAssertEqual(try shown(""), "")
  }

  func testOnlyADiaryLineIsADiaryLine() {
    XCTAssertTrue(AdDiary.isDiaryLine(AdDiary.line(at: 1, episodeId: "e1", what: "x")))
    XCTAssertTrue(AdDiary.isDiaryLine(#"{"kind": "diary", "what": "x"}"#))
    XCTAssertTrue(AdDiary.isDiaryLine(#"{"kind":"diary"}"#))
    var log = SkipLog()
    log.append(
      SkipLogEntry(
        context: SkipContext(time: 1, episode: "e1"), start: 10, end: 40, kind: .ad,
        confidence: .sure, outcome: .kept))
    XCTAssertFalse(AdDiary.isDiaryLine(log.lines[0]))
    XCTAssertFalse(AdDiary.isDiaryLine("not json diary"))
    XCTAssertFalse(AdDiary.isDiaryLine(""))
  }

  // MARK: The skip log and the diary together

  private func skipLines(_ count: Int) -> [String] {
    var log = SkipLog()
    for number in 1...count {
      log.append(
        SkipLogEntry(
          context: SkipContext(time: Double(number), episode: "e\(number)"), start: 10, end: 40,
          kind: .ad, confidence: .sure, outcome: .kept))
    }
    return log.lines
  }

  func testTheSharedCopyHoldsTheSkipLogThenTheDiary() {
    let skips = skipLines(2)
    let diary = [
      AdDiary.line(at: 1, episodeId: "e1", what: "a"),
      AdDiary.line(at: 2, episodeId: "e1", what: "b"),
    ]
    let shared = AdDiary.shared(
      skipLog: skips.joined(separator: "\n") + "\n", diary: diary.joined(separator: "\n") + "\n")
    XCTAssertEqual(shared, (skips + diary).joined(separator: "\n") + "\n")
    // Either one alone, and nothing at all.
    XCTAssertEqual(
      AdDiary.shared(skipLog: skips.joined(separator: "\n") + "\n", diary: ""),
      skips.joined(separator: "\n") + "\n")
    XCTAssertEqual(
      AdDiary.shared(skipLog: "", diary: diary.joined(separator: "\n") + "\n"),
      diary.joined(separator: "\n") + "\n")
    XCTAssertEqual(AdDiary.shared(skipLog: "", diary: ""), "")
  }

  func testTheSkipLogIgnoresDiaryLinesSoTheSharedCopyReadsLikeTheLog() {
    let skips = skipLines(3)
    let diary = (1...600).map { AdDiary.line(at: Double($0), episodeId: "e1", what: "step \($0)") }
    let shared = AdDiary.shared(
      skipLog: skips.joined(separator: "\n") + "\n", diary: diary.joined(separator: "\n") + "\n")
    let log = SkipLog(text: shared)
    XCTAssertEqual(log.lines, skips, "the diary lines neither count nor push skips out")
    XCTAssertEqual(log.entries.count, 3)
    XCTAssertEqual(SkipLog(text: skips.joined(separator: "\n") + "\n").lines, skips)
  }

  // MARK: Failures by their names

  func testANoteNamesTheErrorAndNotItsWords() {
    XCTAssertEqual(AdDiary.note(for: AdDetectorError.refused), "the model refused a part")
    XCTAssertEqual(AdDiary.note(for: AdDetectorError.tooLong), "a part was too long for the model")
    XCTAssertEqual(
      AdDiary.note(for: AdDetectorError.unavailable(.appleIntelligenceOff)),
      "model unavailable: Apple Intelligence is off")
    // A raw error is named by its type and its case.
    let raw = AdDiary.note(for: DiaryFakeError.rateLimited("they said buy now"))
    XCTAssertTrue(raw.hasSuffix("DiaryFakeError rateLimited"), raw)
    XCTAssertFalse(raw.contains("buy now"))
  }

  func testAFailureThatTheDetectorMadeKeepsTheNamesOfTheErrorItCameFrom() {
    // `AdModelFailure.classify` puts the names of the model's own error at the end of the text.
    let failure = AdModelFailure.classify(DiaryFakeError.rateLimited("they said buy now"))
    guard case .failed(let text) = failure else { return XCTFail("\(failure)") }
    XCTAssertTrue(text.hasSuffix("DiaryFakeError rateLimited]"), text)
    let note = AdDiary.note(for: failure)
    XCTAssertTrue(note.hasPrefix("the model failed: "), note)
    XCTAssertTrue(note.hasSuffix("DiaryFakeError rateLimited"), note)
    XCTAssertFalse(note.contains("buy now"))
    // Words that only look like names are not copied.
    XCTAssertEqual(
      AdDiary.note(for: AdDetectorError.failed("they said buy now (two words)")),
      "the model failed")
    XCTAssertEqual(
      AdDiary.note(for: AdDetectorError.failed("x [model error: not a type name!]")),
      "the model failed")
    XCTAssertEqual(AdDiary.note(for: AdDetectorError.failed("")), "the model failed")
  }
}
