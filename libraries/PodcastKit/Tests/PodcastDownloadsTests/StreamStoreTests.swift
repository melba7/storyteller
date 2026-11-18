import XCTest

@testable import PodcastDownloads

/// The store's help for a download that is played while it arrives: a staging file to write
/// into, and filing the finished file the way a finished download is filed.
final class StreamStoreTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "stream-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: root)
  }

  private func entry(_ id: String) -> DownloadEntry {
    DownloadEntry(
      episodeId: id, url: "https://cdn.example.com/\(id).mp3", fileExtension: "mp3",
      state: .downloading(bytes: 0, expected: nil))
  }

  func testAStagingFileIsNewEmptyAndOutsideTheEpisodesFolder() throws {
    let store = try DownloadStore(root: root)
    let first = try store.newStagingFile(episodeId: "a")
    let second = try store.newStagingFile(episodeId: "a")
    XCTAssertNotEqual(first, second)
    XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
    XCTAssertEqual(try Data(contentsOf: first).count, 0)
    XCTAssertFalse(first.path.hasPrefix(try store.folder(for: "a").path))
  }

  func testAStagingFileIsRefusedForAnUnsafeId() throws {
    let store = try DownloadStore(root: root)
    XCTAssertThrowsError(try store.newStagingFile(episodeId: "../x"))
    XCTAssertThrowsError(try store.newStagingFile(episodeId: "preview:s:1"))
  }

  func testAStagedFileIsHashedAndFiledLikeAFinishedDownload() throws {
    let store = try DownloadStore(root: root)
    try store.put(entry("a"))
    let staged = try store.newStagingFile(episodeId: "a")
    try Data("abc".utf8).write(to: staged)
    let done = try store.installStaged(staged, episodeId: "a", fileExtension: "mp3")
    // SHA-256 of "abc".
    let sha = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    guard case .downloaded(let file, let hash, let bytes, _) = done.state else {
      return XCTFail("not downloaded: \(done.state)")
    }
    XCTAssertEqual(file, "\(sha).mp3")
    XCTAssertEqual(hash, sha)
    XCTAssertEqual(bytes, 3)
    XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(store.localFile(for: "a"))), Data("abc".utf8))
    XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
  }

  func testAFileOpenedBeforeItWasFiledCanStillBeRead() throws {
    let store = try DownloadStore(root: root)
    try store.put(entry("a"))
    let staged = try store.newStagingFile(episodeId: "a")
    try Data("abcdef".utf8).write(to: staged)
    let reader = try FileHandle(forReadingFrom: staged)
    defer { try? reader.close() }
    try store.installStaged(staged, episodeId: "a", fileExtension: "mp3")
    try reader.seek(toOffset: 2)
    XCTAssertEqual(try reader.read(upToCount: 3), Data("cde".utf8))
  }

  func testAnEpisodeRemovedMeanwhileIsNotBroughtBack() throws {
    let store = try DownloadStore(root: root)
    let staged = try store.newStagingFile(episodeId: "a")
    try Data("abc".utf8).write(to: staged)
    XCTAssertThrowsError(try store.installStaged(staged, episodeId: "a", fileExtension: "mp3")) {
      XCTAssertEqual($0 as? DownloadError, DownloadError.noEntry("a"))
    }
    XCTAssertNil(store.entry(for: "a"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
  }

  func testAMissingStagedFileIsAnErrorNotACrash() throws {
    let store = try DownloadStore(root: root)
    try store.put(entry("a"))
    let gone = root.appendingPathComponent("nothing")
    XCTAssertThrowsError(try store.installStaged(gone, episodeId: "a", fileExtension: "mp3"))
  }
}

final class StreamFailureReasonTests: XCTestCase {
  func testAReasonIsPlainWords() {
    XCTAssertEqual(
      DownloadRecovery.reason(for: DownloadFailure(httpStatus: 404)),
      "The episode is no longer there (404)")
    XCTAssertEqual(
      DownloadRecovery.reason(for: DownloadFailure(diskFull: true)), "The phone is full")
  }

  func testAConnectionThatDroppedHasNoSecondTryHere() {
    XCTAssertEqual(
      DownloadRecovery.reason(for: DownloadFailure(urlErrorCode: -1005)),
      "No connection, tap to try again")
  }
}

final class KnownTypeTests: XCTestCase {
  func testKnownTypesGiveTheirExtensionAndOthersNone() {
    XCTAssertEqual(DownloadFile.knownExtension(forType: "audio/mpeg"), "mp3")
    XCTAssertEqual(DownloadFile.knownExtension(forType: "Audio/X-M4A; x=y"), "m4a")
    XCTAssertNil(DownloadFile.knownExtension(forType: "application/octet-stream"))
    XCTAssertNil(DownloadFile.knownExtension(forType: nil))
  }
}
