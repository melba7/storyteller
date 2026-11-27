import XCTest

@testable import PodcastDownloads

final class DownloadStoreTests: XCTestCase {
  private var root: URL!
  private let sha = String(repeating: "ab", count: 32)

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "downloads-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: root)
  }

  private func entry(_ id: String, _ state: DownloadState) -> DownloadEntry {
    DownloadEntry(
      episodeId: id, url: "https://cdn.example.com/\(id).mp3", fileExtension: "mp3", state: state,
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
  }

  /// Puts a finished file through the same steps a download takes.
  @discardableResult
  private func finish(_ store: DownloadStore, _ id: String, bytes: Int = 5) throws -> DownloadEntry {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data(repeating: 1, count: bytes).write(to: temp)
    let staged = try store.stage(temp, episodeId: id)
    return try store.install(
      episodeId: id, staged: staged, sha256: sha, fileExtension: "mp3", bytes: Int64(bytes),
      date: Date(timeIntervalSince1970: 1_700_000_100))
  }

  // MARK: The index

  func testTheIndexSurvivesARestart() throws {
    let store = try DownloadStore(root: root)
    try store.put(entry("a", .queued))
    try store.put(entry("b", .downloading(bytes: 10, expected: 100)))
    try store.put(entry("c", .failed(reason: "Stopped, tap to try again")))
    try finish(store, "d")

    let reopened = try DownloadStore(root: root)
    XCTAssertEqual(reopened.entries(), store.entries())
    XCTAssertEqual(reopened.entries().map(\.episodeId), ["a", "b", "c", "d"])
    XCTAssertEqual(
      reopened.entry(for: "d")?.state,
      .downloaded(
        file: "\(sha).mp3", sha256: sha, bytes: 5, date: Date(timeIntervalSince1970: 1_700_000_100)))
    XCTAssertEqual(reopened.entry(for: "b")?.state, .downloading(bytes: 10, expected: 100))
  }

  func testTheAutomaticFlagSurvivesARestartAndAnOldIndexMeansFalse() throws {
    let store = try DownloadStore(root: root)
    var auto = entry("a", .queued)
    auto.automatic = true
    try store.put(auto)
    try store.put(entry("b", .queued))
    let reopened = try DownloadStore(root: root)
    XCTAssertEqual(reopened.entry(for: "a")?.automatic, true)
    XCTAssertEqual(reopened.entry(for: "b")?.automatic, false)

    // An index from before the flag existed.
    let old = """
      {"version":1,"entries":[{"episodeId":"c","url":"https://x.example/c.mp3",\
      "fileExtension":"mp3","state":{"kind":"queued"},"updatedAt":"2026-11-17T10:00:00Z"}]}
      """
    try Data(old.utf8).write(to: root.appendingPathComponent("index.json"))
    XCTAssertEqual(try DownloadStore(root: root).entry(for: "c")?.automatic, false)
  }

  func testThePlainAddressSurvivesARestartAndAnOldIndexHasNone() throws {
    let store = try DownloadStore(root: root)
    var withPlain = entry("a", .queued)
    withPlain.plainURL = "http://x.example/a.mp3"
    try store.put(withPlain)
    try store.put(entry("b", .queued))
    let reopened = try DownloadStore(root: root)
    XCTAssertEqual(reopened.entry(for: "a")?.plainURL, "http://x.example/a.mp3")
    XCTAssertNil(reopened.entry(for: "b")?.plainURL)
  }

  func testFinishingKeepsTheAutomaticFlag() throws {
    let store = try DownloadStore(root: root)
    var auto = entry("a", .queued)
    auto.automatic = true
    try store.put(auto)
    XCTAssertTrue(try finish(store, "a").automatic)
  }

  func testTheAheadFlagSurvivesARestartAndFinishingAndAnOldIndexMeansFalse() throws {
    let store = try DownloadStore(root: root)
    var ahead = entry("a", .queued)
    ahead.automatic = true
    ahead.ahead = true
    try store.put(ahead)
    try store.put(entry("b", .queued))
    let reopened = try DownloadStore(root: root)
    XCTAssertEqual(reopened.entry(for: "a")?.ahead, true)
    XCTAssertEqual(reopened.entry(for: "b")?.ahead, false)
    XCTAssertTrue(try finish(reopened, "a").ahead)
    XCTAssertEqual(try DownloadStore(root: root).entry(for: "a")?.ahead, true)

    // An index from before the flag existed.
    let old = """
      {"version":1,"entries":[{"episodeId":"c","url":"https://x.example/c.mp3",\
      "fileExtension":"mp3","state":{"kind":"queued"},"updatedAt":"2026-11-17T10:00:00Z",\
      "automatic":true}]}
      """
    try Data(old.utf8).write(to: root.appendingPathComponent("index.json"))
    XCTAssertEqual(try DownloadStore(root: root).entry(for: "c")?.ahead, false)
  }

  func testClearingTheAheadFlagChangesNothingElse() throws {
    let store = try DownloadStore(root: root)
    var ahead = entry("a", .queued)
    ahead.automatic = true
    ahead.ahead = true
    try store.put(ahead)
    try store.put(entry("b", .queued))
    let done = try finish(store, "a")

    let cleared = try store.clearAhead(episodeId: "a")
    XCTAssertEqual(cleared?.ahead, false)
    var expected = done
    expected.ahead = false
    XCTAssertEqual(cleared, expected)
    XCTAssertEqual(try DownloadStore(root: root).entry(for: "a"), expected)
    // One that is not ahead, or not there, is left alone.
    XCTAssertNil(try store.clearAhead(episodeId: "b"))
    XCTAssertNil(try store.clearAhead(episodeId: "nope"))
    XCTAssertEqual(store.entry(for: "b")?.ahead, false)
  }

  // MARK: A copy taken only for the list

  func testTheForListFlagSurvivesARestartAndAnOldIndexMeansFalse() throws {
    let store = try DownloadStore(root: root)
    var listed = entry("a", .queued)
    listed.copyForList = true
    try store.put(listed)
    try store.put(entry("b", .queued))

    let reopened = try DownloadStore(root: root)
    XCTAssertEqual(reopened.entry(for: "a")?.copyForList, true)
    XCTAssertEqual(reopened.entry(for: "b")?.copyForList, false)

    // An index from before the flag existed still reads, and the flag means false.
    let old = """
      {"version":1,"entries":[{"episodeId":"c","url":"https://x.example/c.mp3",\
      "fileExtension":"mp3","state":{"kind":"queued"},"updatedAt":"2026-11-17T10:00:00Z",\
      "automatic":true,"ahead":true}]}
      """
    try Data(old.utf8).write(to: root.appendingPathComponent("index.json"))
    let read = try DownloadStore(root: root).entry(for: "c")
    XCTAssertEqual(read?.copyForList, false)
    XCTAssertEqual(read?.ahead, true)
    XCTAssertEqual(read?.automatic, true)
  }

  func testInstallingOverAnEntryKeepsItsForListFlag() throws {
    let store = try DownloadStore(root: root)
    var listed = entry("a", .queued)
    listed.copyForList = true
    try store.put(listed)
    XCTAssertTrue(try finish(store, "a").copyForList)
    try store.put(entry("b", .queued))
    XCTAssertFalse(try finish(store, "b").copyForList)
  }

  func testClearingTheAheadMarkAlsoMakesAListCopyTheListenersOwn() throws {
    let store = try DownloadStore(root: root)
    var listed = entry("a", .queued)
    listed.copyForList = true
    try store.put(listed)
    try finish(store, "a")
    let cleared = try store.clearAhead(episodeId: "a")
    XCTAssertEqual(cleared?.copyForList, false)
    XCTAssertEqual(try DownloadStore(root: root).entry(for: "a")?.copyForList, false)
    // Nothing to clear the second time.
    XCTAssertNil(try store.clearAhead(episodeId: "a"))
  }

  func testAnIndexThatCannotBeReadIsSetAsideAndTheStoreStartsEmpty() throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: root.appendingPathComponent("index.json"))
    let store = try DownloadStore(root: root)
    XCTAssertEqual(store.entries(), [])
    XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("index.corrupt.json").path))
    try store.put(entry("a", .queued))
    XCTAssertEqual(try DownloadStore(root: root).entries().count, 1)
  }

  func testProgressIsKeptInMemoryAndOnlyForMovingDownloads() throws {
    let store = try DownloadStore(root: root)
    try store.put(entry("a", .queued))
    XCTAssertEqual(
      store.updateProgress(episodeId: "a", bytes: 50, expected: 100)?.state,
      .downloading(bytes: 50, expected: 100))
    XCTAssertNil(store.updateProgress(episodeId: "missing", bytes: 1, expected: 2))
    try store.put(entry("b", .failed(reason: "x")))
    XCTAssertNil(store.updateProgress(episodeId: "b", bytes: 1, expected: 2))
    XCTAssertEqual(store.entry(for: "b")?.state, .failed(reason: "x"))
  }

  // MARK: The relaunch

  func testRelaunchFailsLostDownloadsAndReturnsQueuedOnesToRestart() throws {
    let store = try DownloadStore(root: root)
    try store.put(entry("lost", .downloading(bytes: 1, expected: 9)))
    try store.put(entry("alive", .downloading(bytes: 1, expected: 9)))
    try store.put(entry("waiting", .queued))
    try finish(store, "done")

    let restart = try store.reconcile(liveEpisodeIds: ["alive"])
    XCTAssertEqual(restart.map(\.episodeId), ["waiting"])
    XCTAssertEqual(store.entry(for: "lost")?.state, .failed(reason: "Stopped, tap to try again"))
    XCTAssertEqual(store.entry(for: "alive")?.state, .downloading(bytes: 1, expected: 9))
    XCTAssertEqual(store.entry(for: "waiting")?.state, .queued)
    if case .downloaded = store.entry(for: "done")?.state {} else { XCTFail("kept") }
    // The change is on disk.
    XCTAssertEqual(
      try DownloadStore(root: root).entry(for: "lost")?.state, .failed(reason: "Stopped, tap to try again"))
  }

  func testRelaunchDropsAnUnfinishedPlayThroughDownloadWithItsFolder() throws {
    let store = try DownloadStore(root: root)
    var heard = entry("heard", .downloading(bytes: 1, expected: 9))
    heard.playThrough = true
    try store.put(heard)
    var feeding = entry("feeding", .downloading(bytes: 1, expected: 9))
    feeding.playThrough = true
    try store.put(feeding)
    let folder = try store.folder(for: "heard")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let restart = try store.reconcile(liveEpisodeIds: ["feeding"])
    XCTAssertEqual(restart, [])
    XCTAssertNil(store.entry(for: "heard"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    XCTAssertEqual(store.entry(for: "feeding")?.state, .downloading(bytes: 1, expected: 9))
    XCTAssertNil(try DownloadStore(root: root).entry(for: "heard"))
  }

  func testTheMarkSurvivesTheIndexAndAnOldIndexMeansNone() throws {
    let store = try DownloadStore(root: root)
    var marked = entry("a", .queued)
    marked.playThrough = true
    try store.put(marked)
    XCTAssertEqual(try DownloadStore(root: root).entry(for: "a")?.playThrough, true)
    let old = """
      {"episodeId":"b","url":"https://x/b.mp3","fileExtension":"mp3","state":{"kind":"queued"},\
      "updatedAt":"2030-01-01T00:00:00Z"}
      """
    let decoded = try JSONDecoder.iso.decode(DownloadEntry.self, from: Data(old.utf8))
    XCTAssertFalse(decoded.playThrough)
  }

  // MARK: Files

  func testAFileLivesAtEpisodeFolderHashDotExtension() throws {
    let store = try DownloadStore(root: root)
    let id = UUID().uuidString
    try finish(store, id)
    let expected = root.appendingPathComponent(id).appendingPathComponent("\(sha).mp3")
    XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path))
    XCTAssertEqual(store.localFile(for: id)?.path, expected.path)
    // Nothing is left waiting in .incoming.
    let waiting = try? FileManager.default.contentsOfDirectory(
      atPath: root.appendingPathComponent(".incoming").path)
    XCTAssertEqual(waiting ?? [], [])
  }

  func testBadEpisodeIdsAreRefusedEverywhere() throws {
    let store = try DownloadStore(root: root)
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data([1]).write(to: temp)
    defer { try? FileManager.default.removeItem(at: temp) }
    for bad in ["", "/", "..", "../escape", "a/b"] {
      XCTAssertThrowsError(try store.folder(for: bad))
      XCTAssertThrowsError(try store.put(entry(bad, .queued)))
      XCTAssertThrowsError(try store.stage(temp, episodeId: bad))
      XCTAssertThrowsError(try store.delete(episodeId: bad))
      XCTAssertNil(store.localFile(for: bad))
    }
    XCTAssertEqual(store.entries(), [])
    XCTAssertTrue(FileManager.default.fileExists(atPath: temp.path))
  }

  func testInstallRefusesAHashOrExtensionThatIsNotSafe() throws {
    let store = try DownloadStore(root: root)
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data([1]).write(to: temp)
    defer { try? FileManager.default.removeItem(at: temp) }
    XCTAssertThrowsError(
      try store.install(episodeId: "a", staged: temp, sha256: "../x", fileExtension: "mp3", bytes: 1))
    XCTAssertThrowsError(
      try store.install(episodeId: "a", staged: temp, sha256: sha, fileExtension: "../x", bytes: 1))
  }

  func testANewDownloadReplacesTheOldFileAndItsSideFiles() throws {
    let store = try DownloadStore(root: root)
    try finish(store, "a")
    let folder = try store.folder(for: "a")
    try Data("{}".utf8).write(to: folder.appendingPathComponent("\(sha).transcript.json"))
    try finish(store, "a", bytes: 8)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: folder.path), ["\(sha).mp3"])
    XCTAssertEqual(store.storageUsed(), 8)
  }

  func testAFinishedDownloadThatWasDeletedMeanwhileIsNotBroughtBack() throws {
    let store = try DownloadStore(root: root)
    try store.put(entry("a", .downloading(bytes: 1, expected: 2)))
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data([1, 2]).write(to: temp)
    let staged = try store.stage(temp, episodeId: "a")
    // The listener removes it after the file finished but before it is filed.
    try store.delete(episodeId: "a")
    XCTAssertThrowsError(
      try store.install(
        episodeId: "a", staged: staged, sha256: sha, fileExtension: "mp3", bytes: 2,
        requireEntry: true)
    ) { XCTAssertEqual($0 as? DownloadError, .noEntry("a")) }
    XCTAssertNil(store.entry(for: "a"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: try store.folder(for: "a").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
  }

  func testInstallWithAnEntryStillWorksWhenOneIsRequired() throws {
    let store = try DownloadStore(root: root)
    try store.put(entry("a", .downloading(bytes: 1, expected: 2)))
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data([1, 2]).write(to: temp)
    let staged = try store.stage(temp, episodeId: "a")
    let done = try store.install(
      episodeId: "a", staged: staged, sha256: sha, fileExtension: "mp3", bytes: 2, requireEntry: true)
    XCTAssertEqual(done.url, "https://cdn.example.com/a.mp3")
    XCTAssertNotNil(store.localFile(for: "a"))
  }

  // MARK: Deleting

  func testDeleteRemovesTheWholeFolderAndTheEntry() throws {
    let store = try DownloadStore(root: root)
    try finish(store, "a")
    try finish(store, "b")
    let folder = try store.folder(for: "a")
    try Data("{}".utf8).write(to: folder.appendingPathComponent("\(sha).transcript.json"))
    try Data("{}".utf8).write(to: folder.appendingPathComponent("\(sha).ads.test.json"))

    XCTAssertTrue(try store.delete(episodeId: "a"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    XCTAssertNil(store.entry(for: "a"))
    XCTAssertNil(store.localFile(for: "a"))
    XCTAssertEqual(try DownloadStore(root: root).entries().map(\.episodeId), ["b"])
    XCTAssertNotNil(store.localFile(for: "b"))
    XCTAssertFalse(try store.delete(episodeId: "a"))
  }

  func testDeleteAlsoClearsAnEntryThatNeverFinished() throws {
    let store = try DownloadStore(root: root)
    try store.put(entry("a", .downloading(bytes: 1, expected: 2)))
    XCTAssertTrue(try store.delete(episodeId: "a"))
    XCTAssertEqual(store.entries(), [])
  }

  func testAFileThatWentMissingIsNotOffered() throws {
    let store = try DownloadStore(root: root)
    try finish(store, "a")
    try FileManager.default.removeItem(at: try XCTUnwrap(store.localFile(for: "a")))
    XCTAssertNil(store.localFile(for: "a"))
  }

  // MARK: Storage

  func testStorageUsedIsTheSumOfDownloadedBytes() throws {
    let store = try DownloadStore(root: root)
    XCTAssertEqual(store.storageUsed(), 0)
    try finish(store, "a", bytes: 5)
    try finish(store, "b", bytes: 7)
    try store.put(entry("c", .downloading(bytes: 99, expected: 100)))
    try store.put(entry("d", .failed(reason: "x")))
    XCTAssertEqual(store.storageUsed(), 12)
    try store.delete(episodeId: "a")
    XCTAssertEqual(store.storageUsed(), 7)
  }
}

extension JSONDecoder {
  fileprivate static var iso: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
