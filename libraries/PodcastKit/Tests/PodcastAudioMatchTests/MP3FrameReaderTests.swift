import XCTest

@testable import PodcastAudioMatch

final class MP3FrameReaderTests: XCTestCase {
  private func read(_ bytes: [UInt8], pieces: [Int]) -> [MP3Frame] {
    var reader = MP3FrameReader()
    var frames: [MP3Frame] = []
    var at = 0
    var turn = 0
    while at < bytes.count {
      let size = pieces[turn % pieces.count]
      frames += reader.feed(Array(bytes[at..<min(at + size, bytes.count)]))
      XCTAssertLessThanOrEqual(reader.pending, 2000)
      at += size
      turn += 1
    }
    return frames
  }

  private var file: [UInt8] {
    var bytes: [UInt8] = Fake.id3(size: 300)
    bytes += Marked.frames(0..<20)
    bytes += Fake.frame(7, padding: true)
    bytes += Marked.frames(20..<40)
    bytes += [UInt8](repeating: 0x55, count: 37)
    bytes += Marked.frames(40..<60)
    bytes += [0xFF, 0xFB, 0x90, 0x00]  // looks like a header
    bytes += [UInt8](repeating: 0x11, count: 50)
    bytes += Marked.frames(60..<90)
    return bytes
  }

  func testAnySplitGivesTheFramesOfParse() {
    let bytes = file
    let expected = MP3Frames.parse(bytes).frames
    XCTAssertEqual(expected.count, 91)
    for pieces in [[1], [2], [7], [100], [417], [418, 3], [1000], [5, 400, 1], [bytes.count]] {
      XCTAssertEqual(read(bytes, pieces: pieces), expected, "pieces \(pieces)")
    }
  }

  func testATagSplitAcrossPiecesIsSkipped() {
    let bytes = Fake.id3(size: 2000) + Marked.frames(0..<10)
    var reader = MP3FrameReader()
    XCTAssertTrue(reader.feed(Array(bytes[0..<5])).isEmpty)
    XCTAssertTrue(reader.feed(Array(bytes[5..<1200])).isEmpty)
    let frames = reader.feed(Array(bytes[1200...]))
    XCTAssertEqual(frames, MP3Frames.parse(bytes).frames)
    XCTAssertEqual(frames.first?.offset, 2010)
    XCTAssertEqual(frames.first?.start, 0)
  }

  func testAFileWithoutATag() {
    let bytes = Marked.frames(0..<5)
    XCTAssertEqual(read(bytes, pieces: [1]), MP3Frames.parse(bytes).frames)
  }

  func testACutOffLastFrameIsNeverReturned() {
    let bytes = Marked.frames(0..<5) + Array(Marked.frame(5)[0..<300])
    XCTAssertEqual(read(bytes, pieces: [50]).count, 5)
  }

  func testEmptyAndNonMP3BytesGiveNothing() {
    var reader = MP3FrameReader()
    XCTAssertTrue(reader.feed([]).isEmpty)
    XCTAssertTrue(reader.feed([UInt8](repeating: 0x20, count: 5000)).isEmpty)
    XCTAssertLessThanOrEqual(reader.pending, 4)
  }
}
