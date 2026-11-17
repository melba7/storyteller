// LOFI-FORK: the podcast player's rules (see FORK.md). Plain values, no AVFoundation.
import Foundation

/// A playback speed: 0.5x to 3.0x in steps of 0.1, as Pocket Casts allows.
public struct Speed: Equatable, Sendable {
  public static let minimum = 0.5
  public static let maximum = 3.0
  public static let normal = Speed(tenths: 10)

  /// The speed in tenths, so repeated steps never drift (11 is 1.1x).
  private let tenths: Int

  private init(tenths: Int) {
    self.tenths = min(30, max(5, tenths))
  }

  /// The speed as a rate for the player.
  public var value: Double { Double(tenths) / 10 }

  /// The nearest allowed speed to `rate`. Not a number gives normal speed.
  public static func clamped(_ rate: Double) -> Speed {
    guard rate.isFinite else { return .normal }
    return Speed(tenths: Int((rate * 10).rounded()))
  }

  /// One step faster, stopping at 3.0x.
  public var up: Speed { Speed(tenths: tenths + 1) }

  /// One step slower, stopping at 0.5x.
  public var down: Speed { Speed(tenths: tenths - 1) }
}
