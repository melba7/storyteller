// LOFI-FORK: the podcast player's rules (see FORK.md). Plain values, no AVFoundation.
import Foundation

/// How far the skip buttons jump, and where a jump may land.
public enum Skip {
  /// Seconds back (Pocket Casts' default).
  public static let back = 10.0
  /// Seconds ahead (Pocket Casts' default).
  public static let ahead = 45.0

  /// Keeps a position inside the episode. With no known duration only 0 is a limit.
  public static func clamp(_ position: Double, duration: Double?) -> Double {
    guard position.isFinite else { return 0 }
    let floor = max(0, position)
    guard let duration, duration.isFinite, duration > 0 else { return floor }
    return min(floor, duration)
  }

  /// Where a jump of `amount` seconds (negative for back) from `position` lands.
  public static func target(from position: Double, by amount: Double, duration: Double?) -> Double {
    clamp(position + amount, duration: duration)
  }
}

/// Where an episode starts when it is loaded.
public enum ResumeRule {
  /// An episode with fewer seconds than this left starts over.
  public static let nearEnd = 10.0

  /// 0 when the episode was played, was left within 10 seconds of its end, or the saved
  /// place is at or past the end or not a usable number; otherwise the saved place.
  public static func start(savedPosition: Double, duration: Double?, played: Bool) -> Double {
    if played || !savedPosition.isFinite || savedPosition <= 0 { return 0 }
    if let duration, duration.isFinite, duration > 0 {
      if savedPosition >= duration || duration - savedPosition < nearEnd { return 0 }
    }
    return savedPosition
  }
}

/// When an episode counts as played.
public enum PlayedRule {
  /// Stopping this close to the end counts as played.
  public static let nearEnd = 5.0

  public static func isPlayed(position: Double, duration: Double?, reachedEnd: Bool) -> Bool {
    if reachedEnd { return true }
    guard let duration, duration.isFinite, duration > 0, position.isFinite else { return false }
    return duration - position <= nearEnd
  }
}

/// Which player owns the lock screen and the headphone buttons.
public enum RemoteOwnerKind: Equatable, Sendable {
  case book
  case podcast
}

/// Whoever started playing last owns the lock screen. Pausing changes nothing, so the card
/// stays where it was until the other player starts.
public struct RemoteOwner: Equatable, Sendable {
  public private(set) var current = RemoteOwnerKind.book

  public init() {}

  public mutating func podcastStartedPlaying() { current = .podcast }
  public mutating func bookStartedPlaying() { current = .book }
  public mutating func podcastPaused() {}
  public mutating func bookPaused() {}
}
