import XCTest

@testable import PodcastAudioMatch

/// 128 kbps frames whose bytes are told apart by an id, and whose side information starts with a
/// chosen bit reservoir pointer. The same id and pointer give the same bytes in any file.
enum Marked {
  static func frame(_ id: Int, pointer: Int = 5) -> [UInt8] {
    var bytes = Synth.frame(kbps: 128)
    bytes[4] = UInt8(pointer >> 1)
    bytes[5] = UInt8(pointer & 1) << 7
    bytes[100] = UInt8(id & 0xFF)
    bytes[101] = UInt8(id >> 8 & 0xFF)
    bytes[102] = UInt8(id >> 16 & 0xFF)
    return bytes
  }

  static func frames(_ ids: Range<Int>, pointer: Int = 5) -> [UInt8] {
    ids.flatMap { frame($0, pointer: pointer) }
  }

  static func parse(_ parts: [UInt8]...) -> MP3Parse { MP3Frames.parse(parts.flatMap { $0 }) }
}

final class SharedRunsTests: XCTestCase {
  func testASpotAtDifferentPlacesInTwoEpisodesIsOneRun() {
    let spot = Marked.frames(0..<1150)
    let a = Marked.parse(Marked.frames(10_000..<10_200), spot, Marked.frames(11_000..<11_300))
    let b = Marked.parse(spot, Marked.frames(20_000..<20_400))
    XCTAssertEqual(SharedRuns.find(a, b), [SharedRun(a: 200..<1350, b: 0..<1150)])
  }

  func testARunOf100FramesIsNotReported() {
    let spot = Marked.frames(0..<100)
    let a = Marked.parse(Marked.frames(10_000..<10_200), spot)
    let b = Marked.parse(spot, Marked.frames(20_000..<20_400))
    XCTAssertTrue(SharedRuns.find(a, b).isEmpty)
    XCTAssertEqual(SharedRuns.find(a, b, minFrames: 100).count, 1)
  }

  func test300EqualFramesOfOneHashAreNotARun() {
    let silence = (0..<300).flatMap { _ in Marked.frame(7) }
    XCTAssertTrue(SharedRuns.find(Marked.parse(silence), Marked.parse(silence)).isEmpty)
  }

  func testAStretchThatRepeatsTenDifferentFramesIsNotARun() {
    // 130 frames long, but only 10 different ones: fewer than the 20 a run needs.
    let loop = (0..<130).flatMap { Marked.frame($0 % 10) }
    let a = Marked.parse(Marked.frames(10_000..<10_050), loop)
    let b = Marked.parse(loop, Marked.frames(20_000..<20_050))
    XCTAssertTrue(SharedRuns.find(a, b).isEmpty)
  }

  func testEqualFramesInTheMiddleOfASpotDoNotSplitIt() {
    // A spot with 40 frames of digital silence in the middle, equal in both files.
    let spot =
      Marked.frames(0..<100) + (0..<40).flatMap { _ in Marked.frame(9_999) }
      + Marked.frames(100..<200)
    let a = Marked.parse(Marked.frames(10_000..<10_030), spot)
    let b = Marked.parse(spot, Marked.frames(20_000..<20_030))
    // The spot is 100 + 40 + 100 frames long.
    XCTAssertEqual(SharedRuns.find(a, b), [SharedRun(a: 30..<270, b: 0..<240)])
  }

  func testTwoSpotsInAnotherOrderAreTwoRunsInTheOrderOfTheFirstFile() {
    let x = Marked.frames(0..<150)
    let y = Marked.frames(1_000..<1_200)
    let a = Marked.parse(x, Marked.frames(10_000..<10_050), y)
    let b = Marked.parse(y, Marked.frames(20_000..<20_050), x)
    XCTAssertEqual(
      SharedRuns.find(a, b),
      [SharedRun(a: 0..<150, b: 250..<400), SharedRun(a: 200..<400, b: 0..<200)])
  }

  func testFilesWithNothingInCommonAndEmptyFilesGiveNoRuns() {
    let a = Marked.parse(Marked.frames(0..<300))
    let b = Marked.parse(Marked.frames(1_000..<1_300))
    XCTAssertTrue(SharedRuns.find(a, b).isEmpty)
    XCTAssertTrue(SharedRuns.find(a, MP3Frames.parse([])).isEmpty)
    XCTAssertTrue(SharedRuns.find(MP3Frames.parse([]), MP3Frames.parse([])).isEmpty)
  }

  // MARK: What the bytes say at an edge

  func testAResetWithinTwoFramesOfAnEdgeIsFound() {
    // 200 frames that reach back into the reservoir, then a spot whose first frame does not.
    let spot = Marked.frame(0, pointer: 0) + Marked.frames(1..<150)
    let parse = Marked.parse(Marked.frames(10_000..<10_200), spot)
    let report = SeekDrift.report(parse)
    XCTAssertEqual(report.reservoirResets, [200])
    XCTAssertEqual(SharedRuns.evidence(at: 200, in: parse, report: report).reset, 0)
    XCTAssertEqual(SharedRuns.evidence(at: 198, in: parse, report: report).reset, 2)
    XCTAssertEqual(SharedRuns.evidence(at: 202, in: parse, report: report).reset, -2)
    XCTAssertNil(SharedRuns.evidence(at: 197, in: parse, report: report).reset)
    XCTAssertNil(SharedRuns.evidence(at: 203, in: parse, report: report).reset)
    XCTAssertFalse(SharedRuns.evidence(at: 350, in: parse, report: report).any)
  }

  func testAChangeOfEncodingWithinTwoFramesOfAnEdgeIsFound() {
    let parse = MP3Frames.parse(
      Synth.frames(300, kbps: 128) + Synth.frames(100, kbps: 64) + Synth.frames(100, kbps: 128))
    let report = SeekDrift.report(parse)
    XCTAssertEqual(report.seams.count, 2)
    let atTheSeam = SharedRuns.evidence(at: 301, in: parse, report: report)
    XCTAssertTrue(atTheSeam.seam?.contains("64 kbps") == true, atTheSeam.seam ?? "nil")
    XCTAssertTrue(atTheSeam.any)
    XCTAssertNil(SharedRuns.evidence(at: 303, in: parse, report: report).seam)
    XCTAssertNotNil(SharedRuns.evidence(at: 400, in: parse, report: report).seam)
  }

  func testAnEdgeAtTheEndOfTheFileHasNoFrameButCanStillBeChecked() {
    let parse = Marked.parse(Marked.frames(0..<300))
    let report = SeekDrift.report(parse)
    XCTAssertFalse(SharedRuns.evidence(at: 300, in: parse, report: report).any)
    XCTAssertFalse(SharedRuns.evidence(at: 0, in: MP3Frames.parse([]), report: report).any)
  }
}
