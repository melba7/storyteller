import XCTest

@testable import PodcastAudioMatch

final class MP3SideInfoTests: XCTestCase {
  func testTheNineBitPointerOfAnMPEG1FrameIsRead() {
    // The side information starts 0x0A 0x80: 0000 1010 1 is 21.
    let frame = Data([0xFF, 0xFB, 0x90, 0x00, 0x0A, 0x80, 0x00, 0x00])
    XCTAssertEqual(MP3SideInfo.mainDataBegin(frame), 21)
  }

  func testTheLargestAndSmallestMPEG1Pointers() {
    XCTAssertEqual(MP3SideInfo.mainDataBegin(Data([0xFF, 0xFB, 0x90, 0x00, 0xFF, 0x80, 0, 0])), 511)
    XCTAssertEqual(MP3SideInfo.mainDataBegin(Data([0xFF, 0xFB, 0x90, 0x00, 0xFF, 0x7F, 0, 0])), 510)
    XCTAssertEqual(MP3SideInfo.mainDataBegin(Data([0xFF, 0xFB, 0x90, 0x00, 0x00, 0x00, 0, 0])), 0)
  }

  func testTheEightBitPointerOfAnMPEG2FrameIsRead() {
    // 0xF3: MPEG-2, Layer III, no checksum. The first byte is the whole pointer.
    XCTAssertEqual(MP3SideInfo.mainDataBegin(Data([0xFF, 0xF3, 0x90, 0x00, 0xC8, 0x80, 0, 0])), 200)
  }

  func testAChecksumPushesTheSideInformationBackByTwoBytes() {
    // 0xFA: MPEG-1, Layer III, with a checksum (the protection bit is 0).
    let frame = Data([0xFF, 0xFA, 0x90, 0x00, 0x12, 0x34, 0x0A, 0x80])
    XCTAssertEqual(MP3SideInfo.mainDataBegin(frame), 21)
  }

  func testBytesThatAreNotALayerIIIFrameOrAreCutShortGiveNil() {
    XCTAssertNil(MP3SideInfo.mainDataBegin(Data()))
    XCTAssertNil(MP3SideInfo.mainDataBegin(Data([0xFF, 0xFB, 0x90, 0x00, 0x0A])))
    XCTAssertNil(MP3SideInfo.mainDataBegin(Data([0x49, 0x44, 0x33, 0x03, 0, 0, 0, 0])))
    // Layer II (0xFD) and the reserved version (0xEB) are not Layer III.
    XCTAssertNil(MP3SideInfo.mainDataBegin(Data([0xFF, 0xFD, 0x90, 0x00, 0x0A, 0x80, 0, 0])))
    XCTAssertNil(MP3SideInfo.mainDataBegin(Data([0xFF, 0xEB, 0x90, 0x00, 0x0A, 0x80, 0, 0])))
  }

  func testASliceOfLargerDataIsReadFromItsOwnStart() {
    let data = Data([1, 2, 3, 0xFF, 0xFB, 0x90, 0x00, 0x0A, 0x80, 0x00])
    XCTAssertEqual(MP3SideInfo.mainDataBegin(data.dropFirst(3)), 21)
  }

  func testParsedFramesCarryTheirPointer() {
    let parse = Marked.parse(Marked.frame(1, pointer: 21), Marked.frame(2, pointer: 0))
    XCTAssertEqual(parse.frames.map(\.mainDataBegin), [21, 0])
  }
}
