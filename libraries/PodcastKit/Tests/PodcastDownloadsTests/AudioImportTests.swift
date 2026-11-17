import XCTest

@testable import PodcastDownloads

final class AudioImportTests: XCTestCase {
  private let sha = "0123456789abcdef" + String(repeating: "f", count: 48)

  func testAcceptsTheAudioTypesAvPlayerPlaysAndIgnoresCase() {
    for name in ["a.mp3", "A.MP3", "talk.m4a", "book.m4b", "x.wav", "x.aiff", "x.aif", "x.caf",
      "x.flac", "x.aac", "clip.mp4"]
    {
      XCTAssertTrue(AudioImport.isAccepted(fileName: name), name)
    }
    for name in ["notes.txt", "photo.jpg", "movie", "x.opus", ".mp3", "a.mp3.exe", ""] {
      XCTAssertFalse(AudioImport.isAccepted(fileName: name), name)
    }
  }

  func testTheExtensionIsLowercaseAndSafe() {
    XCTAssertEqual(AudioImport.fileExtension(fileName: "Show Notes.M4A"), "m4a")
    XCTAssertNil(AudioImport.fileExtension(fileName: "readme.txt"))
  }

  func testTheIdIsStableSafeAndFromTheHash() throws {
    let id = try XCTUnwrap(AudioImport.episodeId(sha256: sha))
    XCTAssertEqual(id, "file-0123456789abcdef" + String(repeating: "f", count: 16))
    XCTAssertEqual(AudioImport.episodeId(sha256: sha), id)
    XCTAssertTrue(DownloadFile.isSafeEpisodeId(id))
    XCTAssertTrue(AudioImport.isImportedId(id))
    XCTAssertFalse(AudioImport.isImportedId(UUID().uuidString))
    XCTAssertNil(AudioImport.episodeId(sha256: "../nope"))
  }

  func testTheTitleIsTheTagElseTheFileNameWithoutItsExtension() {
    XCTAssertEqual(AudioImport.title(fileName: "x.mp3", tagTitle: "  Chapter One \n"), "Chapter One")
    XCTAssertEqual(AudioImport.title(fileName: "My Talk.final.mp3", tagTitle: nil), "My Talk.final")
    XCTAssertEqual(AudioImport.title(fileName: "My Talk.mp3", tagTitle: "   "), "My Talk")
    XCTAssertEqual(AudioImport.title(fileName: ".mp3", tagTitle: nil), "Untitled file")
  }

  func testAFileThatIsAlreadyInstalledIsRecognised() {
    let done = DownloadEntry(
      episodeId: "file-a", url: "", fileExtension: "mp3",
      state: .downloaded(file: sha + ".mp3", sha256: sha, bytes: 5, date: Date()))
    XCTAssertTrue(AudioImport.isInstalled(done, sha256: sha))
    XCTAssertFalse(AudioImport.isInstalled(done, sha256: String(repeating: "a", count: 64)))
    XCTAssertFalse(AudioImport.isInstalled(nil, sha256: sha))
    var failed = done
    failed.state = .failed(reason: "x")
    XCTAssertFalse(AudioImport.isInstalled(failed, sha256: sha))
  }

  func testInstallingTwiceKeepsOneEntryWithTheSameFileName() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try DownloadStore(root: root)
    let source = root.appendingPathComponent("source.mp3")
    try Data("hello".utf8).write(to: source)
    let hash = try FileHash.sha256(of: source)
    let id = try XCTUnwrap(AudioImport.episodeId(sha256: hash))
    let staged = try store.stage(source, episodeId: id)
    let entry = try store.install(
      episodeId: id, staged: staged, sha256: hash, fileExtension: "mp3", bytes: 5)
    XCTAssertTrue(AudioImport.isInstalled(store.entry(for: id), sha256: hash))
    XCTAssertEqual(store.localFile(for: id)?.lastPathComponent, "\(hash).mp3")
    XCTAssertEqual(entry.episodeId, id)
  }
}
