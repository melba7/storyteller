import Foundation

@testable import PodcastAudioMatch

/// Made-up sound for the edge tests. The sample rate is low, so a debug build stays quick, and
/// every signal is the same on every machine.
enum EdgeSynth {
  static let rate = 4000.0

  /// Steady noise: each sample is a random number between -amplitude and amplitude.
  static func noise(_ seconds: Double, _ amplitude: Float, seed: UInt64 = 1) -> [Float] {
    var state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
    return (0..<Int(seconds * rate)).map { _ in
      state ^= state << 13
      state ^= state >> 7
      state ^= state << 17
      return (Float(state >> 40) / Float(1 << 24) * 2 - 1) * amplitude
    }
  }

  static func tone(_ seconds: Double, hz: Double, _ amplitude: Float) -> [Float] {
    (0..<Int(seconds * rate)).map { Float(sin(2 * Double.pi * hz * Double($0) / rate)) * amplitude }
  }

  static func silence(_ seconds: Double) -> [Float] {
    [Float](repeating: 0, count: Int(seconds * rate))
  }

  /// The blocks of a signal, read in one piece.
  static func blocks(_ samples: [Float]) -> EdgeBlocks {
    var meter = EdgeMeter(sampleRate: rate)
    meter.add(samples)
    return meter.finish()
  }

  /// The peaks of a signal.
  static func peaks(_ samples: [Float]) -> [EdgePeak] {
    EdgeSound.analyse(blocks(samples)).peaks
  }
}
