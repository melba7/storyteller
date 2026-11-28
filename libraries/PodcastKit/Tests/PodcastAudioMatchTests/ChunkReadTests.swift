import XCTest

@testable import PodcastAudioMatch

/// The chunked reads of a file, and the line the score prints while it reads many files.
final class ChunkReadTests: XCTestCase {
  func testEveryChunkOfAFileIsReadInOrderThenNothing() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("chunks-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data((0..<10).map { UInt8($0) }).write(to: url)
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var read: [[UInt8]] = []
    while let chunk = ChunkRead.next(handle, upTo: 4) { read.append([UInt8](chunk)) }
    XCTAssertEqual(read, [[0, 1, 2, 3], [4, 5, 6, 7], [8, 9]])
    XCTAssertNil(ChunkRead.next(handle, upTo: 4))
  }

  func testAFolderGivesNoChunk() throws {
    let handle = try FileHandle(forReadingFrom: FileManager.default.temporaryDirectory)
    defer { try? handle.close() }
    XCTAssertNil(ChunkRead.next(handle, upTo: 4))
  }

  func testTheProgressLineSaysTheEpisodesAndTheMostMemoryUsed() {
    XCTAssertEqual(
      ChunkRead.progressLine(episodes: 200, peakBytes: 1_288_490_189),
      "Read the audio of 200 episodes. The most memory used so far is 1.2 GB.")
    XCTAssertEqual(
      ChunkRead.progressLine(episodes: 100, peakBytes: 52_428_800),
      "Read the audio of 100 episodes. The most memory used so far is 0.05 GB.")
  }

  func testTheLineComesEveryHundredEpisodes() {
    XCTAssertFalse(ChunkRead.saysProgress(after: 0))
    XCTAssertFalse(ChunkRead.saysProgress(after: 99))
    XCTAssertTrue(ChunkRead.saysProgress(after: 100))
    XCTAssertFalse(ChunkRead.saysProgress(after: 150))
    XCTAssertTrue(ChunkRead.saysProgress(after: 300))
  }
}
