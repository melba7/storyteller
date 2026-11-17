// LOFI-FORK: the podcast player's rules (see FORK.md). Plain values, no AVFoundation.
import Foundation

/// A sleep timer: a countdown of minutes, or "until the end of this episode". The caller
/// passes the time (seconds on any steady clock, such as Date's), so the rules test without
/// waiting.
public struct SleepTimer: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case countdown
    case endOfEpisode
    /// Stops where the chapter playing now ends (`endsAt` is that place in the episode).
    case endOfChapter
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
  /// When a countdown ends, in clock seconds. For the end-of-chapter timer it is instead the
  /// place in the episode (seconds) where the chapter ends. Zero for the end-of-episode timer.
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

  /// Stops at `end`, the second of the episode where the chapter that is playing ends. Nil
  /// for a place that is not a time.
  public static func endOfChapter(endingAt end: Double) -> SleepTimer? {
    guard end.isFinite, end > 0 else { return nil }
    return SleepTimer(kind: .endOfChapter, endsAt: end)
  }

  public enum ChapterStatus: Equatable, Sendable {
    /// Not at the end yet (or this is not a chapter timer).
    case waiting
    /// At the end of the chapter: pause now.
    case reached
    /// The listener went well past the end; the timer is out of date.
    case passed
  }

  /// How close to the end of the chapter the player pauses. The player checks about twice a
  /// second, so it stops a little early rather than late into the next chapter.
  public static let chapterEndSlack = 0.5
  /// Further than this past the end means the listener moved on, not that the chapter ended.
  public static let chapterPassedBy = 3.0

  /// Where playback is compared with the end of the chapter, for an end-of-chapter timer.
  public func chapterStatus(at position: Double) -> ChapterStatus {
    guard kind == .endOfChapter, position.isFinite else { return .waiting }
    if position > endsAt + Self.chapterPassedBy { return .passed }
    return position >= endsAt - Self.chapterEndSlack ? .reached : .waiting
  }

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
  public var stopsBeforeNextEpisode: Bool { kind == .endOfEpisode || kind == .endOfChapter }

  /// A listener's own time, from what was typed: whole minutes from 1 to 720. Nil when it is
  /// not a number in that range.
  public static func customMinutes(_ text: String) -> Int? {
    guard let minutes = Int(text.trimmingCharacters(in: .whitespaces)),
      (1...longestMinutes).contains(minutes)
    else { return nil }
    return minutes
  }
}
