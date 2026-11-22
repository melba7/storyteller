// LOFI-FORK: a short wait before a never-checked stream starts (see FORK.md).
//
// A stream that nothing is known about starts playing at once, so the listener is already in
// an ad when the head scan finds it. For an episode that plays through its own download, starts
// at 0:00, was never checked and is of a show that is not known to start clean, Play waits a
// moment for the first look (the 15 second step's rules and the memory of ads), so an ad that
// holds 0:00 is left before it is heard. The wait never lasts past `longest` (3 seconds), or
// `longestForAdOpeners` (5 seconds) for a show that usually opens with an ad. Foundation only.
import Foundation

public struct StartHold: Equatable, Sendable {
  /// The wait never lasts longer than this many seconds from the tap.
  public static let longest = 3.0
  /// A show that usually opens with an ad is waited for a little longer.
  public static let longestForAdOpeners = 5.0

  /// The longest wait for a show, by whether it usually opens with an ad.
  public static func longest(usuallyOpensWithAd: Bool) -> Double {
    usuallyOpensWithAd ? longestForAdOpeners : longest
  }
  /// An episode that starts later than this many seconds is not waited for (it resumes).
  public static let startsUnder = 1.0

  /// Why the wait is over.
  public enum Release: Equatable, Sendable {
    /// The first step's rules and the memory of ads have answered.
    case verdict
    /// The head scan heard the show's own opening words (`ShowOpening`): the show has begun, so
    /// whatever is before them was the pre-roll, and the first look has seen it.
    case showBegan
    /// The head scan ended (also when it failed) before it answered.
    case scanEnded
    /// `longest` seconds went by.
    case timeout
    /// The listener tapped Play again.
    case secondTap
  }

  /// Whether Play should wait: Skip ads is on, the episode plays through its own download (a
  /// stream that is saved as it plays), it starts under a second, nothing is saved for it yet,
  /// the show is not known to start clean, and the app is in front. With the screen locked or the
  /// app away, iOS may suspend the app before the timer fires, and the episode would stay silent
  /// until the app is opened: then it starts at once, whatever the ad scan says.
  public static func wanted(
    skipAds: Bool, playsOwnDownload: Bool, startsAt: Double, hasSavedAds: Bool,
    showStartsClean: Bool, appActive: Bool
  ) -> Bool {
    skipAds && playsOwnDownload && startsAt < startsUnder && !hasSavedAds && !showStartsClean
      && appActive
  }

  /// Why the wait is over, nil while it goes on. Once set it never changes: the first reason
  /// wins and the others are ignored.
  public private(set) var released: Release?

  public init() {}

  public mutating func verdict() -> Release? { release(.verdict) }
  public mutating func showBegan() -> Release? { release(.showBegan) }
  public mutating func scanEnded() -> Release? { release(.scanEnded) }
  public mutating func tappedAgain() -> Release? { release(.secondTap) }

  /// `elapsed` seconds have gone by since the tap. The wait ends at `longest` seconds, which is
  /// longer for a show that usually opens with an ad (`longest(usuallyOpensWithAd:)`).
  public mutating func tick(elapsed: Double, longest: Double = StartHold.longest) -> Release? {
    elapsed >= longest ? release(.timeout) : nil
  }

  /// The reason, when this is the one that ended the wait.
  private mutating func release(_ reason: Release) -> Release? {
    guard released == nil else { return nil }
    released = reason
    return reason
  }
}
