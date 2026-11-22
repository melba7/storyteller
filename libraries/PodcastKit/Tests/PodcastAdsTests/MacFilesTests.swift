import XCTest

@testable import PodcastAds

/// The two readers of the Mac's files, with the Mac's own text.
final class MacFilesTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_700_000_000)

  func testTheLibraryOfTheMacReadsThroughTheTable() {
    let table = [MacFixtures.showB: "show-b-id"]
    let known = MacFiles.library(data: MacFixtures.libraryData, now: now, showOf: MacFiles.table(table))
    XCTAssertEqual(known.ads.count, 2)
    let everywhere = known.ads.first { $0.scope == "all" }
    XCTAssertEqual(everywhere?.showId, "", "its feed is not in the table")
    XCTAssertEqual(everywhere?.advertiser, "Acme")
    XCTAssertEqual(everywhere?.kind, .ad)
    XCTAssertEqual(everywhere?.seen, 3)
    let own = known.ads.first { $0.scope == "show" }
    XCTAssertEqual(own?.showId, "show-b-id")
    XCTAssertEqual(own?.kind, .ownPlug)
  }

  func testAnAdOfOneShowWhoseFeedIsNotInTheTableIsDropped() {
    let known = MacFiles.library(data: MacFixtures.libraryData, now: now, showOf: MacFiles.table([:]))
    XCTAssertEqual(known.ads.map(\.scope), ["all"])
    XCTAssertEqual(known.ads[0].showId, "")
  }

  func testTheScorecardUsesTheFeedAddressAsTheShow() {
    let known = MacFiles.library(data: MacFixtures.libraryData, now: now, showOf: MacFiles.feedAsShow)
    XCTAssertEqual(
      Set(known.ads.map(\.showId)), ["https://show-a.test/feed", "https://www.Show-B.test/rss/"])
  }

  func testTheHabitsOfTheMacReadThroughTheTable() throws {
    let habits = try XCTUnwrap(
      MacFiles.habits(data: MacFixtures.habitsData, showOf: MacFiles.table([MacFixtures.showA: "a-id"])))
    XCTAssertEqual(habits.shows.map(\.id), ["a-id"], "show B is not in the table")
    XCTAssertTrue(habits.usuallyOpensWithAd(show: "a-id"))
    XCTAssertEqual(habits.openingEnd(show: "a-id"), 40)
    XCTAssertEqual(habits.firstLook(show: "a-id"), 50)
  }

  func testHabitsWithAFeedAddressAsTheId() throws {
    let habits = try XCTUnwrap(MacFiles.habits(data: MacFixtures.habitsData, showOf: MacFiles.feedAsShow))
    XCTAssertEqual(habits.shows.map(\.id), ["https://show-a.test/feed", "https://www.Show-B.test/rss/"])
    XCTAssertEqual(habits.shows[1].opensWithAd, 0)
    XCTAssertNil(habits.shows[1].openingEnds)
  }

  func testAFileOfAnotherShapeIsNotRead() {
    XCTAssertNil(MacFiles.habits(data: Data("[]".utf8), showOf: MacFiles.feedAsShow))
    XCTAssertNil(MacFiles.habits(data: Data(#"{"version": 2, "shows": []}"#.utf8), showOf: MacFiles.feedAsShow))
    XCTAssertNil(MacFiles.habits(data: Data(#"{"version": 1}"#.utf8), showOf: MacFiles.feedAsShow))
    XCTAssertEqual(
      MacFiles.library(data: Data("garbage".utf8), now: now, showOf: MacFiles.feedAsShow).ads.count, 0)
  }

  func testEntriesInThePhonesOwnShapeAreKept() throws {
    let library = #"""
      {"version": 1, "ads": [{"show": "s", "scope": "show", "sort": "sponsor", "who": "A",
        "text": "\#((1...30).map { "w\($0)" }.joined(separator: " "))", "length": 30, "seen": 2}]}
      """#
    let known = MacFiles.library(data: Data(library.utf8), now: now, showOf: MacFiles.table([:]))
    XCTAssertEqual(known.ads.map(\.showId), ["s"])
    let habits = #"{"version": 1, "shows": [{"id": "s", "episodes": 5, "opensWithAd": 5, "openingEnds": 40}]}"#
    let read = try XCTUnwrap(MacFiles.habits(data: Data(habits.utf8), showOf: MacFiles.table([:])))
    XCTAssertTrue(read.usuallyOpensWithAd(show: "s"))
  }

  func testOneBadShowDoesNotSpoilTheOthers() throws {
    let text = #"""
      {"version": 1, "shows": [7, {"feed": "f1", "episodes": "many", "opensWithAd": 1},
        {"feed": "f2", "episodes": 4, "opensWithAd": 0}, {"title": "no feed"}]}
      """#
    let habits = try XCTUnwrap(MacFiles.habits(data: Data(text.utf8), showOf: MacFiles.feedAsShow))
    XCTAssertEqual(habits.shows.map(\.id), ["f2"])
  }
}
