import XCTest

@testable import PodcastAds

/// What the Mac's teaching run learned about how each show starts.
final class ShowHabitsTests: XCTestCase {
  private func habits(_ episodes: Int, _ opens: Int, ends: Double? = 40, id: String = "s")
    -> ShowHabits
  {
    var habits = ShowHabits()
    habits.shows = [.init(id: id, episodes: episodes, opensWithAd: opens, openingEnds: ends)]
    return habits
  }

  func testAnUnknownShowSaysNothing() {
    let empty = ShowHabits()
    XCTAssertFalse(empty.usuallyOpensWithAd(show: "s"))
    XCTAssertFalse(empty.startsClean(show: "s"))
    XCTAssertNil(empty.openingEnd(show: "s"))
    XCTAssertFalse(habits(5, 5).usuallyOpensWithAd(show: "other"))
  }

  func testUsuallyOpensWithAdNeedsThreeEpisodesAndThreeInFive() {
    XCTAssertFalse(habits(2, 2).usuallyOpensWithAd(show: "s"))
    XCTAssertTrue(habits(3, 3).usuallyOpensWithAd(show: "s"))
    XCTAssertFalse(habits(3, 1).usuallyOpensWithAd(show: "s"))
    XCTAssertTrue(habits(5, 3).usuallyOpensWithAd(show: "s"))
    XCTAssertFalse(habits(5, 2).usuallyOpensWithAd(show: "s"))
    XCTAssertTrue(habits(10, 6).usuallyOpensWithAd(show: "s"))
    XCTAssertFalse(habits(10, 5).usuallyOpensWithAd(show: "s"))
  }

  func testStartsCleanNeedsFourEpisodesAndNoOpeningAd() {
    XCTAssertFalse(habits(3, 0).startsClean(show: "s"))
    XCTAssertTrue(habits(4, 0).startsClean(show: "s"))
    XCTAssertFalse(habits(20, 1).startsClean(show: "s"))
  }

  func testOpeningEndIsKeptInsideFiveToThreeHundred() {
    XCTAssertEqual(habits(5, 5, ends: 40).openingEnd(show: "s"), 40)
    XCTAssertEqual(habits(5, 5, ends: 1).openingEnd(show: "s"), 5)
    XCTAssertEqual(habits(5, 5, ends: 900).openingEnd(show: "s"), 300)
    XCTAssertNil(habits(5, 5, ends: nil).openingEnd(show: "s"))
    XCTAssertNil(habits(5, 1, ends: 40).openingEnd(show: "s"), "it does not usually open with one")
    XCTAssertNil(habits(2, 2, ends: 40).openingEnd(show: "s"))
  }

  func testTheFirstLookIsTheOpeningEndPlusTenSeconds() {
    XCTAssertEqual(habits(5, 5, ends: 40).firstLook(show: "s"), 50)
    XCTAssertEqual(habits(5, 5, ends: 1).firstLook(show: "s"), 15)
    XCTAssertEqual(habits(5, 5, ends: 900).firstLook(show: "s"), 310)
    XCTAssertNil(habits(5, 5, ends: nil).firstLook(show: "s"))
    XCTAssertNil(habits(5, 1, ends: 40).firstLook(show: "s"))
    XCTAssertNil(ShowHabits().firstLook(show: "s"))
  }

  func testImpossibleNumbersMakeTheShowSayNothing() {
    let bad = [
      habits(-3, 0), habits(5, 6), habits(5, -1), habits(5, 5, ends: .infinity),
      habits(5, 5, ends: .nan), habits(-4, -4),
    ]
    for one in bad {
      XCTAssertFalse(one.usuallyOpensWithAd(show: "s"))
      XCTAssertFalse(one.startsClean(show: "s"))
      XCTAssertNil(one.openingEnd(show: "s"))
    }
  }

  func testDataOfThisFormatAndVersionIsRead() throws {
    let json = #"{"version":1,"shows":[{"id":"s","episodes":5,"opensWithAd":4,"openingEnds":42.5}]}"#
    let read = try XCTUnwrap(ShowHabits(data: Data(json.utf8)))
    XCTAssertTrue(read.usuallyOpensWithAd(show: "s"))
    XCTAssertEqual(read.openingEnd(show: "s"), 42.5)
    XCTAssertNil(ShowHabits(data: Data(#"{"version":2,"shows":[]}"#.utf8)))
    XCTAssertNil(ShowHabits(data: Data("nonsense".utf8)))
    XCTAssertNil(ShowHabits(data: Data(#"{"version":1,"shows":[{"id":"s"}]}"#.utf8)))
  }

  func testLoadAndSave() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathComponent(ShowHabits.fileName)
    XCTAssertEqual(ShowHabits.load(from: url), ShowHabits(), "missing file")
    try habits(5, 4).save(to: url)
    XCTAssertEqual(ShowHabits.load(from: url), habits(5, 4))
    try Data("{".utf8).write(to: url)
    XCTAssertEqual(ShowHabits.load(from: url), ShowHabits(), "unreadable file")
    try Data(#"{"version":9,"shows":[]}"#.utf8).write(to: url)
    XCTAssertEqual(ShowHabits.load(from: url), ShowHabits(), "another version")
  }

  func testFileName() { XCTAssertEqual(ShowHabits.fileName, "show-habits.json") }
}
