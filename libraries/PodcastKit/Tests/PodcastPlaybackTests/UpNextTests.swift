import XCTest

@testable import PodcastPlayback

final class UpNextTests: XCTestCase {
  private func item(_ id: String, position: Double = 0) -> QueueItem {
    QueueItem(
      id: id, url: "https://cdn.example.com/\(id).mp3", type: "audio/mpeg", title: "Episode \(id)",
      showTitle: "Show", artworkUrl: nil, duration: 600, position: position)
  }

  private func queue(_ ids: String...) -> UpNextQueue { UpNextQueue(items: ids.map { item($0) }) }

  private func ids(_ queue: UpNextQueue) -> [String] { queue.items.map(\.id) }

  // MARK: Adding

  func testPlayNextPutsAnEpisodeAtTheTopAndPlayLastAtTheBottom() {
    var q = queue("a", "b")
    q.add(item("n"), at: .next)
    q.add(item("l"), at: .last)
    XCTAssertEqual(ids(q), ["n", "a", "b", "l"])
  }

  func testAddingAnEpisodeAlreadyQueuedMovesItAndKeepsItOnce() {
    var q = queue("a", "b", "c")
    q.add(item("c"), at: .next)
    XCTAssertEqual(ids(q), ["c", "a", "b"])
    q.add(item("c"), at: .last)
    XCTAssertEqual(ids(q), ["a", "b", "c"])
  }

  func testAddingTakesTheNewDetailsOfAnEpisodeAlreadyQueued() {
    var q = queue("a", "b")
    q.add(item("b", position: 120), at: .last)
    XCTAssertEqual(q.items.last?.position, 120)
  }

  func testTheEpisodePlayingNowIsNotQueued() {
    var q = queue("a")
    q.add(item("p"), at: .next, playingId: "p")
    XCTAssertEqual(ids(q), ["a"])
  }

  func testAQueueBuiltWithRepeatsKeepsTheFirstOfEach() {
    XCTAssertEqual(ids(UpNextQueue(items: [item("a"), item("b"), item("a")])), ["a", "b"])
  }

  // MARK: Moving, removing, clearing

  func testMovingAnItem() {
    var q = queue("a", "b", "c", "d")
    q.move(from: 0, to: 2)
    XCTAssertEqual(ids(q), ["b", "c", "a", "d"])
    q.move(from: 3, to: 0)
    XCTAssertEqual(ids(q), ["d", "b", "c", "a"])
  }

  func testMovingOutsideTheListIsClampedAndAnEmptyQueueIsLeftAlone() {
    var q = queue("a", "b", "c")
    q.move(from: 1, to: 99)
    XCTAssertEqual(ids(q), ["a", "c", "b"])
    q.move(from: -4, to: 1)
    XCTAssertEqual(ids(q), ["c", "a", "b"])
    var empty = UpNextQueue()
    empty.move(from: 0, to: 1)
    XCTAssertTrue(empty.isEmpty)
  }

  func testRemovingOneAndClearing() {
    var q = queue("a", "b", "c")
    q.remove("b")
    q.remove("zzz")
    XCTAssertEqual(ids(q), ["a", "c"])
    q.clear()
    XCTAssertTrue(q.isEmpty)
  }

  // MARK: Playing

  func testAnEpisodeThatStartsPlayingLeavesTheQueue() {
    var q = queue("a", "b", "c")
    q.startedPlaying("b")
    XCTAssertEqual(ids(q), ["a", "c"])
  }

  func testWhenAnEpisodeEndsTheFirstQueuedOneComesOffTheQueue() {
    var q = queue("a", "b")
    XCTAssertEqual(q.takeNext()?.id, "a")
    XCTAssertEqual(ids(q), ["b"])
    XCTAssertEqual(q.takeNext()?.id, "b")
    XCTAssertNil(q.takeNext())
    XCTAssertTrue(q.isEmpty)
  }

  func testAnItemThatCannotBePlayedIsSkipped() {
    var q = queue("a", "bad", "c")
    let next = q.takeNext { $0.id != "a" && $0.id != "bad" }
    XCTAssertEqual(next?.id, "c")
    XCTAssertTrue(q.isEmpty)
  }

  func testPlayingFromAListPutsTheEpisodeThatWasPlayingBackAtTheTopWithItsPlace() {
    var q = queue("a", "b")
    q.startedFromList("x", previous: item("p", position: 321), previousFinished: false)
    XCTAssertEqual(ids(q), ["p", "a", "b"])
    XCTAssertEqual(q.items.first?.position, 321)
  }

  func testAFinishedEpisodeIsNotPutBack() {
    var q = queue("a")
    q.startedFromList("x", previous: item("p", position: 600), previousFinished: true)
    XCTAssertEqual(ids(q), ["a"])
  }

  func testNothingWasPlayingSoNothingIsPutBack() {
    var q = queue("a", "x")
    q.startedFromList("x", previous: nil, previousFinished: false)
    XCTAssertEqual(ids(q), ["a"])
  }

  func testPickingTheQueuedEpisodeThatIsAlreadyPlayingDoesNotQueueItAgain() {
    var q = queue("a")
    q.startedFromList("p", previous: item("p", position: 5), previousFinished: false)
    XCTAssertEqual(ids(q), ["a"])
  }

  func testPickingAQueuedEpisodeRemovesItAndQueuesTheOneThatWasPlaying() {
    var q = queue("a", "b", "c")
    q.startedFromList("b", previous: item("p"), previousFinished: false)
    XCTAssertEqual(ids(q), ["p", "a", "c"])
  }

  // MARK: Where an item plays from

  func testAQueuedItemPlaysFromItsDownloadWhenItHasOne() {
    let file = URL(fileURLWithPath: "/tmp/a.mp3")
    XCTAssertEqual(QueueSource.url(for: item("a"), localFile: file), file)
  }

  func testAnItemWhoseDownloadWasDeletedStreamsFromItsAddress() {
    XCTAssertEqual(
      QueueSource.url(for: item("a"), localFile: nil)?.absoluteString,
      "https://cdn.example.com/a.mp3")
  }

  func testAnItemWithNoFileAndNoUsableAddressHasNoSource() {
    for bad in ["", "not a link", "ftp://example.com/a.mp3", "https://"] {
      var broken = item("a")
      broken.url = bad
      XCTAssertNil(QueueSource.url(for: broken, localFile: nil), bad)
    }
  }

  // MARK: Saving

  func testTheQueueSurvivesARestart() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(
      "up-next-\(UUID().uuidString)/up-next.json")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    var q = queue("a", "b")
    q.add(item("c", position: 42.5), at: .next)
    try q.save(to: file)
    XCTAssertEqual(UpNextQueue.load(from: file), q)
  }

  func testAMissingOrBrokenFileIsAnEmptyQueue() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    XCTAssertTrue(UpNextQueue.load(from: folder.appendingPathComponent("none.json")).isEmpty)
    let broken = folder.appendingPathComponent("broken.json")
    try Data("{nope".utf8).write(to: broken)
    XCTAssertTrue(UpNextQueue.load(from: broken).isEmpty)
  }
}

final class QueueItemChaptersTests: XCTestCase {
  func testChaptersAddressSurvivesSavingAndOldFilesStillRead() throws {
    let item = QueueItem(id: "a", url: "https://x/a.mp3", title: "A", chaptersUrl: "https://x/c.json")
    let data = try JSONEncoder().encode(UpNextQueue(items: [item]))
    XCTAssertEqual(try JSONDecoder().decode(UpNextQueue.self, from: data).items.first?.chaptersUrl, "https://x/c.json")
    let old = Data(
      #"{"items":[{"id":"a","url":"u","type":"","title":"A","showTitle":"","position":0}]}"#.utf8)
    XCTAssertNil(try JSONDecoder().decode(UpNextQueue.self, from: old).items.first?.chaptersUrl)
  }
}
