import XCTest

@testable import PodcastAudioMatch

/// The change score (the 3 seconds before a point against the 3 seconds after) and the peaks of it,
/// on made-up signals whose changes are known.
final class EdgeChangeTests: XCTestCase {
  private func strongest(_ peaks: [EdgePeak]) -> EdgePeak? {
    peaks.max { $0.strength < $1.strength }
  }

  func testAStepInLoudnessIsFoundWithinASecond() throws {
    let peaks = EdgeSynth.peaks(
      EdgeSynth.noise(30, 0.05, seed: 1) + EdgeSynth.noise(30, 0.25, seed: 2))
    let found = try XCTUnwrap(strongest(peaks))
    XCTAssertEqual(found.time, 30, accuracy: 1)
    // 20 log10(5) is 14 dB louder, and the score is in decibels.
    XCTAssertEqual(found.strength, 14, accuracy: 2)
  }

  func testAChangeOfToneAtTheSameLoudnessIsFoundWithinASecond() throws {
    let peaks = EdgeSynth.peaks(
      EdgeSynth.tone(30, hz: 440, 0.3) + EdgeSynth.tone(30, hz: 1500, 0.3))
    let found = try XCTUnwrap(strongest(peaks))
    XCTAssertEqual(found.time, 30, accuracy: 1)
    XCTAssertGreaterThan(found.strength, 10)
  }

  func testASoundThatDoesNotLandOnTheHalfSecondIsStillFoundWithinASecond() throws {
    let peaks = EdgeSynth.peaks(
      EdgeSynth.noise(31.3, 0.05, seed: 1) + EdgeSynth.noise(28, 0.25, seed: 2))
    XCTAssertEqual(try XCTUnwrap(strongest(peaks)).time, 31.3, accuracy: 1)
  }

  func testTheEdgesOfAPauseAreFound() {
    let peaks = EdgeSynth.peaks(
      EdgeSynth.noise(30, 0.1, seed: 1) + EdgeSynth.silence(4) + EdgeSynth.noise(30, 0.1, seed: 2))
    XCTAssertEqual(peaks.count, 2, "\(peaks)")
    XCTAssertTrue(peaks.contains { abs($0.time - 30) <= 1 }, "\(peaks)")
    XCTAssertTrue(peaks.contains { abs($0.time - 34) <= 1 }, "\(peaks)")
  }

  func testAFlatSignalHasNoStrongPeak() {
    XCTAssertEqual(EdgeSynth.peaks(EdgeSynth.noise(60, 0.1)), [])
    XCTAssertEqual(EdgeSynth.peaks(EdgeSynth.tone(60, hz: 700, 0.2)), [])
    XCTAssertEqual(EdgeSynth.peaks(EdgeSynth.silence(60)), [])
  }

  func testAChangeUnderThreeDecibelsIsNotAPeak() {
    // 0.10 to 0.12 is 1.6 dB.
    XCTAssertEqual(
      EdgeSynth.peaks(EdgeSynth.noise(30, 0.10, seed: 1) + EdgeSynth.noise(30, 0.12, seed: 2)), [])
  }

  func testPointsWhereTheThreeSecondWindowsDoNotFitHaveNoScore() {
    let blocks = EdgeSynth.blocks(
      EdgeSynth.noise(30, 0.05, seed: 1) + EdgeSynth.noise(30, 0.25, seed: 2))
    let scores = EdgeSound.scores(blocks)
    XCTAssertEqual(scores.count, blocks.count + 1)
    XCTAssertEqual(Array(scores[0..<6]), [Float](repeating: 0, count: 6))
    XCTAssertEqual(Array(scores[(scores.count - 5)...]), [Float](repeating: 0, count: 5))
    XCTAssertGreaterThan(scores[60], 10)
    XCTAssertEqual(
      EdgeSound.scores(EdgeSynth.blocks(EdgeSynth.noise(5, 0.1))), [Float](repeating: 0, count: 11))
  }

  func testAPeakIsTheStrongestPointAroundIt() {
    var scores = [Float](repeating: 0, count: 200)
    scores[50] = 5
    scores[52] = 8  // 1 s from the first one: the stronger one wins the places around it
    scores[60] = 4
    scores[61] = 4  // a tie keeps the earlier point
    scores[100] = 2.9  // under the floor
    let peaks = EdgeSound.peaks(scores, seconds: 100)
    XCTAssertEqual(peaks.map(\.time), [26, 30])
    XCTAssertEqual(peaks.map(\.strength), [8, 4])
  }

  func testOnlyTheStrongestPeaksAreKeptAFewHundredAnHour() {
    // A spike every 2 seconds for an hour, stronger and stronger (by more than the 0.01 that is kept).
    var scores = [Float](repeating: 0, count: 7201)
    for place in stride(from: 10, to: 7190, by: 4) { scores[place] = 3 + Float(place) / 100 }
    let peaks = EdgeSound.peaks(scores, seconds: 3600)
    XCTAssertEqual(peaks.count, EdgeSound.peaksPerHour)
    XCTAssertEqual(peaks, peaks.sorted { $0.time < $1.time })
    // The kept ones are the 300 latest spikes, which are the strongest.
    XCTAssertEqual(peaks.first?.time, 2995)
    XCTAssertEqual(peaks.last?.time, 3593)
    XCTAssertEqual(peaks.map(\.strength).min() ?? 0, 62.9, accuracy: 0.01)
  }

  func testAShortEpisodeKeepsTenPeaksAndTheEarlierOnesWinATie() {
    var scores = [Float](repeating: 0, count: 201)
    for place in stride(from: 10, to: 190, by: 8) { scores[place] = 5 }
    let peaks = EdgeSound.peaks(scores, seconds: 100)
    XCTAssertEqual(peaks.map(\.time), (0..<10).map { Double(10 + 8 * $0) / 2 })
  }

  func testTheStrongestPeakWithinTenSecondsIsTheOneThatIsFound() {
    let peaks = [
      EdgePeak(time: 100, strength: 4), EdgePeak(time: 108, strength: 9),
      EdgePeak(time: 111, strength: 20), EdgePeak(time: 91.5, strength: 9),
    ]
    XCTAssertEqual(
      EdgeSound.strongest(near: 100, in: peaks), EdgePeak(time: 108, strength: 9),
      "as strong as the one 8.5 s the other way, and nearer")
    XCTAssertEqual(EdgeSound.strongest(near: 91, in: peaks)?.time, 91.5)
    XCTAssertEqual(EdgeSound.strongest(near: 101, in: peaks)?.time, 111, "10 seconds is inside")
    XCTAssertEqual(
      EdgeSound.strongest(near: 100.5, in: peaks)?.time, 108, "10.5 seconds is outside")
    XCTAssertNil(EdgeSound.strongest(near: 150, in: peaks))
    XCTAssertNil(EdgeSound.strongest(near: 100, in: []))
  }

  func testAWindowFitsOnlyWhenThreeSecondsRemainOnBothSides() {
    XCTAssertTrue(EdgeSound.fits(3, seconds: 100))
    XCTAssertTrue(EdgeSound.fits(97, seconds: 100))
    XCTAssertFalse(EdgeSound.fits(2.9, seconds: 100))
    XCTAssertFalse(EdgeSound.fits(97.1, seconds: 100))
    XCTAssertFalse(EdgeSound.fits(0, seconds: 100))
    XCTAssertFalse(EdgeSound.fits(.nan, seconds: 100))
  }
}
