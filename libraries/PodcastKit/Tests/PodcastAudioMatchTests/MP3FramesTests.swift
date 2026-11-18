import XCTest

@testable import PodcastAudioMatch

/// Hand-built MP3 bytes: MPEG-1 Layer III, 128 kbps, 44.1 kHz, so a frame is 417 or 418 bytes
/// and lasts 1152 / 44100 seconds.
enum Fake {
  static func frame(_ fill: UInt8, padding: Bool = false) -> [UInt8] {
    let length = padding ? 418 : 417
    var bytes = [UInt8](repeating: fill, count: length)
    bytes[0] = 0xFF
    bytes[1] = 0xFB  // MPEG-1, Layer III, no CRC
    bytes[2] = 0x90 | (padding ? 0x02 : 0)  // 128 kbps, 44.1 kHz
    bytes[3] = 0x00
    return bytes
  }

  static func id3(size: Int) -> [UInt8] {
    var bytes: [UInt8] = [0x49, 0x44, 0x33, 3, 0, 0]
    bytes += [UInt8((size >> 21) & 0x7F), UInt8((size >> 14) & 0x7F), UInt8((size >> 7) & 0x7F), UInt8(size & 0x7F)]
    return bytes + [UInt8](repeating: 0, count: size)
  }
}

final class MP3FramesTests: XCTestCase {
  func testCutsFramesWithSizesAndTimes() {
    let bytes = Fake.frame(1) + Fake.frame(2, padding: true) + Fake.frame(3)
    let result = MP3Frames.parse(bytes)
    XCTAssertEqual(result.frames.count, 3)
    XCTAssertEqual(result.frames.map(\.length), [417, 418, 417])
    XCTAssertEqual(result.frames[1].offset, 417)
    XCTAssertEqual(result.frames[2].start, 2 * 1152.0 / 44100, accuracy: 1e-9)
    XCTAssertEqual(result.seconds, 3 * 1152.0 / 44100, accuracy: 1e-9)
    XCTAssertEqual(result.bitrate, 128_000)
  }

  func testAnID3TagIsSkipped() {
    let tag = Fake.id3(size: 1000)
    let result = MP3Frames.parse(tag + Fake.frame(1) + Fake.frame(2))
    XCTAssertEqual(result.tagBytes, 1010)
    XCTAssertEqual(result.frames.count, 2)
    XCTAssertEqual(result.frames[0].offset, 1010)
    XCTAssertEqual(result.frames[0].start, 0)
  }

  func testIdenticalFramesHaveTheSameHashAndDifferentOnesDoNot() {
    let result = MP3Frames.parse(Fake.frame(1) + Fake.frame(1) + Fake.frame(2))
    XCTAssertEqual(result.frames[0].hash, result.frames[1].hash)
    XCTAssertNotEqual(result.frames[0].hash, result.frames[2].hash)
  }

  func testGarbageBetweenFramesIsSkippedWithoutACrash() {
    let junk = [UInt8](repeating: 0x55, count: 37)
    let result = MP3Frames.parse(Fake.frame(1) + Fake.frame(2) + junk + Fake.frame(3) + Fake.frame(4))
    XCTAssertEqual(result.frames.count, 4)
    XCTAssertEqual(result.skippedBytes, 37)
  }

  func testABrokenHeaderIsHandled() {
    // Reserved bitrate (1111), reserved sample rate (11), layer I and a lone 0xFF at the end.
    var bad = Fake.frame(1)
    bad[2] = 0xFF
    let result = MP3Frames.parse(bad + Fake.frame(2) + Fake.frame(3) + [0xFF])
    XCTAssertEqual(result.frames.count, 2)
    XCTAssertTrue(MP3Frames.parse([]).frames.isEmpty)
    XCTAssertTrue(MP3Frames.parse([0xFF]).frames.isEmpty)
    XCTAssertTrue(MP3Frames.parse([0x49, 0x44, 0x33]).frames.isEmpty)
  }

  func testATruncatedLastFrameIsLeftOut() {
    let result = MP3Frames.parse(Fake.frame(1) + Fake.frame(2) + Array(Fake.frame(3).prefix(200)))
    XCTAssertEqual(result.frames.count, 2)
  }

  func testATagThatClaimsMoreThanThereIsGivesNothing() {
    let result = MP3Frames.parse(Array(Fake.id3(size: 5000).prefix(100)))
    XCTAssertTrue(result.frames.isEmpty)
  }
}
