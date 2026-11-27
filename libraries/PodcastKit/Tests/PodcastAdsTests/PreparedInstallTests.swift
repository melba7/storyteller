import XCTest

@testable import PodcastAds

/// What the phone checks before it swaps in a copy the Mac prepared.
final class PreparedInstallTests: XCTestCase {
  private let hash = String(repeating: "ab", count: 32)
  private let other = String(repeating: "cd", count: 32)

  private func copy(_ file: String = "prepared/0123456789ab.mp3", bytes: Int64 = 1000)
    -> PreparedCopy
  {
    PreparedCopy(file: file, sha256: hash, bytes: bytes)
  }

  // MARK: Before the file is read

  func testNoListedCopyIsRefused() {
    XCTAssertEqual(PreparedInstall.early(listed: nil, inPlayer: false, moving: false), .noCopy)
  }

  func testAnEpisodeInThePlayerIsRefused() {
    XCTAssertEqual(
      PreparedInstall.early(listed: copy(), inPlayer: true, moving: false), .playing)
  }

  func testAnEpisodeBeingDownloadedIsRefused() {
    XCTAssertEqual(
      PreparedInstall.early(listed: copy(), inPlayer: false, moving: true), .downloading)
  }

  func testTheEpisodeInThePlayerComesBeforeTheDownload() {
    XCTAssertEqual(PreparedInstall.early(listed: copy(), inPlayer: true, moving: true), .playing)
  }

  func testAFreeEpisodeWithACopyPassesTheEarlyChecks() {
    XCTAssertNil(PreparedInstall.early(listed: copy(), inPlayer: false, moving: false))
  }

  // MARK: After the file is read

  func testTheRightSizeAndHashPass() {
    XCTAssertNil(PreparedInstall.late(listed: copy(), bytes: 1000, sha256: hash))
  }

  func testTheHashMayBeInUpperCase() {
    XCTAssertNil(PreparedInstall.late(listed: copy(), bytes: 1000, sha256: hash.uppercased()))
  }

  func testAWrongSizeIsRefusedWhateverTheHash() {
    XCTAssertEqual(PreparedInstall.late(listed: copy(), bytes: 999, sha256: hash), .size)
    XCTAssertEqual(PreparedInstall.late(listed: copy(), bytes: 999, sha256: other), .size)
  }

  func testAWrongHashIsRefused() {
    XCTAssertEqual(PreparedInstall.late(listed: copy(), bytes: 1000, sha256: other), .hash)
  }

  // MARK: The file's extension

  func testTheExtensionIsTheCopysOwnInLowerCase() {
    XCTAssertEqual(PreparedInstall.fileExtension(of: copy("prepared/x.mp3")), "mp3")
    XCTAssertEqual(PreparedInstall.fileExtension(of: copy("prepared/x.M4A")), "m4a")
  }

  func testACopyWithNoUsableExtensionHasNone() {
    XCTAssertNil(PreparedInstall.fileExtension(of: copy("prepared/noextension")))
    XCTAssertNil(PreparedInstall.fileExtension(of: copy("prepared/x.toolong")))
    XCTAssertNil(PreparedInstall.fileExtension(of: copy("prepared/x.m-4")))
  }

  // MARK: The for-list flag

  func testAnEntryThatExistedKeepsItsFlagAndANewOneGetsTheAsked() {
    XCTAssertFalse(PreparedInstall.forList(existing: false, forListOnly: true))
    XCTAssertTrue(PreparedInstall.forList(existing: true, forListOnly: false))
    XCTAssertTrue(PreparedInstall.forList(existing: nil, forListOnly: true))
    XCTAssertFalse(PreparedInstall.forList(existing: nil, forListOnly: false))
  }

  // MARK: The notes

  func testASkipOfAPreparedAdIsNotedWithItsName() {
    XCTAssertEqual(PreparedAds.noteName(forSource: PreparedAds.source), "prepared")
    XCTAssertNil(PreparedAds.noteName(forSource: "own-sound"))
    XCTAssertNil(PreparedAds.noteName(forSource: ""))
    XCTAssertNil(PreparedAds.noteName(forSource: nil))
  }

  func testTheNoteOfAPreparedSkipAndOfItsUndoCarriesByPrepared() throws {
    for what in [PhoneNote.What.skipped, .undone] {
      let note = PhoneNote(
        at: 1, what: what, episode: "e", show: "s", start: 100, end: 160, kind: .ad,
        by: PreparedAds.noteName(forSource: PreparedAds.source))
      let object = try XCTUnwrap(
        JSONSerialization.jsonObject(with: Data(note.line.utf8)) as? [String: Any])
      XCTAssertEqual(object["by"] as? String, "prepared")
    }
  }
}
