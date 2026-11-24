import XCTest

@testable import PodcastAudioMatch

/// What each half second of a made-up signal sounds like: its loudness, its 24 bands and whether
/// it is a pause.
final class EdgeSoundTests: XCTestCase {
  func testALoudnessIsInDecibelsOfTheRootMeanSquare() {
    // A sine of amplitude 0.5 has a root mean square of 0.3536, which is -9.03 dB.
    let blocks = EdgeSynth.blocks(EdgeSynth.tone(10, hz: 440, 0.5))
    XCTAssertEqual(blocks.count, 20)
    for value in blocks.loudness { XCTAssertEqual(value, -9.03, accuracy: 0.1) }
  }

  func testAToneIsLoudestInTheBandThatHoldsItsFrequency() throws {
    let edges = EdgeSound.bandEdges(sampleRate: EdgeSynth.rate)
    XCTAssertEqual(edges.count, EdgeSound.bandCount + 1)
    for hz in [320.0, 670.0, 1580.0] {
      let blocks = EdgeSynth.blocks(EdgeSynth.tone(5, hz: hz, 0.3))
      let bands = Array(blocks.bands[0..<EdgeSound.bandCount])
      let loudest = try XCTUnwrap(bands.indices.max { bands[$0] < bands[$1] })
      XCTAssertTrue(
        edges[loudest] <= hz && hz < edges[loudest + 1],
        "\(hz) Hz was loudest in the band \(edges[loudest])...\(edges[loudest + 1])")
    }
  }

  func testPiecesOfAnySizeGiveTheSameBlocks() {
    let signal = EdgeSynth.noise(8, 0.2) + EdgeSynth.tone(8, hz: 900, 0.2)
    var pieces = EdgeMeter(sampleRate: EdgeSynth.rate)
    var at = 0
    var turn = 0
    let sizes = [1, 7, 1999, 2000, 2001, 3, 10_000]
    while at < signal.count {
      pieces.add(Array(signal[at..<min(at + sizes[turn % sizes.count], signal.count)]))
      at += sizes[turn % sizes.count]
      turn += 1
    }
    XCTAssertEqual(pieces.finish(), EdgeSynth.blocks(signal))
  }

  func testAPieceShorterThanHalfASecondAtTheEndIsLeftOut() {
    XCTAssertEqual(EdgeSynth.blocks(EdgeSynth.noise(3.4, 0.2)).count, 6)
    XCTAssertEqual(EdgeSynth.blocks([]).count, 0)
  }

  func testASampleThatIsNotANumberCountsAsSilence() {
    var signal = EdgeSynth.noise(2, 0.2)
    signal[100] = .nan
    signal[200] = .infinity
    let blocks = EdgeSynth.blocks(signal)
    XCTAssertTrue(blocks.loudness.allSatisfy(\.isFinite))
    XCTAssertTrue(blocks.bands.allSatisfy(\.isFinite))
  }

  func testHalfSecondsOfNothingBetweenSoundAreAPause() {
    let blocks = EdgeSynth.blocks(
      EdgeSynth.noise(5, 0.2, seed: 1) + EdgeSynth.silence(2) + EdgeSynth.noise(5, 0.2, seed: 2))
    XCTAssertEqual(blocks.count, 24)
    for index in 0..<24 {
      XCTAssertEqual(blocks.pause[index], (10..<14).contains(index), "\(index)")
    }
  }

  func testWithNoSoundAtAllThereIsNoPause() {
    let blocks = EdgeSynth.blocks(EdgeSynth.silence(6))
    XCTAssertEqual(blocks.count, 12)
    XCTAssertFalse(blocks.pause.contains(true))
  }

  func testAQuietPassageIsNotAPauseWhenItIsAudible() {
    // 14 dB under the rest is quiet speech, not a pause.
    let blocks = EdgeSynth.blocks(
      EdgeSynth.noise(10, 0.25, seed: 1) + EdgeSynth.noise(10, 0.05, seed: 2))
    XCTAssertFalse(blocks.pause.contains(true))
  }
}
