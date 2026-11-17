// LOFI-FORK: where an episode's ad finding is, and when it runs (see FORK.md).
import Foundation

/// Where one episode's ad finding is, once its transcript is ready.
public enum AdsStatus: Sendable, Equatable {
  case waiting
  case finding(percent: Int)
  case found(count: Int)
  case noneFound
  /// Not now, with the words for the listener ("Apple Intelligence is off").
  case notPossible(reason: String)
}

public enum AdsRules {
  /// The status from what is known about the episode.
  ///
  /// - Parameters:
  ///   - file: the saved result of the detector, if any.
  ///   - detectorVersion: the running detector's version; a result of another version is old
  ///     and the episode is checked again.
  ///   - finding: the percent done while a run is going.
  ///   - unavailable: why the model cannot be used now, or nil when it can.
  ///   - failure: why the last run in this launch failed, so it is not retried in a loop.
  public static func status(
    file: AdsFile?, detectorVersion: String, finding: Int?, unavailable: AdUnavailable?,
    failure: String?
  ) -> AdsStatus {
    if let finding { return .finding(percent: finding) }
    if let file, file.detectorVersion == detectorVersion {
      return file.ads.isEmpty ? .noneFound : .found(count: file.ads.count)
    }
    if let failure { return .notPossible(reason: failure) }
    if let unavailable { return .notPossible(reason: unavailable.reason) }
    return .waiting
  }

  /// Whether the episode is to be queued: only a waiting one is.
  public static func wantsRun(_ status: AdsStatus) -> Bool { status == .waiting }

  /// Whether the work may go on now: the app is on the screen, a podcast is playing (iOS keeps
  /// the app running), or iOS gave a background turn.
  public static func mayRun(appActive: Bool, playing: Bool, inBackgroundTask: Bool) -> Bool {
    appActive || playing || inBackgroundTask
  }

  /// Whether to look again later by itself: the model is downloading, which passes. An
  /// Apple Intelligence that is off, or a phone that cannot run it, does not.
  public static func looksAgainLater(_ unavailable: AdUnavailable?) -> Bool {
    unavailable?.passesByItself ?? false
  }

  /// How much of the pieces are done, 0 to 100.
  public static func percent(done: Int, total: Int) -> Int {
    guard total > 0, done > 0 else { return 0 }
    return min(100, done * 100 / total)
  }
}
