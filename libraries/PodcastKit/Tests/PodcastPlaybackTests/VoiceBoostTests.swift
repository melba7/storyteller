import XCTest

@testable import PodcastPlayback

final class VoiceBoostTests: XCTestCase {
  private func sine(amplitude: Float, count: Int = 44100, rate: Double = 44100) -> [Float] {
    (0..<count).map { amplitude * sin(2 * .pi * 220 * Float($0) / Float(rate)) }
  }

  private func rms(_ samples: [Float]) -> Float {
    sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
  }

  private func boosted(_ strength: BoostStrength, _ input: [Float]) throws -> [Float] {
    var boost = VoiceBoost(parameters: try XCTUnwrap(strength.parameters), sampleRate: 44100)
    var samples = input
    samples.withUnsafeMutableBufferPointer { boost.process($0) }
    return samples
  }

  func testOffDoesNothingAndTheStrengthsGrow() throws {
    XCTAssertNil(BoostStrength.off.parameters)
    let gains = try [BoostStrength.low, .medium, .high].map { try XCTUnwrap($0.parameters).gain }
    XCTAssertEqual(gains, gains.sorted())
    XCTAssertTrue(gains.allSatisfy { $0 > 1 })
  }

  func testStoredValuesFallBackToOff() {
    XCTAssertEqual(BoostStrength(stored: "medium"), .medium)
    XCTAssertEqual(BoostStrength(stored: "loud"), .off)
    XCTAssertEqual(BoostStrength(stored: nil), .off)
    XCTAssertEqual(BoostStrength(stored: 3), .off)
  }

  func testAShowsOwnChoiceWins() {
    XCTAssertEqual(BoostStrength.effective(show: .off, listener: .high), .off)
    XCTAssertEqual(BoostStrength.effective(show: .low, listener: .high), .low)
    XCTAssertEqual(BoostStrength.effective(show: nil, listener: .high), .high)
  }

  func testAQuietVoiceComesUp() throws {
    let quiet = sine(amplitude: 0.05)
    let out = try boosted(.medium, quiet)
    // 0.05 x 2 stays under the threshold, so the gain is applied as it is.
    XCTAssertEqual(rms(out) / rms(quiet), 2.0, accuracy: 0.05)
  }

  func testStrongerBoostIsLouder() throws {
    let quiet = sine(amplitude: 0.05)
    let low = rms(try boosted(.low, quiet))
    let medium = rms(try boosted(.medium, quiet))
    let high = rms(try boosted(.high, quiet))
    XCTAssertLessThan(low, medium)
    XCTAssertLessThan(medium, high)
  }

  func testPeaksNeverReachFullScale() throws {
    for strength in [BoostStrength.low, .medium, .high] {
      for amplitude: Float in [0.3, 0.8, 1.0] {
        let out = try boosted(strength, sine(amplitude: amplitude))
        XCTAssertLessThan(out.map { abs($0) }.max() ?? 0, 1.0, "\(strength) at \(amplitude)")
      }
    }
    // Even a sample out of range (or not a number) is tamed.
    let wild = try boosted(.high, [5, -5, .nan, .infinity, 0.5])
    XCTAssertTrue(wild.allSatisfy { $0.isFinite && abs($0) < 1.0 })
  }

  func testLoudPartsAreSqueezedMoreThanQuietOnes() throws {
    let quiet = rms(try boosted(.high, sine(amplitude: 0.05)))
    let loud = rms(try boosted(.high, sine(amplitude: 0.5)))
    // The input is 10x louder; the output is much less than 10x louder.
    XCTAssertLessThan(loud / quiet, 6)
  }

  func testSilenceStaysSilent() throws {
    let out = try boosted(.high, [Float](repeating: 0, count: 5000))
    XCTAssertTrue(out.allSatisfy { $0 == 0 })
  }

  func testTheLimiterLeavesQuietSoundAlone() {
    XCTAssertEqual(VoiceBoost.limit(0.5), 0.5)
    XCTAssertEqual(VoiceBoost.limit(-0.7), -0.7)
    XCTAssertLessThan(VoiceBoost.limit(2), 1)
    XCTAssertGreaterThan(VoiceBoost.limit(-2), -1)
  }
}
