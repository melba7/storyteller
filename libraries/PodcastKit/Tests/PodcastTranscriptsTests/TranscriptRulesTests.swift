import XCTest

@testable import PodcastTranscripts

final class TranscriptRulesTests: XCTestCase {
  private func word(_ text: String, _ start: Double, _ end: Double? = nil) -> TranscriptWord {
    TranscriptWord(text: text, start: start, end: end ?? start + 0.3)
  }

  // MARK: Lines

  func testALineEndsAtSentencePunctuation() {
    let lines = LineRule.lines(from: [
      word("Hello", 0), word("there.", 0.4), word("How", 0.8), word("are", 1.2), word("you?", 1.6),
    ])
    XCTAssertEqual(lines.map(\.text), ["Hello there.", "How are you?"])
    XCTAssertEqual(lines[0].start, 0)
    XCTAssertEqual(lines[0].end, 0.7, accuracy: 0.001)
    XCTAssertEqual(lines[1].start, 0.8)
  }

  func testAClosingQuoteDoesNotHideTheEndOfASentence() {
    XCTAssertTrue(LineRule.endsSentence("done.\""))
    XCTAssertTrue(LineRule.endsSentence("what?)"))
    XCTAssertTrue(LineRule.endsSentence("so…"))
    XCTAssertFalse(LineRule.endsSentence("so,"))
    XCTAssertFalse(LineRule.endsSentence("\""))
    XCTAssertFalse(LineRule.endsSentence(""))
  }

  func testAPauseOfEightTenthsOfASecondEndsALine() {
    // 0.3 to 1.1 is exactly 0.8 s of silence; 1.4 to 2.1 is 0.7 s.
    let lines = LineRule.lines(from: [
      word("one", 0), word("two", 1.1), word("three", 1.8, 2.1), word("four", 2.8),
    ])
    XCTAssertEqual(lines.map(\.text), ["one", "two three four"])
  }

  func testALineIsCutAtTwentyFiveWords() {
    let words = (0..<60).map { word("w\($0)", Double($0) * 0.4) }
    let lines = LineRule.lines(from: words)
    XCTAssertEqual(lines.map { $0.text.split(separator: " ").count }, [25, 25, 10])
  }

  func testNoWordsMakeNoLines() {
    XCTAssertEqual(LineRule.lines(from: []), [])
  }

  // MARK: Pieces and the overlap

  func testThePiecesStartAtTheSavedTimeMinusTheOverlap() throws {
    let first = try XCTUnwrap(Pieces.next(reached: 0, duration: 700))
    XCTAssertEqual(first, PiecePlan(readFrom: 0, readTo: 300, keepFrom: 0))
    let second = try XCTUnwrap(Pieces.next(reached: 300, duration: 700))
    XCTAssertEqual(second, PiecePlan(readFrom: 298, readTo: 600, keepFrom: 300))
    let last = try XCTUnwrap(Pieces.next(reached: 600, duration: 700))
    XCTAssertEqual(last, PiecePlan(readFrom: 598, readTo: 700, keepFrom: 600))
    XCTAssertNil(Pieces.next(reached: 700, duration: 700))
    XCTAssertNil(Pieces.next(reached: 699.995, duration: 700))
    XCTAssertNil(Pieces.next(reached: 0, duration: 0))
  }

  func testTheOverlapsWordsAreNotDoubled() {
    let saved = [word("a", 296), word("b", 298.5), word("c", 299.5, 300.4)]
    // The next piece reads from 298 and hears b and c again, then new words.
    let heard = [word("b", 298.5), word("c", 299.5, 300.4), word("d", 300.5), word("e", 301)]
    let merged = Pieces.merge(saved: saved, new: heard, keepFrom: 300)
    XCTAssertEqual(merged.map(\.text), ["a", "b", "c", "d", "e"])
  }

  func testAWordStartingAtTheSavedTimeIsKept() {
    let merged = Pieces.merge(saved: [], new: [word("x", 300), word("y", 299.99)], keepFrom: 300)
    XCTAssertEqual(merged.map(\.text), ["x"])
  }

  func testProgressIsAPercentage() {
    XCTAssertEqual(Pieces.percent(reached: 0, duration: 100), 0)
    XCTAssertEqual(Pieces.percent(reached: 40, duration: 100), 40)
    XCTAssertEqual(Pieces.percent(reached: 299.9, duration: 700), 42)
    XCTAssertEqual(Pieces.percent(reached: 100, duration: 100), 100)
    XCTAssertEqual(Pieces.percent(reached: 500, duration: 100), 100)
    XCTAssertEqual(Pieces.percent(reached: 10, duration: 0), 0)
  }

  // MARK: Resume

  private let identity = TranscriptIdentity(
    locale: "en-US", recogniser: "Fake", recogniserVersion: "1", osVersion: "26.0",
    sha256: String(repeating: "ab", count: 32))

  func testAMatchingPartialFileIsResumedFrom() {
    let partial = PartialTranscript(
      identity: identity, duration: 700, reached: 300, words: [word("a", 1)])
    let state = Resume.state(partial: partial, identity: identity, duration: 700)
    XCTAssertEqual(state.reached, 300)
    XCTAssertEqual(state.words.count, 1)
  }

  func testAPartialFileOfAnotherRecogniserLanguageOrFileStartsOver() {
    let partial = PartialTranscript(identity: identity, duration: 700, reached: 300, words: [])
    var other = identity
    other.locale = "de-DE"
    XCTAssertEqual(Resume.state(partial: partial, identity: other, duration: 700).reached, 0)
    other = identity
    other.recogniserVersion = "2"
    XCTAssertEqual(Resume.state(partial: partial, identity: other, duration: 700).reached, 0)
    other = identity
    other.sha256 = String(repeating: "cd", count: 32)
    XCTAssertEqual(Resume.state(partial: partial, identity: other, duration: 700).reached, 0)
    XCTAssertEqual(Resume.state(partial: nil, identity: identity, duration: 700).reached, 0)
  }

  func testAPartialFileThatMakesNoSenseStartsOver() {
    let past = PartialTranscript(identity: identity, duration: 700, reached: 9000, words: [])
    XCTAssertEqual(Resume.state(partial: past, identity: identity, duration: 700).reached, 0)
    let negative = PartialTranscript(identity: identity, duration: 700, reached: -5, words: [])
    XCTAssertEqual(Resume.state(partial: negative, identity: identity, duration: 700).reached, 0)
  }

  // MARK: The language

  func testTheLocaleFollowsTheFeedsLanguage() {
    XCTAssertEqual(LocalePick.identifier(feedLanguage: "en-us", phone: "fr-FR"), "en-US")
    XCTAssertEqual(LocalePick.identifier(feedLanguage: "DE", phone: "fr-FR"), "de")
    XCTAssertEqual(LocalePick.identifier(feedLanguage: "pt_br", phone: "fr-FR"), "pt-BR")
    XCTAssertEqual(LocalePick.identifier(feedLanguage: "zh-hans-cn", phone: "fr-FR"), "zh-Hans-CN")
  }

  func testWithoutAFeedLanguageThePhonesIsUsed() {
    XCTAssertEqual(LocalePick.identifier(feedLanguage: nil, phone: "fr-FR"), "fr-FR")
    XCTAssertEqual(LocalePick.identifier(feedLanguage: "  ", phone: "fr-FR"), "fr-FR")
    XCTAssertEqual(LocalePick.identifier(feedLanguage: "x", phone: "fr-FR"), "fr-FR")
    XCTAssertEqual(LocalePick.identifier(feedLanguage: "12-34", phone: "fr-FR"), "fr-FR")
  }
}
