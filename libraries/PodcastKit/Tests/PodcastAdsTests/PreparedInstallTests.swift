import XCTest

@testable import PodcastAds

/// What the phone checks before it swaps in a copy the Mac prepared.
final class PreparedInstallTests: XCTestCase {
  private let goodSha = String(repeating: "ab", count: 32)
  private let other = String(repeating: "cd", count: 32)

  private func aCopy(_ file: String = "prepared/0123456789ab.mp3", bytes: Int64 = 1000)
    -> PreparedCopy
  {
    PreparedCopy(file: file, sha256: goodSha, bytes: bytes)
  }

  // MARK: Before the file is read

  func testNoListedCopyIsRefused() {
    XCTAssertEqual(PreparedInstall.early(listed: nil, inPlayer: false, moving: false), .noCopy)
  }

  func testAnEpisodeInThePlayerIsRefused() {
    XCTAssertEqual(
      PreparedInstall.early(listed: aCopy(), inPlayer: true, moving: false), .playing)
  }

  func testAnEpisodeBeingDownloadedIsRefused() {
    XCTAssertEqual(
      PreparedInstall.early(listed: aCopy(), inPlayer: false, moving: true), .downloading)
  }

  func testTheEpisodeInThePlayerComesBeforeTheDownload() {
    XCTAssertEqual(PreparedInstall.early(listed: aCopy(), inPlayer: true, moving: true), .playing)
  }

  func testAFreeEpisodeWithACopyPassesTheEarlyChecks() {
    XCTAssertNil(PreparedInstall.early(listed: aCopy(), inPlayer: false, moving: false))
  }

  // MARK: After the file is read

  func testTheRightSizeAndHashPass() {
    XCTAssertNil(PreparedInstall.late(listed: aCopy(), bytes: 1000, sha256: goodSha))
  }

  func testTheHashMayBeInUpperCase() {
    XCTAssertNil(PreparedInstall.late(listed: aCopy(), bytes: 1000, sha256: goodSha.uppercased()))
  }

  func testAWrongSizeIsRefusedWhateverTheHash() {
    XCTAssertEqual(PreparedInstall.late(listed: aCopy(), bytes: 999, sha256: goodSha), .size)
    XCTAssertEqual(PreparedInstall.late(listed: aCopy(), bytes: 999, sha256: other), .size)
  }

  func testAWrongHashIsRefused() {
    XCTAssertEqual(PreparedInstall.late(listed: aCopy(), bytes: 1000, sha256: other), .hash)
  }

  // MARK: The file's extension

  func testTheExtensionIsTheCopysOwnInLowerCase() {
    XCTAssertEqual(PreparedInstall.fileExtension(of: aCopy("prepared/x.mp3")), "mp3")
    XCTAssertEqual(PreparedInstall.fileExtension(of: aCopy("prepared/x.M4A")), "m4a")
  }

  func testACopyWithNoUsableExtensionHasNone() {
    XCTAssertNil(PreparedInstall.fileExtension(of: aCopy("prepared/noextension")))
    XCTAssertNil(PreparedInstall.fileExtension(of: aCopy("prepared/x.toolong")))
    XCTAssertNil(PreparedInstall.fileExtension(of: aCopy("prepared/x.m-4")))
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

  // MARK: A miss

  func testAMissedNoteOnAPreparedFileCarriesByPrepared() throws {
    var file = AdsFile(
      sha256: goodSha, detector: "d", detectorVersion: "v", osVersion: "", duration: 100, ads: [])
    file.prepared = true
    XCTAssertEqual(PreparedAds.noteName(forFile: file), "prepared")
    let note = PhoneNote(
      at: 1, what: .missed, episode: "e", show: "s", start: 10, end: 40, kind: nil,
      by: PreparedAds.noteName(forFile: file))
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(note.line.utf8)) as? [String: Any])
    XCTAssertEqual(object["by"] as? String, "prepared")
  }

  func testAMissedNoteOnAnyOtherFileNamesNoFinder() {
    var plain = AdsFile(
      sha256: goodSha, detector: "d", detectorVersion: "v", osVersion: "", duration: 100, ads: [])
    XCTAssertNil(PreparedAds.noteName(forFile: plain))
    plain.prepared = false
    XCTAssertNil(PreparedAds.noteName(forFile: plain))
    XCTAssertNil(PreparedAds.noteName(forFile: nil))
  }
}
