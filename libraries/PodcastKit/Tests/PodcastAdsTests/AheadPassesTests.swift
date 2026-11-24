import XCTest

@testable import PodcastAds

/// The record of which marks the finder has used for each episode, so a pass is not repeated at
/// every start and runs again when newer marks come.
final class AheadPassesTests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ahead-passes-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  func testAnEpisodeWithNoRecordNeedsAPass() {
    XCTAssertTrue(AheadPasses().needs(episode: "e1", marked: 1_700_000_000))
  }

  func testAnEpisodeIsDoneForTheMarksItWasLookedAtWith() {
    var passes = AheadPasses()
    passes.record(episode: "e1", marked: 1_700_000_000)
    XCTAssertFalse(passes.needs(episode: "e1", marked: 1_700_000_000))
    XCTAssertFalse(passes.needs(episode: "e1", marked: 1_699_999_999), "older marks are no news")
  }

  func testNewerMarksNeedANewPass() {
    var passes = AheadPasses()
    passes.record(episode: "e1", marked: 1_700_000_000)
    XCTAssertTrue(passes.needs(episode: "e1", marked: 1_700_000_001))
    passes.record(episode: "e1", marked: 1_700_086_400)
    XCTAssertFalse(passes.needs(episode: "e1", marked: 1_700_086_400))
  }

  func testAnotherEpisodeIsNotDoneBecauseOneIs() {
    var passes = AheadPasses()
    passes.record(episode: "e1", marked: 1_700_000_000)
    XCTAssertTrue(passes.needs(episode: "e2", marked: 1_700_000_000))
  }

  func testARecordNeverGoesBackToOlderMarks() {
    var passes = AheadPasses()
    passes.record(episode: "e1", marked: 1_700_086_400)
    passes.record(episode: "e1", marked: 1_700_000_000)
    XCTAssertFalse(passes.needs(episode: "e1", marked: 1_700_086_400))
  }

  func testAMarkThatIsNotANumberIsNeverRecordedOrNeeded() {
    var passes = AheadPasses()
    passes.record(episode: "e1", marked: .nan)
    XCTAssertTrue(passes.stamps.isEmpty)
    XCTAssertFalse(passes.needs(episode: "e1", marked: .nan))
  }

  func testTheRecordIsKeptInTheFolderAndReadAgain() throws {
    var passes = AheadPasses()
    passes.record(episode: "e1", marked: 1_700_000_000)
    passes.record(episode: "e2", marked: 1_700_086_400)
    try passes.save(to: folder)
    let again = AheadPasses.load(from: folder)
    XCTAssertEqual(again, passes)
    XCTAssertFalse(again.needs(episode: "e2", marked: 1_700_086_400))
  }

  func testNoFileOrADamagedOneIsAnEmptyRecord() throws {
    XCTAssertEqual(AheadPasses.load(from: folder), AheadPasses())
    try Data("{not json".utf8).write(to: folder.appendingPathComponent(AheadPasses.fileName))
    XCTAssertEqual(AheadPasses.load(from: folder), AheadPasses())
    try Data(#"{"stamps": [1, 2]}"#.utf8).write(
      to: folder.appendingPathComponent(AheadPasses.fileName))
    XCTAssertEqual(AheadPasses.load(from: folder), AheadPasses())
  }

  func testOnlyTheNewestRecordsAreKept() {
    var passes = AheadPasses()
    for number in 0..<(AheadPasses.most + 25) {
      passes.record(episode: "e\(number)", marked: 1_700_000_000 + Double(number))
    }
    XCTAssertEqual(passes.stamps.count, AheadPasses.most)
    XCTAssertNil(passes.stamps["e0"], "the oldest are dropped")
    XCTAssertNotNil(passes.stamps["e\(AheadPasses.most + 24)"])
  }
}
