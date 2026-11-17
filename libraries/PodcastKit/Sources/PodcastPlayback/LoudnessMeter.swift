// LOFI-FORK: the podcast player's silence trimming (see FORK.md). Plain values, no AVFoundation.
import Foundation

/// Turns a stream of mono audio samples into how loud each 50 ms was (root mean square, 0 to
/// 1). The app feeds it the decoded samples of a file piece by piece, in order.
public struct LoudnessMeter: Sendable {
  public let samplesPerFrame: Int
  /// The loudness of each whole frame so far.
  public private(set) var frames: [Float] = []
  private var sum = 0.0
  private var counted = 0

  public init(sampleRate: Double, frameSeconds: Double = SilenceFinder.frameSeconds) {
    let rate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 16000
    samplesPerFrame = max(1, Int((rate * frameSeconds).rounded()))
  }

  /// The frames can be of any size: a frame may be finished by a later call. A last piece too
  /// short to make a frame is dropped. A sample that is not a number counts as silence.
  public mutating func add(_ samples: UnsafeBufferPointer<Float>) {
    for sample in samples {
      let value = sample.isFinite ? Double(sample) : 0
      sum += value * value
      counted += 1
      if counted == samplesPerFrame {
        frames.append(Float((sum / Double(counted)).squareRoot()))
        sum = 0
        counted = 0
      }
    }
  }

  public mutating func add(_ samples: [Float]) {
    samples.withUnsafeBufferPointer { add($0) }
  }
}
