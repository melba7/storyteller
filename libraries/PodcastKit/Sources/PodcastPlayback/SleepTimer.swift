// LOFI-FORK: the podcast player's rules (see FORK.md). Plain values, no AVFoundation.
import Foundation

/// A sleep timer: a countdown of minutes, or "until the end of this episode". The caller
/// passes the time (seconds on any steady clock, such as Date's), so the rules test without
/// waiting.
public struct SleepTimer: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case countdown
    case endOfEpisode
  }

  /// The choices the player offers, in minutes.
  public static let presetMinutes = [5, 10, 15, 30, 45, 60]
  /// The most a listener's own time may be (12 hours).
  public static let longestMinutes = 720
  /// The volume falls to nothing over this many seconds before the countdown ends.
  public static let fadeSeconds = 10.0
  /// What "Add 5 minutes" adds.
  public static let extraSeconds = 300.0

  public let kind: Kind
  /// When a countdown ends. Zero for the end-of-episode timer, which has no clock.
  public let endsAt: Double

  private init(kind: Kind, endsAt: Double) {
    self.kind = kind
    self.endsAt = endsAt
  }

  /// A countdown of this many minutes from `now`. Nil for zero or fewer, or no number; a
  /// longer time than 12 hours is cut to 12 hours.
  public static func countdown(minutes: Double, from now: Double) -> SleepTimer? {
    guard minutes.isFinite, minutes >= 1.0 / 60, now.isFinite else { return nil }
    let seconds = min(minutes, Double(longestMinutes)) * 60
    return SleepTimer(kind: .countdown, endsAt: now + seconds)
  }

  /// Stops at the end of the episode that is playing.
  public static let endOfEpisode = SleepTimer(kind: .endOfEpisode, endsAt: 0)

  /// Seconds left on a countdown, never below zero. Nil for the end-of-episode timer.
  public func remaining(at now: Double) -> Double? {
    guard kind == .countdown else { return nil }
    return max(0, endsAt - now)
  }

  /// Whether a countdown has run out.
  public func isFinished(at now: Double) -> Bool {
    (remaining(at: now) ?? 1) <= 0
  }

  /// Five more minutes on a countdown (counted from now if it has just run out). The
  /// end-of-episode timer has no clock, so it stays as it is.
  public func extended(at now: Double) -> SleepTimer {
    guard kind == .countdown else { return self }
    return SleepTimer(
      kind: .countdown, endsAt: max(endsAt, now) + Self.extraSeconds)
  }

  /// The player's volume now, 1 until the last 10 seconds and then falling in a straight
  /// line to 0. Always 1 for the end-of-episode timer.
  public func volume(at now: Double) -> Double {
    guard let left = remaining(at: now) else { return 1 }
    return min(1, left / Self.fadeSeconds)
  }

  /// When the episode ends and the queue has more: a timer set for the end of the episode
  /// means stop here rather than go on to the next one.
  public var stopsBeforeNextEpisode: Bool { kind == .endOfEpisode }

  /// A listener's own time, from what was typed: whole minutes from 1 to 720. Nil when it is
  /// not a number in that range.
  public static func customMinutes(_ text: String) -> Int? {
    guard let minutes = Int(text.trimmingCharacters(in: .whitespaces)),
      (1...longestMinutes).contains(minutes)
    else { return nil }
    return minutes
  }
}
