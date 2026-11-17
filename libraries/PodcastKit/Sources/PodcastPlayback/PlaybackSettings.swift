// LOFI-FORK: the podcast player's rules (see FORK.md). Plain values, no AVFoundation.
import Foundation

/// What the headphones' next button does. (Previous always skips back.)
public enum HeadphoneNext: String, Equatable, Sendable {
  /// Skip ahead by the skip-forward amount.
  case skip
  /// Start the next episode in Up Next (skips ahead when the queue is empty).
  case nextEpisode
}

/// What the player does about a press of the headphones' or lock screen's next button.
public enum HeadphoneAction: Equatable, Sendable {
  case skip(seconds: Double)
  case nextEpisode
}

/// The listener's playback settings. Stored natively because the player uses them with the
/// screen locked; `init(values:)` and `values` are the stored form, a plain dictionary.
public struct PlaybackSettings: Equatable, Sendable {
  /// The amounts the skip buttons may have, in seconds.
  public static let skipChoices = [5, 10, 15, 30, 45, 60]
  /// "Mark played when this many seconds are left": 0 is off.
  public static let markPlayedChoices = [0, 10, 30, 60]

  public var skipBack = 10
  public var skipForward = 45
  public var headphoneNext = HeadphoneNext.skip
  public var markPlayedWhenLeft = 0
  public var rewindAfterPause = false

  /// The defaults are what the player used before there were settings.
  public init() {}

  /// Reads stored values. Anything missing or not one of the choices keeps its default.
  public init(values: [String: Any]) {
    if let back = values["skipBack"] as? Int, Self.skipChoices.contains(back) {
      skipBack = back
    }
    if let forward = values["skipForward"] as? Int, Self.skipChoices.contains(forward) {
      skipForward = forward
    }
    if let raw = values["headphoneNext"] as? String, let next = HeadphoneNext(rawValue: raw) {
      headphoneNext = next
    }
    if let left = values["markPlayedWhenLeft"] as? Int, Self.markPlayedChoices.contains(left) {
      markPlayedWhenLeft = left
    }
    if let rewind = values["rewindAfterPause"] as? Bool { rewindAfterPause = rewind }
  }

  public var values: [String: Any] {
    [
      "skipBack": skipBack, "skipForward": skipForward, "headphoneNext": headphoneNext.rawValue,
      "markPlayedWhenLeft": markPlayedWhenLeft, "rewindAfterPause": rewindAfterPause,
    ]
  }

  /// What the next button does now. Next episode needs one in Up Next; otherwise it skips.
  public func nextAction(queueHasNext: Bool) -> HeadphoneAction {
    if headphoneNext == .nextEpisode && queueHasNext { return .nextEpisode }
    return .skip(seconds: Double(skipForward))
  }

  /// How far back the previous button goes, in seconds.
  public var previousSeconds: Double { Double(skipBack) }
}

/// Going back a little when playing again after a long pause, so the listener hears again
/// what they were in the middle of.
public enum RewindRule {
  /// A pause of 5 minutes or more rewinds this much...
  public static let shortPause = 300.0
  public static let shortPauseRewind = 3.0
  /// ...and one of an hour or more, this much.
  public static let longPause = 3600.0
  public static let longPauseRewind = 10.0

  /// Seconds to go back for a pause of `pausedFor` seconds. Nothing when the setting is off,
  /// the pause was short or the time is not a number.
  public static func seconds(pausedFor: Double, enabled: Bool) -> Double {
    guard enabled, pausedFor.isFinite else { return 0 }
    if pausedFor >= longPause { return longPauseRewind }
    if pausedFor >= shortPause { return shortPauseRewind }
    return 0
  }
}
