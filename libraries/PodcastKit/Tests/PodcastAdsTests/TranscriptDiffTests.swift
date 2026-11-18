import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// Words the publisher's transcript does not have are inserted audio (N3).
final class TranscriptDiffTests: XCTestCase {
  /// The publisher's words "t0 t1 ...", from `from`.
  private func theirs(_ count: Int, from: Int = 0) -> [String] {
    (from..<(from + count)).map { "t\($0)" }
  }

  /// `count` words of inserted audio "ad0 ad1 ...", from `from`.
  private func spot(_ count: Int, from: Int = 0) -> [String] {
    (from..<(from + count)).map { "ad\($0)" }
  }

  /// The texts as our timed words, `step` seconds each, one right after the other.
  private func timed(_ texts: [String], step: Double = 0.5) -> [TranscriptWord] {
    texts.enumerated().map {
      TranscriptWord(text: $0.element, start: Double($0.offset) * step, end: Double($0.offset + 1) * step)
    }
  }

  // MARK: The stretches

  func testFortyAdWordsThenTheirWordsWithThreeChangedIsOneStretch() throws {
    var ours = spot(40) + theirs(200)
    for place in [50, 100, 150] { ours[40 + place] = "changed\(place)" }
    let words = timed(ours)
    let found = try XCTUnwrap(TranscriptDiff.inserted(ours: words, theirs: theirs(200)))
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found.first?.words, 0..<40)
    XCTAssertEqual(found.first?.start, 0)
    XCTAssertEqual(found.first?.end, words[39].end)
  }

  func testAStretchOfTwelveWordsIsNotReported() throws {
    let words = timed(spot(12) + theirs(200))
    XCTAssertEqual(try XCTUnwrap(TranscriptDiff.inserted(ours: words, theirs: theirs(200))), [])
  }

  func testAStretchThatIsTooShortInTimeIsNotReported() throws {
    // 25 words in 2.5 seconds: enough words, not enough time.
    let words = timed(spot(25), step: 0.1) + timed(theirs(200), step: 0.5).map {
      TranscriptWord(text: $0.text, start: $0.start + 2.5, end: $0.end + 2.5)
    }
    XCTAssertEqual(try XCTUnwrap(TranscriptDiff.inserted(ours: words, theirs: theirs(200))), [])
  }

  func testAStretchInTheMiddleHasItsOwnPlace() throws {
    let words = timed(theirs(100) + spot(30) + theirs(100, from: 100))
    let found = try XCTUnwrap(TranscriptDiff.inserted(ours: words, theirs: theirs(200)))
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found.first?.words, 100..<130)
    XCTAssertEqual(found.first?.start, words[100].start)
    XCTAssertEqual(found.first?.end, words[129].end)
  }

  func testTwoStretchesAreTwo() throws {
    let words = timed(spot(30) + theirs(100) + spot(30, from: 100) + theirs(100, from: 100))
    let found = try XCTUnwrap(TranscriptDiff.inserted(ours: words, theirs: theirs(200)))
    XCTAssertEqual(found.map(\.words), [0..<30, 130..<160])
  }

  func testAStretchThatRunsToTheEndOfOurWordsIsNotReported() throws {
    // A head that is still downloading: more words may follow, so the end is not known.
    let words = timed(theirs(200) + spot(40))
    XCTAssertEqual(try XCTUnwrap(TranscriptDiff.inserted(ours: words, theirs: theirs(200))), [])
  }

  func testCaseAndPunctuationDoNotMatter() throws {
    let spelled = theirs(100).map { $0.uppercased() + "," }
    let words = timed(spot(30) + spelled)
    let found = try XCTUnwrap(TranscriptDiff.inserted(ours: words, theirs: theirs(100)))
    XCTAssertEqual(found.map(\.words), [0..<30])
  }

  func testARepeatedPhraseDoesNotConfuseTheAlignment() throws {
    let phrase = ["so", "thats", "the", "end", "of"]
    let published = theirs(60) + phrase + theirs(60, from: 60) + phrase + theirs(60, from: 120)
    let ours = theirs(60) + phrase + spot(30) + theirs(60, from: 60) + phrase + theirs(60, from: 120)
    let found = try XCTUnwrap(TranscriptDiff.inserted(ours: timed(ours), theirs: published))
    XCTAssertEqual(found.map(\.words), [65..<95])
  }

  func testTheirTranscriptHavingMoreThanOursIsFine() throws {
    // Our words are the first minutes of a long episode.
    let ours = timed(spot(40) + theirs(150))
    let found = try XCTUnwrap(TranscriptDiff.inserted(ours: ours, theirs: theirs(3000)))
    XCTAssertEqual(found.map(\.words), [0..<40])
  }

  // MARK: A transcript that is not the same show

  func testUnderHalfOfOurWordsInTheirsIsNil() {
    // 30 of our 100 words are theirs.
    let words = timed(theirs(30) + spot(70))
    XCTAssertNil(TranscriptDiff.inserted(ours: words, theirs: theirs(30)))
  }

  func testNoWordsOfOursIsNil() {
    XCTAssertNil(TranscriptDiff.inserted(ours: [], theirs: theirs(100)))
    XCTAssertNil(TranscriptDiff.inserted(ours: timed(theirs(100)), theirs: []))
  }

  func testMoreThanHalfOfOursNotInTheirsIsNilToo() {
    // More than half of our words not in theirs says the transcript is of something else (or was
    // made from this same file), not that the episode is mostly ads.
    let words = timed(spot(150) + theirs(100))
    XCTAssertNil(TranscriptDiff.inserted(ours: words, theirs: theirs(100)))
  }

  // MARK: Reading a transcript file

  func testVTTLosesItsHeaderNotesIdsTimesAndTags() {
    let vtt = """
      WEBVTT

      NOTE made by a machine
      second line of the note

      intro-1
      00:00:01.000 --> 00:00:04.000
      <v Sam>Hello and welcome, to the show.

      00:00:04.500 --> 00:00:07.000 align:start
      It's <c.yellow>good</c> to be here.<00:00:06.000>
      """
    XCTAssertEqual(
      TranscriptDiff.plainWords(vtt, type: "text/vtt"),
      ["hello", "and", "welcome", "to", "the", "show", "its", "good", "to", "be", "here"])
  }

  func testSRTLosesNumbersTimesAndSpeakerLabels() {
    let srt = """
      1
      00:00:01,000 --> 00:00:04,000
      Sam: Hello and welcome.

      2
      00:00:04,500 --> 00:00:07,000
      SPEAKER 2: Thanks for having me.
      """
    XCTAssertEqual(
      TranscriptDiff.plainWords(srt, type: "application/x-subrip"),
      ["hello", "and", "welcome", "thanks", "for", "having", "me"])
  }

  func testJSONKeepsTheBodiesAndNotTheSpeakersOrTimes() {
    let json = """
      {"version":"1.0.0","segments":[
        {"speaker":"Sam","startTime":1.0,"endTime":4.0,"body":"Hello and welcome."},
        {"speaker":"Jo","startTime":4.5,"endTime":7,"body":"Thanks for having me."}]}
      """
    XCTAssertEqual(
      TranscriptDiff.plainWords(json, type: "application/json"),
      ["hello", "and", "welcome", "thanks", "for", "having", "me"])
  }

  func testJSONThatIsNotTranscriptGivesNothing() {
    XCTAssertEqual(TranscriptDiff.plainWords("{not json", type: "application/json"), [])
    XCTAssertEqual(TranscriptDiff.plainWords("[1, 2]", type: "application/json"), [])
    XCTAssertEqual(TranscriptDiff.plainWords("{\"segments\": 3}", type: "application/json"), [])
  }

  func testHTMLAndPlainTextLoseTheirTags() {
    XCTAssertEqual(
      TranscriptDiff.plainWords("<p>Hello <b>big</b> world &amp; all.</p>", type: "text/html"),
      ["hello", "big", "world", "all"])
    XCTAssertEqual(
      TranscriptDiff.plainWords("Hello there.\nGeneral Kenobi.", type: "text/plain"),
      ["hello", "there", "general", "kenobi"])
  }

  func testALineOfDigitsIsKeptUnlessATimeFollowsIt() {
    XCTAssertEqual(
      TranscriptDiff.plainWords("The year was\n1984\nand then", type: "text/plain"),
      ["the", "year", "was", "1984", "and", "then"])
  }

  func testAnEmptyFileGivesNothing() {
    XCTAssertEqual(TranscriptDiff.plainWords("", type: "text/vtt"), [])
    XCTAssertEqual(TranscriptDiff.plainWords("WEBVTT\n\n", type: "text/vtt"), [])
  }
}
