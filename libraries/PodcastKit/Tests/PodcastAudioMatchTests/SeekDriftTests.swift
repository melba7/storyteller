import XCTest

@testable import PodcastAudioMatch

/// Hand-built MPEG-1 Layer III frames of any bitrate at 44.1 or 48 kHz, in stereo or mono.
enum Synth {
  private static let kbpsTable = [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]

  static func frame(
    kbps: Int, rate: Int = 44100, mono: Bool = false, padding: Bool = false, tag: String? = nil
  ) -> [UInt8] {
    let length = 144 * kbps * 1000 / rate + (padding ? 1 : 0)
    var bytes = [UInt8](repeating: 1, count: length)
    bytes[0] = 0xFF
    bytes[1] = 0xFB  // MPEG-1, Layer III, no CRC
    let kbpsIndex = UInt8((kbpsTable.firstIndex(of: kbps) ?? 0) + 1)
    let rateIndex: UInt8 = rate == 48000 ? 1 : 0
    bytes[2] = kbpsIndex << 4 | rateIndex << 2 | (padding ? 0x02 : 0)
    bytes[3] = mono ? 0xC0 : 0x00
    if let tag {
      let at = mono ? 21 : 36  // after the header and the side information
      bytes.replaceSubrange(at..<at + 4, with: Array(tag.utf8))
    }
    return bytes
  }

  static func frames(_ count: Int, kbps: Int, rate: Int = 44100, mono: Bool = false) -> [UInt8] {
    (0..<count).flatMap { _ in frame(kbps: kbps, rate: rate, mono: mono) }
  }
}

final class SeekDriftTests: XCTestCase {
  private let frameSeconds = 1152.0 / 44100

  func testEqualFramesAreSteadyAndTheRatioGuessIsRight() {
    let report = SeekDrift.report(MP3Frames.parse(Synth.frames(4000, kbps: 128)))
    XCTAssertTrue(report.steady)
    XCTAssertEqual(report.worstSeconds, 0, accuracy: 0.001)
    XCTAssertEqual(report.framesPerBitrate, [128_000: 4000])
    XCTAssertTrue(report.seams.isEmpty)
  }

  func testPaddedFramesOfOneBitrateStayWithinAFewMilliseconds() {
    // A real constant-bitrate file mixes 417 and 418 byte frames.
    let bytes = (0..<4000).flatMap { Synth.frame(kbps: 128, padding: $0 % 3 == 0) }
    let report = SeekDrift.report(MP3Frames.parse(bytes))
    XCTAssertTrue(report.steady)
    XCTAssertLessThan(report.worstSeconds, 0.05)
  }

  func testTwoBitratesAreNotSteadyAndTheRatioGuessIsFarOff() {
    // 1,000 frames of 417 bytes, then 3,000 of 209: 26 s of audio in 40% of the bytes.
    let bytes =
      Synth.frames(1000, kbps: 128)
      + (0..<3000).flatMap { _ in Synth.frame(kbps: 64, padding: true) }
    let parse = MP3Frames.parse(bytes)
    XCTAssertEqual(parse.frames.count, 4000)
    XCTAssertEqual(parse.frames[1000].length, 209)
    let report = SeekDrift.report(parse)
    XCTAssertFalse(report.steady)
    XCTAssertEqual(report.framesPerBitrate, [128_000: 1000, 64_000: 3000])
    // The player asks for 41.7 s, guesses the byte at that share of the file (byte 417,000, where
    // the 64 kbps part begins) and gets audio from 26.1 s: 15.6 s early. (At the 26.1 s seam
    // itself the error is 9.8 s; the worst is further on.)
    XCTAssertEqual(report.worstSeconds, 15.6, accuracy: 0.2)
  }

  func testNinetyNineInAHundredFramesAtOneBitrateIsSteady() {
    let nearly = Synth.frames(990, kbps: 128) + Synth.frames(10, kbps: 64)
    XCTAssertTrue(SeekDrift.report(MP3Frames.parse(nearly)).steady)
    let less = Synth.frames(980, kbps: 128) + Synth.frames(20, kbps: 64)
    XCTAssertFalse(SeekDrift.report(MP3Frames.parse(less)).steady)
  }

  func testAChangeOfBitrateThatHoldsIsASeam() {
    let bytes =
      Synth.frames(300, kbps: 128) + Synth.frames(100, kbps: 64) + Synth.frames(300, kbps: 128)
    let seams = SeekDrift.report(MP3Frames.parse(bytes)).seams
    XCTAssertEqual(seams.count, 2)
    XCTAssertEqual(seams[0].time, 300 * frameSeconds, accuracy: 0.001)
    XCTAssertEqual(seams[1].time, 400 * frameSeconds, accuracy: 0.001)
    XCTAssertTrue(seams[0].reason.contains("128 kbps"), seams[0].reason)
    XCTAssertTrue(seams[0].reason.contains("64 kbps"), seams[0].reason)
  }

  func testAShortChangeIsNoSeam() {
    let bytes =
      Synth.frames(300, kbps: 128) + Synth.frames(49, kbps: 64) + Synth.frames(300, kbps: 128)
    XCTAssertTrue(SeekDrift.report(MP3Frames.parse(bytes)).seams.isEmpty)
  }

  func testAChangeOfSampleRateOrChannelsIsASeam() {
    let bytes =
      Synth.frames(100, kbps: 128) + Synth.frames(100, kbps: 128, rate: 48000)
      + Synth.frames(100, kbps: 128, rate: 48000, mono: true)
    let seams = SeekDrift.report(MP3Frames.parse(bytes)).seams
    XCTAssertEqual(seams.count, 2)
    XCTAssertTrue(seams[0].reason.contains("48000 Hz"), seams[0].reason)
    XCTAssertTrue(seams[1].reason.contains("mono"), seams[1].reason)
  }

  func testAnInfoOrXingTagAfterTheFirstFrameIsASeam() {
    // The first frame of an encoded file has the tag; one in the middle is where two files join.
    let bytes =
      Synth.frame(kbps: 128, tag: "Info") + Synth.frames(199, kbps: 128)
      + Synth.frame(kbps: 128, tag: "Xing") + Synth.frames(99, kbps: 128)
    let seams = SeekDrift.report(MP3Frames.parse(bytes)).seams
    XCTAssertEqual(seams.count, 1)
    XCTAssertEqual(seams[0].time, 200 * frameSeconds, accuracy: 0.001)
    XCTAssertTrue(seams[0].reason.contains("Xing"), seams[0].reason)
  }

  func testNoFramesGiveAnEmptyReport() {
    let report = SeekDrift.report(MP3Frames.parse([]))
    XCTAssertFalse(report.steady)
    XCTAssertEqual(report.worstSeconds, 0)
    XCTAssertTrue(report.framesPerBitrate.isEmpty)
    XCTAssertTrue(report.seams.isEmpty)
  }

  // MARK: Reservoir resets

  func testAResetAfterSixtyFramesWithAPointerIsListedAndOneAfterTenIsNot() {
    let bytes =
      Marked.frames(0..<60) + Marked.frame(100, pointer: 0) + Marked.frames(101..<111)
      + Marked.frame(200, pointer: 0) + Marked.frames(201..<260)
    let report = SeekDrift.report(MP3Frames.parse(bytes))
    XCTAssertEqual(report.reservoirResets, [60])
  }

  func testFramesThatNeverHaveAnEmptyReservoirHaveNoResets() {
    XCTAssertTrue(SeekDrift.report(MP3Frames.parse(Marked.frames(0..<300))).reservoirResets.isEmpty)
  }

  func testOnlyTheFirstOfSeveralEmptyFramesIsAReset() {
    let bytes =
      Marked.frames(0..<60) + (0..<3).flatMap { Marked.frame(100 + $0, pointer: 0) }
      + Marked.frames(200..<260) + Marked.frame(300, pointer: 0)
    XCTAssertEqual(SeekDrift.report(MP3Frames.parse(bytes)).reservoirResets, [60, 123])
  }

  func testTheFirstFrameOfAFileIsNotAReset() {
    let bytes = Marked.frame(0, pointer: 0) + Marked.frames(1..<80)
    XCTAssertTrue(SeekDrift.report(MP3Frames.parse(bytes)).reservoirResets.isEmpty)
  }
}
