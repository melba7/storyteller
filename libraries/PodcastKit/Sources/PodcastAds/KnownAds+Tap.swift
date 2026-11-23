// LOFI-FORK: remembering the one stretch a listener confirmed (see FORK.md). Foundation only.
import Foundation
import PodcastTranscripts

extension KnownAds {
  /// Remembers the one stretch the listener said "yes" to when the phone asked, with its words
  /// in `transcript`. Nothing else is counted: `learn(from:)` on the whole file would count every
  /// other sure ad of the episode a second time, because the file's ads were already learned
  /// when it was finished. A confirmed stretch is sure by the listener's word, whatever the
  /// question's own confidence was, and the memory's usual limits for what it keeps still apply
  /// (15 to 120 seconds, at least 25 words). Words that are already remembered for the show are
  /// one entry that was seen once more, so call this once for each answer. True when the
  /// memory changed and should be saved.
  @discardableResult
  public mutating func learnTapped(
    _ ad: FoundAd, transcript: Transcript, show: String, now: Date
  ) -> Bool {
    var confirmed = ad
    confirmed.confidence = .sure
    let one = AdsFile(
      sha256: transcript.identity.sha256, detector: AdAsking.source, detectorVersion: "",
      osVersion: "", duration: transcript.duration, ads: [confirmed])
    let before = ads
    learn(from: one, transcript: transcript, show: show, now: now)
    return ads != before
  }
}
