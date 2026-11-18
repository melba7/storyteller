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
  /// An intro that reaches within this many seconds of the end of an episode is not skipped
  /// (see `ShowRules.start`).
  public static let nearEnd = 10.0

  /// 0 when the episode was played or the saved place is not a usable number; otherwise the
  /// saved place, never later.
  ///
  /// The length does not decide. A feed's length is often shorter than the real audio (ads
  /// are inserted, or the feed is wrong), and an episode stopped past that length, or in its
  /// last seconds, used to start again at 0:00. An episode stopped at its real end is already
  /// marked played, which starts it over. `duration` stays in the signature so no caller changes.
  public static func start(savedPosition: Double, duration: Double?, played: Bool) -> Double {
    if played || !savedPosition.isFinite || savedPosition <= 0 { return 0 }
    return savedPosition
  }
}

/// When an episode counts as played.
public enum PlayedRule {
  /// Stopping this close to the end counts as played.
  public static let nearEnd = 5.0
  /// A clock that overshoots the end by this much is still at the end.
  public static let pastEndSlack = 1.0

  /// `within` is how many seconds from the end count as played: the listener's setting (see
  /// PlaybackSettings.markPlayedWhenLeft), never less than `nearEnd`. A place more than
  /// `pastEndSlack` past the length is not the end: the length is the feed's guess (the audio
  /// has not told its own yet), so the episode is not played.
  public static func isPlayed(
    position: Double, duration: Double?, reachedEnd: Bool, within: Double = nearEnd
  ) -> Bool {
    if reachedEnd { return true }
    guard let duration, duration.isFinite, duration > 0, position.isFinite else { return false }
    let left = duration - position
    if left < -pastEndSlack { return false }
    return left <= max(within, nearEnd)
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
