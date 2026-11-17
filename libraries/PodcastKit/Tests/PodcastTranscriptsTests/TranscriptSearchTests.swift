import XCTest

@testable import PodcastTranscripts

final class TranscriptSearchTests: XCTestCase {
  private func lines(_ texts: [String]) -> [TranscriptLine] {
    texts.enumerated().map { TranscriptLine(start: Double($0.offset) * 10, end: Double($0.offset) * 10 + 9, text: $0.element) }
  }

  func testNormalisingFoldsCaseAccentsAndPunctuation() {
    XCTAssertEqual(TranscriptSearch.normalise("  Café,  DON'T   stop!\n"), "cafe dont stop")
    XCTAssertEqual(TranscriptSearch.normalise("Zoë’s “Naïve” idea…"), "zoes naive idea")
  }

  func testAQueryUnderThreeCharactersFindsNothing() {
    let found = TranscriptSearch.search("a!", in: lines(["a b c", "ab"]))
    XCTAssertTrue(found.isEmpty)
    XCTAssertTrue(TranscriptSearch.search("  ", in: lines(["anything"])).isEmpty)
    XCTAssertEqual(TranscriptSearch.search("cat", in: lines(["the cat sat"])).count, 1)
  }

  func testAPhraseMatchesIgnoringCaseAccentsAndPunctuation() {
    let found = TranscriptSearch.search("cafe au lait", in: lines(["One.", "We had a Café au lait, then left.", "Two."]))
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found[0].start, 10)
    XCTAssertEqual(found[0].text, "We had a Café au lait, then left.")
    XCTAssertEqual(found[0].before, "One.")
    XCTAssertEqual(found[0].after, "Two.")
  }

  func testThePhraseNeedsWholeWords() {
    XCTAssertTrue(TranscriptSearch.search("cat", in: lines(["a concatenation"])).isEmpty)
  }

  func testTheFirstAndLastLinesHaveOneSideOfContext() {
    let found = TranscriptSearch.search("needle", in: lines(["needle here", "x", "also needle"]))
    XCTAssertEqual(found.count, 2)
    XCTAssertEqual(found[0].before, "")
    XCTAssertEqual(found[0].after, "x")
    XCTAssertEqual(found[1].before, "x")
    XCTAssertEqual(found[1].after, "")
  }

  func testAllTheWordsAreUsedOnlyWhenThePhraseIsNowhereInTheEpisode() {
    let apart = lines(["the red fox", "jumped over the blue", "red and blue are colours"])
    // "blue red" is no phrase anywhere, so lines holding both words match.
    let found = TranscriptSearch.search("blue red", in: apart)
    XCTAssertEqual(found.map(\.start), [20])
    // "red fox" is a phrase in line 0; the all-words fallback is not used.
    let phrase = TranscriptSearch.search("red fox", in: lines(["the red fox", "fox and red"]))
    XCTAssertEqual(phrase.map(\.start), [0])
  }

  func testAtMostThreeHitsPerEpisode() {
    let many = lines(Array(repeating: "banana bread", count: 8))
    XCTAssertEqual(TranscriptSearch.search("banana", in: many).map(\.start), [0, 10, 20])
  }

  func testAtMostFiftyHitsInAll() {
    let episodes = (0..<30).map { n in
      (id: "e\(n)", lines: lines(["banana one", "banana two"]))
    }
    let found = TranscriptSearch.search("banana", episodes: episodes)
    XCTAssertEqual(found.map(\.hits.count).reduce(0, +), 50)
    XCTAssertEqual(found.count, 25)
  }

  func testEpisodesWithoutHitsAreLeftOut() {
    let found = TranscriptSearch.search(
      "banana", episodes: [(id: "a", lines: lines(["apple"])), (id: "b", lines: lines(["banana split"]))])
    XCTAssertEqual(found.map(\.episodeId), ["b"])
  }
}
