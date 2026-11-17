import XCTest

@testable import PodcastChapters

final class ChapterJSONTests: XCTestCase {
  func parse(_ text: String) -> [Chapter] { ChapterJSON.parse(Data(text.utf8)) }

  func testReadsTheFormatsFields() {
    let chapters = parse(
      """
      {"version": "1.2.0", "chapters": [
        {"startTime": 0, "title": "Start", "img": "https://x.test/a.jpg", "url": "https://x.test/p"},
        {"startTime": 94.5, "title": "Donation", "endTime": 120}
      ]}
      """)
    XCTAssertEqual(chapters.count, 2)
    XCTAssertEqual(chapters[0].imageURL, "https://x.test/a.jpg")
    XCTAssertEqual(chapters[0].url, "https://x.test/p")
    XCTAssertEqual(chapters[1].start, 94.5)
    XCTAssertEqual(chapters[1].end, 120)
  }

  func testSilentMarkersAreLeftOut() {
    let chapters = parse(
      """
      {"version":"1.2.0","chapters":[{"startTime":0,"title":"A"},
      {"startTime":30,"title":"hidden","toc":false},{"startTime":60,"title":"B","toc":true}]}
      """)
    XCTAssertEqual(chapters.map(\.title), ["A", "B"])
  }

  func testOrdersAndNamesAndDropsBadEntries() {
    let chapters = parse(
      """
      {"chapters":[{"startTime":50},{"startTime":"10","title":"  First "},
      {"startTime":-5,"title":"neg"},{"title":"no time"},{"startTime":10,"title":"dup"},
      {"startTime":70,"endTime":60,"title":"bad end","img":"ftp://x/y"}]}
      """)
    XCTAssertEqual(chapters.map(\.title), ["First", "Chapter 2", "bad end"])
    XCTAssertNil(chapters[2].end)
    XCTAssertNil(chapters[2].imageURL)
  }

  func testAChapterStartingBeyondAnySaneEpisodeIsDroppedInsteadOfCrashing() {
    let chapters = parse(
      """
      {"chapters":[{"startTime":5,"title":"ok"},{"startTime":1e300,"title":"huge"},
      {"startTime":1e16,"title":"big"}]}
      """)
    XCTAssertEqual(chapters.map(\.title), ["ok"])
    XCTAssertEqual(ChapterList.tidy([Chapter(start: 1e300, title: "x")]).count, 0)
    // The key never traps, even for a chapter built by hand.
    XCTAssertEqual(Chapter(start: 1e300, title: "x").key, 10_000_000_000)
  }

  func testNotAChaptersFileGivesNone() {
    XCTAssertTrue(parse("").isEmpty)
    XCTAssertTrue(parse("[1,2]").isEmpty)
    XCTAssertTrue(parse("{\"chapters\": 4}").isEmpty)
    XCTAssertTrue(parse("<html>").isEmpty)
  }

  func testTheFeedsChaptersWinAndTakeTheFilesPictures() {
    let art = Data([1, 2, 3])
    let feed = [Chapter(start: 0, title: "A"), Chapter(start: 60, title: "B", imageURL: "https://i")]
    let file = [Chapter(start: 0.4, title: "x", imageData: art), Chapter(start: 60, title: "y", imageData: art)]
    let chosen = ChapterList.choose(feed: feed, file: file)
    XCTAssertEqual(chosen.map(\.title), ["A", "B"])
    XCTAssertEqual(chosen[0].imageData, art)
    XCTAssertNil(chosen[1].imageData)
    XCTAssertEqual(ChapterList.choose(feed: [], file: file), file)
  }
}
