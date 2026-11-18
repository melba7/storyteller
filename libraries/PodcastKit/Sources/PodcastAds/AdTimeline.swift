// LOFI-FORK: when each ad became known, against where a listener would be (see FORK.md).
import Foundation

/// What was known about the ads at one moment of the processing.
public struct AdSnapshot: Sendable, Equatable {
  /// Seconds of processing since the listener pressed play.
  public var elapsed: Double
  public var ads: [FoundAd]

  public init(elapsed: Double, ads: [FoundAd]) {
    self.elapsed = elapsed
    self.ads = ads
  }
}

/// One ad of the final result and whether the player would have skipped it.
public struct AdVerdict: Sendable, Equatable {
  public var ad: FoundAd
  /// The processing time after which the ad was first known.
  public var knownAt: Double
  /// The time since pressing play at which the playhead reaches the ad's start, counting the
  /// ads skipped before it.
  public var reachedAt: Double
  /// Whether the ad was known before the playhead reached it.
  public var skipped: Bool

  /// How many seconds before the playhead got there the ad was known (negative when late).
  public var lead: Double { reachedAt - knownAt }
}

/// Plain rules that say whether ad skipping keeps ahead of a listener who plays from the start.
public enum AdTimeline {
  /// The verdict for each ad of the last snapshot that the player would skip (sure and
  /// unsure ones), for a listener who pressed play at 0:00 at `rate` times normal speed, with
  /// the processing starting at the same moment.
  ///
  /// An ad counts as known at the first snapshot that has an ad overlapping it. The playhead
  /// moves at `rate`, and each ad that was known in time is jumped over, so the later ads are
  /// reached sooner.
  public static func verdicts(snapshots: [AdSnapshot], rate: Double = 1) -> [AdVerdict] {
    guard let final = snapshots.last else { return [] }
    let speed = rate.isFinite && rate > 0 ? rate : 1
    var skippedLength = 0.0
    var result: [AdVerdict] = []
    for ad in final.ads.filter({ $0.confidence >= .unsure && $0.end > $0.start }).sorted(by: {
      $0.start < $1.start
    }) {
      let knownAt =
        snapshots.first { snapshot in
          snapshot.ads.contains { $0.start < ad.end && ad.start < $0.end }
        }?.elapsed ?? final.elapsed
      let reachedAt = max(0, ad.start - skippedLength) / speed
      let skipped = knownAt <= reachedAt
      if skipped { skippedLength += ad.duration }
      result.append(AdVerdict(ad: ad, knownAt: knownAt, reachedAt: reachedAt, skipped: skipped))
    }
    return result
  }

  /// How many seconds of audio are processed in one second: above 1, processing is faster than
  /// listening.
  public static func speed(audioSeconds: Double, processingSeconds: Double) -> Double {
    processingSeconds > 0 ? audioSeconds / processingSeconds : 0
  }
}
