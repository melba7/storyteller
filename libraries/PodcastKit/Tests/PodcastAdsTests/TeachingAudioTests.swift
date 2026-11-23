import XCTest

@testable import PodcastAds

/// Which MP3 file of the teaching folder belongs to which episode.
final class TeachingAudioTests: XCTestCase {
  private var folder: FolderWriter!

  override func setUpWithError() throws { folder = try FolderWriter() }
  override func tearDown() { folder.remove() }

  private func list(_ files: [String?]) throws {
    let entries = files.enumerated().map { number, file in
      "{\"id\": \"e\(number)\"" + (file.map { ", \"file\": \"\($0)\"" } ?? "") + "}"
    }
    try folder.write("episodes.json", "{\"version\": 1, \"episodes\": [\(entries.joined(separator: ","))]}")
  }

  func testOnlyAnExistingMP3InsideTheFolderIsAudio() throws {
    try folder.write("audio/a.mp3", "x")
    try folder.write("audio/b.MP3", "x")
    try folder.write("audio/c.m4a", "x")
    try folder.write("outside.mp3", "x")
    try FileManager.default.createDirectory(
      at: folder.url.appendingPathComponent("audio/folder.mp3"), withIntermediateDirectories: true)
    try list([
      "audio/a.mp3", "audio/b.MP3", "audio/c.m4a", "audio/missing.mp3", "audio/folder.mp3",
      "/etc/passwd.mp3", "../outside.mp3", "audio/../outside.mp3", "", nil,
    ])
    let found = TeachingAudio.files(in: folder.url)
    XCTAssertEqual(found.keys.sorted(), ["e0", "e1"])
    XCTAssertEqual(found["e0"]?.lastPathComponent, "a.mp3")
  }

  func testAFolderWithNoEpisodesFileOrAnUnreadableOneHasNoAudio() throws {
    XCTAssertEqual(TeachingAudio.files(in: folder.url), [:])
    try folder.write("episodes.json", "{ nonsense")
    XCTAssertEqual(TeachingAudio.files(in: folder.url), [:])
    try folder.write("episodes.json", "{\"episodes\": [1, \"two\", {\"id\": 3, \"file\": \"a.mp3\"}]}")
    XCTAssertEqual(TeachingAudio.files(in: folder.url), [:])
  }

  func testALinkOutOfTheFolderOrAFileThatIsNotARegularOneIsNotAudio() throws {
    let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent("elsewhere-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: elsewhere) }
    try Data("x".utf8).write(to: elsewhere.appendingPathComponent("x.mp3"))
    try folder.write("audio/real.mp3", "x")
    let audio = folder.url.appendingPathComponent("audio")
    let fileManager = FileManager.default
    // A link to a file elsewhere, a link to a folder elsewhere, a link to a file in the folder,
    // and a named pipe (reading it would wait for ever).
    try fileManager.createSymbolicLink(
      at: audio.appendingPathComponent("out.mp3"), withDestinationURL: elsewhere.appendingPathComponent("x.mp3"))
    try fileManager.createSymbolicLink(
      at: folder.url.appendingPathComponent("linked"), withDestinationURL: elsewhere)
    try fileManager.createSymbolicLink(
      at: audio.appendingPathComponent("same.mp3"), withDestinationURL: audio.appendingPathComponent("real.mp3"))
    XCTAssertEqual(mkfifo(audio.appendingPathComponent("pipe.mp3").path, 0o600), 0)
    try list(["audio/real.mp3", "audio/out.mp3", "linked/x.mp3", "audio/same.mp3", "audio/pipe.mp3"])
    let found = TeachingAudio.files(in: folder.url)
    XCTAssertEqual(found.keys.sorted(), ["e0", "e3"])
  }
}
