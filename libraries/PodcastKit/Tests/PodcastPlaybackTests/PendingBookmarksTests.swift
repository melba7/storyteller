import XCTest

@testable import PodcastPlayback

final class PendingBookmarksTests: XCTestCase {
  private func mark(
    _ id: String = "b1", episode: String = "e1", at position: Double = 100,
    created: Double = 1_000_000
  ) -> PendingBookmark {
    PendingBookmark(id: id, episodeId: episode, positionSeconds: position, createdAt: created)
  }

  // MARK: Reading and writing

  func testWhatIsEncodedIsDecodedAgain() {
    let marks = [mark("a"), mark("b", episode: "e2", at: 12.5)]
    XCTAssertEqual(PendingBookmarks.decode(PendingBookmarks.encode(marks)), marks)
  }

  func testTheFileIsAJSONListTheAppCanRead() throws {
    let data = PendingBookmarks.encode([mark("a", episode: "e9", at: 61.5, created: 5)])
    let list = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    XCTAssertEqual(list.count, 1)
    XCTAssertEqual(list[0]["id"] as? String, "a")
    XCTAssertEqual(list[0]["episodeId"] as? String, "e9")
    XCTAssertEqual(list[0]["positionSeconds"] as? Double, 61.5)
    XCTAssertEqual(list[0]["createdAt"] as? Double, 5)
  }

  func testBrokenOrEmptyDataGivesNoBookmarks() {
    XCTAssertEqual(PendingBookmarks.decode(Data()), [])
    XCTAssertEqual(PendingBookmarks.decode(Data("not json".utf8)), [])
    XCTAssertEqual(PendingBookmarks.decode(Data("{\"id\":1}".utf8)), [])
  }

  func testOnlyTheReadableEntriesAreKept() {
    let json = """
      [{"id":"a","episodeId":"e1","positionSeconds":3,"createdAt":9},
       {"id":"b","episodeId":"e1"},
       {"id":"c","episodeId":"e2","positionSeconds":7,"createdAt":9}]
      """
    XCTAssertEqual(PendingBookmarks.decode(Data(json.utf8)).map(\.id), ["a", "c"])
  }

  // MARK: Appending

  func testANewBookmarkGoesAtTheEnd() {
    let result = PendingBookmarks.appending(mark("b", at: 200), to: [mark("a", at: 100)])
    XCTAssertEqual(result.map(\.id), ["a", "b"])
  }

  func testPressingTwiceAtTheSamePlaceKeepsOneBookmark() {
    let first = mark("a", at: 100, created: 1_000)
    let again = mark("b", at: 101.5, created: 2_000)
    XCTAssertEqual(PendingBookmarks.appending(again, to: [first]).map(\.id), ["a"])
  }

  func testTheSamePlaceInAnotherEpisodeOrMuchLaterIsAnotherBookmark() {
    let first = mark("a", episode: "e1", at: 100)
    XCTAssertEqual(
      PendingBookmarks.appending(mark("b", episode: "e2", at: 100), to: [first]).count, 2)
    XCTAssertEqual(PendingBookmarks.appending(mark("c", at: 160), to: [first]).count, 2)
  }

  func testTheSameIdIsNotAddedTwice() {
    let first = mark("a")
    XCTAssertEqual(PendingBookmarks.appending(first, to: [first]).count, 1)
  }

  func testTheListNeverGrowsPastItsLimit() {
    var marks: [PendingBookmark] = []
    for number in 0..<(PendingBookmarks.limit + 20) {
      marks = PendingBookmarks.appending(
        mark("id\(number)", at: Double(number) * 1000), to: marks)
    }
    XCTAssertEqual(marks.count, PendingBookmarks.limit)
    // The oldest go first.
    XCTAssertEqual(marks.last?.id, "id\(PendingBookmarks.limit + 19)")
    XCTAssertEqual(marks.first?.id, "id20")
  }

  func testAPreviewEpisodeCannotBeBookmarked() {
    XCTAssertTrue(PendingBookmarks.canBookmark(episodeId: "3f2a-uuid"))
    XCTAssertFalse(PendingBookmarks.canBookmark(episodeId: "preview:https://x.test/feed#g1"))
    XCTAssertFalse(PendingBookmarks.canBookmark(episodeId: ""))
  }

  // MARK: The file

  private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathComponent("pending-bookmarks.json")
  }

  func testAppendingToAFileThatIsNotThereMakesIt() throws {
    let file = temporaryFile()
    try PendingBookmarks.append(mark("a"), to: file)
    try PendingBookmarks.append(mark("b", at: 500), to: file)
    XCTAssertEqual(PendingBookmarks.load(from: file).map(\.id), ["a", "b"])
  }

  func testTheTextTheAppReadsIsTheListAsJSON() throws {
    let file = temporaryFile()
    XCTAssertEqual(PendingBookmarks.json(from: file), "[]")
    try PendingBookmarks.append(mark("a"), to: file)
    XCTAssertEqual(PendingBookmarks.decode(Data(PendingBookmarks.json(from: file).utf8)).map(\.id), ["a"])
  }

  func testRemovingTheSavedOnesKeepsTheRest() throws {
    let file = temporaryFile()
    try PendingBookmarks.append(mark("a", at: 100), to: file)
    try PendingBookmarks.append(mark("b", at: 500), to: file)
    try PendingBookmarks.append(mark("c", at: 900), to: file)
    try PendingBookmarks.remove(ids: ["a", "c"], from: file)
    XCTAssertEqual(PendingBookmarks.load(from: file).map(\.id), ["b"])
    try PendingBookmarks.remove(ids: ["b"], from: file)
    XCTAssertEqual(PendingBookmarks.load(from: file), [])
    XCTAssertEqual(PendingBookmarks.json(from: file), "[]")
  }

  func testRemovingFromNoFileOrWithUnknownIdsChangesNothing() throws {
    let file = temporaryFile()
    try PendingBookmarks.remove(ids: ["x"], from: file)
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    try PendingBookmarks.append(mark("a"), to: file)
    try PendingBookmarks.remove(ids: ["x"], from: file)
    XCTAssertEqual(PendingBookmarks.load(from: file).map(\.id), ["a"])
  }
}
