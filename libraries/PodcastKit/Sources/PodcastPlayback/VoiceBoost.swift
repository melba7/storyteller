// LOFI-FORK: the podcast player's voice boost (see FORK.md). Plain values and a plain buffer
// function, no AVFoundation, so it tests on Linux. The iOS part only feeds it audio.
import Foundation

/// How much louder voices are made. A stronger choice adds more gain and squeezes loud parts
/// harder, so quiet voices come up and nothing clips.
public enum BoostStrength: String, CaseIterable, Sendable, Equatable {
  case off, low, medium, high

  /// A stored or typed value; anything that is not a strength is off.
  public init(stored value: Any?) {
    self = (value as? String).flatMap(BoostStrength.init(rawValue:)) ?? .off
  }

  /// What the strength does to the sound, or nil when it does nothing.
  public var parameters: BoostParameters? {
    switch self {
    case .off: return nil
    case .low: return BoostParameters(gain: 1.4, threshold: 0.5, ratio: 2)
    case .medium: return BoostParameters(gain: 2.0, threshold: 0.35, ratio: 3)
    case .high: return BoostParameters(gain: 3.0, threshold: 0.25, ratio: 4)
    }
  }

  /// The strength the player uses: a show's own choice wins over the listener's.
  public static func effective(show: BoostStrength?, listener: BoostStrength) -> BoostStrength {
    show ?? listener
  }
}

/// The numbers of one strength: a linear gain, the level (0 to 1) above which loud parts are
/// squeezed, and the ratio they are squeezed by (3 lets 3 dB in become 1 dB out).
public struct BoostParameters: Sendable, Equatable {
  public var gain: Float
  public var threshold: Float
  public var ratio: Float

  public init(gain: Float, threshold: Float, ratio: Float) {
    self.gain = gain
    self.threshold = threshold
    self.ratio = ratio
  }
}

/// Gain, then a compressor, then a soft limiter, for one channel of audio. It keeps the level
/// it has heard between buffers, so make one per channel and feed it the channel's buffers in
/// order. No output sample is ever as loud as 1.0, and silence stays silent.
public struct VoiceBoost: Sendable {
  /// The loudest an output sample can get, a little under full scale.
  public static let ceiling: Float = 0.97
  /// Below this the limiter does not touch the sound.
  static let knee: Float = 0.8
  static let attackSeconds: Float = 0.005
  static let releaseSeconds: Float = 0.150

  public let parameters: BoostParameters
  private let attack: Float
  private let release: Float
  private var level: Float = 0

  public init(parameters: BoostParameters, sampleRate: Double) {
    self.parameters = parameters
    let rate = Float(sampleRate.isFinite && sampleRate > 1000 ? sampleRate : 44100)
    attack = Self.coefficient(seconds: Self.attackSeconds, rate: rate)
    release = Self.coefficient(seconds: Self.releaseSeconds, rate: rate)
  }

  private static func coefficient(seconds: Float, rate: Float) -> Float {
    1 - exp(-1 / (seconds * rate))
  }

  /// Boosts `samples` in place.
  public mutating func process(_ samples: UnsafeMutableBufferPointer<Float>) {
    for index in samples.indices { samples[index] = process(samples[index]) }
  }

  /// Boosts one sample.
  public mutating func process(_ sample: Float) -> Float {
    guard sample.isFinite else { return 0 }
    let boosted = sample * parameters.gain
    let loudness = abs(boosted)
    // The level follows peaks up quickly and lets go slowly.
    level += (loudness > level ? attack : release) * (loudness - level)
    var out = boosted
    if level > parameters.threshold {
      let squeezed = parameters.threshold + (level - parameters.threshold) / parameters.ratio
      out *= squeezed / level
    }
    return Self.limit(out)
  }

  /// A smooth ceiling: untouched up to the knee, then bent so it never reaches `ceiling`.
  public static func limit(_ x: Float) -> Float {
    let size = abs(x)
    guard size > knee else { return x }
    let room = ceiling - knee
    let bent = knee + room * tanh((size - knee) / room)
    return x < 0 ? -bent : bent
  }
}
