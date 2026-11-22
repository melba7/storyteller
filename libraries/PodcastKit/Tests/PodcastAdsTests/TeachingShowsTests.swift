import XCTest

@testable import PodcastAds

/// The table of which feed is which show, as the app sends it.
final class TeachingShowsTests: XCTestCase {
  private var folder: URL!
  override func setUpWithError() throws { folder = try temporaryFolder() }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  func testAnObjectOfTextsIsTheTable() {
    XCTAssertEqual(
      TeachingShows.parse(#"{"show-a.test/feed": "a-id", "b.test/rss": "b-id"}"#),
      ["show-a.test/feed": "a-id", "b.test/rss": "b-id"])
    XCTAssertEqual(TeachingShows.parse("{}"), [:])
  }

  func testKeysAreMadeFeedKeysAndBadEntriesAreLeftOut() {
    let parsed = TeachingShows.parse(
      #"{"https://www.Show-A.test/feed/": "a-id", "": "x", "b.test/rss": "", "c.test/f": 3, "d.test/f": null}"#)
    XCTAssertEqual(parsed, ["show-a.test/feed": "a-id"])
  }

  func testWhatIsNotAnObjectIsNotATable() {
    XCTAssertNil(TeachingShows.parse("[]"))
    XCTAssertNil(TeachingShows.parse("nope"))
    XCTAssertNil(TeachingShows.parse(""))
    XCTAssertNil(TeachingShows.parse(#""text""#))
  }

  func testTheTableIsKeptInTheFolder() throws {
    XCTAssertEqual(TeachingShows.load(from: folder), [:])
    let there = folder.appendingPathComponent("made-now")
    try TeachingShows.save(["a.test/f": "a"], to: there)
    XCTAssertEqual(TeachingShows.load(from: there), ["a.test/f": "a"])
    try TeachingShows.save(["b.test/f": "b"], to: there)
    XCTAssertEqual(TeachingShows.load(from: there), ["b.test/f": "b"], "the new table replaces the old")
  }

  func testADamagedFileIsAnEmptyTable() throws {
    try Data("{ nope".utf8).write(to: folder.appendingPathComponent(TeachingShows.fileName))
    XCTAssertEqual(TeachingShows.load(from: folder), [:])
  }
}
