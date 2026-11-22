// LOFI-FORK: where an episode's ad finding is, and when it runs (see FORK.md).
import Foundation

/// Where one episode's ad finding is, once its transcript is ready.
public enum AdsStatus: Sendable, Equatable {
  case waiting
  case finding(percent: Int)
  case found(count: Int)
  /// Ads found in the part of the transcript made so far. The player already skips them, and
  /// the episode still waits for its full pass.
  case partialFound(count: Int)
  case noneFound
  /// A finished run in which the model refused some pieces, so those were not checked. `count`
  /// is the ads found in the rest, possibly none.
  case partlyChecked(count: Int)
  /// Not now, with the words for the listener ("Apple Intelligence is off").
  case notPossible(reason: String)
}

public enum AdsRules {
  /// The status from what is known about the episode.
  ///
  /// - Parameters:
  ///   - file: the saved result of the detector, if any.
  ///   - partial: the result for the transcript made so far, if any (no use once `file` is there).
  ///   - detectorVersion: the running detector's version; a result of another version is old
  ///     and the episode is checked again.
  ///   - finding: the percent done while a run is going.
  ///   - unavailable: why the model cannot be used now, or nil when it can.
  ///   - failure: why the last run in this launch failed, so it is not retried in a loop.
  public static func status(
    file: AdsFile?, partial: AdsFile? = nil, detectorVersion: String, finding: Int?,
    unavailable: AdUnavailable?, failure: String?
  ) -> AdsStatus {
    if let finding { return .finding(percent: finding) }
    if let file, file.detectorVersion == detectorVersion { return finished(file) }
    // The local finders' own result is the finished one while the model cannot be asked. When it
    // can be asked, that result is old, as any file of another version is.
    if let file, file.detectorVersion == LocalAdsFile.localVersion,
      unavailable != nil || failure != nil
    {
      return finished(file)
    }
    // The ads found so far are said before a failure, since the player skips them anyway. The
    // episode is still not tried again in a loop: `wantsRun(_:failure:)` says so.
    if let partial, partial.detectorVersion == detectorVersion, !partial.ads.isEmpty {
      return .partialFound(count: partial.ads.count)
    }
    if let failure { return .notPossible(reason: failure) }
    if let unavailable { return .notPossible(reason: unavailable.reason) }
    return .waiting
  }

  /// The status of a finished run: how many ads, and whether some pieces were not checked.
  public static func finished(_ file: AdsFile) -> AdsStatus {
    if (file.refusedPieces ?? 0) > 0 { return .partlyChecked(count: file.ads.count) }
    return file.ads.isEmpty ? .noneFound : .found(count: file.ads.count)
  }

  /// Whether the episode is to be queued: a waiting one, or one that has only a partial result.
  public static func wantsRun(_ status: AdsStatus) -> Bool {
    switch status {
    case .waiting, .partialFound: return true
    default: return false
    }
  }

  /// As `wantsRun(_:)`, but an episode whose last run failed is not queued again, whatever its
  /// status shows (a failed run with ads found so far shows them). Its retry clears the failure.
  public static func wantsRun(_ status: AdsStatus, failure: String?) -> Bool {
    failure == nil && wantsRun(status)
  }

  /// Whether a whole transcript is queued only so the local finders make its result: it has no
  /// final file yet, the model cannot be asked, and no run of the model failed (that one waits for
  /// its retry). `wantsRun(_:failure:)` is false for these, since the model has nothing to do.
  public static func wantsLocalRun(
    _ status: AdsStatus, failure: String?, hasFinal: Bool, unavailable: AdUnavailable?
  ) -> Bool {
    guard failure == nil, !hasFinal, unavailable != nil else { return false }
    switch status {
    case .waiting, .partialFound, .notPossible: return true
    default: return false
    }
  }

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
