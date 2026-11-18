// LOFI-FORK: the podcast player's rules (see FORK.md). Plain values, no AVFoundation.
import Foundation

/// What the player remembers so that Play can start a failed episode again. A failed item no
/// longer plays (Apple's words) and its clock reads 0, so the last place that was good is kept
/// while the item is fine, and is the place to report and to load again once it has failed.
public struct PlayRecovery: Equatable, Sendable {
  private var lastGood = 0.0
  private var failed = false

  public init() {}

  /// A new item was loaded, to start at `place`. It forgets any failure of the one before.
  public mutating func loaded(startingAt place: Double) {
    failed = false
    lastGood = Self.usable(place) ?? 0
  }

  /// The clock was read. A failed item's clock is not a place, so it is ignored after a
  /// failure, and so is a value that is not a number.
  public mutating func noted(_ place: Double) {
    guard !failed, let place = Self.usable(place) else { return }
    lastGood = place
  }

  /// The listener (or the player on the listener's behalf) moved the place. This also counts
  /// after a failure: Play then loads the episode again where the listener moved to.
  public mutating func moved(to place: Double) {
    guard let place = Self.usable(place) else { return }
    lastGood = place
  }

  /// The item failed to play.
  public mutating func itemFailed() { failed = true }

  /// Where to load the episode again, or nil while the item is fine.
  public var reloadPlace: Double? { failed ? lastGood : nil }

  /// The place to report: the last good one after a failure, else what the player says.
  public func place(reported: Double) -> Double { failed ? lastGood : reported }

  private static func usable(_ place: Double) -> Double? {
    place.isFinite ? max(0, place) : nil
  }
}
