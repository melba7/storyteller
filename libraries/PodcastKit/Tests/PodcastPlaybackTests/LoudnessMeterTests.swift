import XCTest

@testable import PodcastPlayback

final class LoudnessMeterTests: XCTestCase {
  func testAFrameIsFiftyMillisecondsOfSamples() {
    XCTAssertEqual(LoudnessMeter(sampleRate: 16000).samplesPerFrame, 800)
    XCTAssertEqual(LoudnessMeter(sampleRate: 44100).samplesPerFrame, 2205)
  }

  func testLoudnessIsTheRootMeanSquare() {
    var meter = LoudnessMeter(sampleRate: 16000)
    meter.add([Float](repeating: 0.5, count: 800))
    meter.add([Float](repeating: 0, count: 800))
    meter.add([Float](repeating: -0.25, count: 800))
    XCTAssertEqual(meter.frames.count, 3)
    XCTAssertEqual(meter.frames[0], 0.5, accuracy: 1e-6)
    XCTAssertEqual(meter.frames[1], 0)
    XCTAssertEqual(meter.frames[2], 0.25, accuracy: 1e-6)
  }

  func testAFrameCanSpanSeveralPiecesAndAShortEndIsDropped() {
    var meter = LoudnessMeter(sampleRate: 16000)
    meter.add([Float](repeating: 0.4, count: 500))
    XCTAssertTrue(meter.frames.isEmpty)
    meter.add([Float](repeating: 0.4, count: 500))
    XCTAssertEqual(meter.frames.count, 1)
    XCTAssertEqual(meter.frames[0], 0.4, accuracy: 1e-6)
    meter.add([Float](repeating: 0.9, count: 100))
    XCTAssertEqual(meter.frames.count, 1)
  }

  func testNotANumberCountsAsSilence() {
    var meter = LoudnessMeter(sampleRate: 16000)
    meter.add([Float](repeating: .nan, count: 800))
    XCTAssertEqual(meter.frames, [0])
  }

  func testAMeasuredFileGivesTheExpectedGaps() {
    var meter = LoudnessMeter(sampleRate: 16000)
    meter.add([Float](repeating: 0.1, count: 800 * 20))
    meter.add([Float](repeating: 0.0005, count: 800 * 30))
    meter.add([Float](repeating: 0.1, count: 800 * 20))
    XCTAssertEqual(SilenceFinder.gaps(loudness: meter.frames), [SilentGap(start: 1.0, end: 2.5)])
  }
}
