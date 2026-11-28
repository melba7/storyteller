import XCTest

@testable import PodcastAds

/// `AdsFile.prepared`: an optional key, so old files still read and files without it are as before.
final class PreparedFileTests: XCTestCase {
  private func file(prepared: Bool? = nil) -> AdsFile {
    AdsFile(
      sha256: "aa", detector: "fake", detectorVersion: "1", osVersion: "26", duration: 600, ads: [],
      prepared: prepared)
  }

  func testAFileSavedBeforeTheKeyExistedStillReadsAsNotPrepared() throws {
    let old =
      #"{"version":1,"sha256":"aa","detector":"fake","detectorVersion":"1","osVersion":"26","duration":600,"ads":[],"undone":[]}"#
    let read = try JSONDecoder().decode(AdsFile.self, from: Data(old.utf8))
    XCTAssertNil(read.prepared)
    XCTAssertEqual(read, file())
  }

  func testAFileWithoutTheKeyEncodesWithoutIt() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let text = String(decoding: try encoder.encode(file()), as: UTF8.self)
    XCTAssertFalse(text.contains("prepared"))
  }

  func testAPreparedFileKeepsTheKeyThroughTheStore() throws {
    let store = AdsStore(folder: try temporaryFolder(), sha256: "aa")
    try store.save(file(prepared: true))
    XCTAssertEqual(store.load(detector: "fake")?.prepared, true)
    XCTAssertTrue(try XCTUnwrap(store.json(detector: "fake")).contains(#""prepared":true"#))
  }
}
