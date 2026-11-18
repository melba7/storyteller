import XCTest

@testable import PodcastAds

final class Mp3PrefixTests: XCTestCase {
  /// A frame of MPEG 1 layer III, 128 kbit/s, 44.1 kHz: 417 bytes, or 418 with padding.
  private func frame(padded: Bool = false) -> Data {
    var bytes: [UInt8] = [0xFF, 0xFB, padded ? 0x92 : 0x90, 0x00]
    bytes += [UInt8](repeating: 0x11, count: (padded ? 418 : 417) - 4)
    return Data(bytes)
  }

  private func tag(_ size: Int) -> Data {
    Data([
      0x49, 0x44, 0x33, 0x04, 0x00, 0x00, UInt8((size >> 21) & 0x7F), UInt8((size >> 14) & 0x7F),
      UInt8((size >> 7) & 0x7F), UInt8(size & 0x7F),
    ])
      + Data(repeating: 0, count: size)
  }

  func testTheCutIsAfterTheLastWholeFrame() {
    let data = frame() + frame(padded: true) + frame() + frame().prefix(200)
    let cut = Mp3Prefix.cut(data)
    XCTAssertEqual(cut?.bytes, 417 + 418 + 417)
    XCTAssertEqual(cut?.frames, 3)
    XCTAssertEqual(cut?.seconds ?? 0, 3 * 1152.0 / 44100, accuracy: 0.0001)
  }

  func testAnId3TagIsSteppedOverAndCounted() {
    let data = tag(300) + frame() + frame()
    let cut = Mp3Prefix.cut(data)
    XCTAssertEqual(cut?.bytes, 310 + 417 * 2)
    XCTAssertEqual(cut?.frames, 2)
  }

  func testATagThatIsNotWholeOrNoWholeFrameGivesNoCut() {
    XCTAssertNil(Mp3Prefix.cut(tag(300).prefix(100)))
    XCTAssertNil(Mp3Prefix.cut(tag(10) + frame().prefix(300)))
    XCTAssertNil(Mp3Prefix.cut(Data(repeating: 0x41, count: 5000)))
  }

  func testTheCutStopsWhereTheFramesStop() {
    let data = frame() + frame() + Data(repeating: 0x00, count: 600) + frame()
    XCTAssertEqual(Mp3Prefix.cut(data)?.frames, 2)
  }

  func testALargeTagMeansNeedMoreUntilTheAudioAfterItIsThere() {
    let whole = tag(700_000) + frame() + frame() + frame()
    XCTAssertEqual(Mp3Prefix.look(whole.prefix(5)), .needMore(audioStart: nil))
    XCTAssertEqual(Mp3Prefix.look(whole.prefix(484_000)), .needMore(audioStart: 700_010))
    XCTAssertEqual(Mp3Prefix.look(whole.prefix(700_010 + 200)), .needMore(audioStart: 700_010))
    let cut = Mp3Prefix.cut(whole)
    XCTAssertEqual(cut?.frames, 3)
    XCTAssertEqual(cut?.audioStart, 700_010)
    XCTAssertEqual(cut?.bytes, 700_010 + 417 * 3)
  }

  func testAStraySyncPairBeforeTheFirstFrameIsNotAFrame() {
    // A header-shaped pair in the tag's padding, with no frame after it.
    let bogus = Data([0xFF, 0xFB, 0x90, 0x00]) + Data(repeating: 0x00, count: 600)
    let data = tag(20) + bogus + frame() + frame() + frame()
    let cut = Mp3Prefix.cut(data)
    XCTAssertEqual(cut?.frames, 3)
    XCTAssertEqual(cut?.bytes, 30 + 604 + 417 * 3)
  }

  func testJunkAfterTheTagIsWaitedPastAndThenGivenUpOn() {
    let junk = tag(10) + Data(repeating: 0x41, count: 5000)
    XCTAssertEqual(Mp3Prefix.look(junk), .needMore(audioStart: 20))
    let later = junk + Data(repeating: 0x41, count: Mp3Prefix.searchWindow)
    XCTAssertEqual(Mp3Prefix.look(later), .notMp3)
    // Junk, then the real frames: found.
    XCTAssertEqual(Mp3Prefix.cut(junk + frame() + frame())?.frames, 2)
  }

  func testALastFrameNeedsNoFollowerOnlyWhenTheFileIsComplete() {
    XCTAssertNil(Mp3Prefix.cut(frame()))
    XCTAssertEqual(Mp3Prefix.cut(frame(), complete: true)?.frames, 1)
  }
}
