// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// How an episode's ad finding is told to the app (the `onAdsChange` event and `listAds`).

import PodcastAds

enum AdsJSON {
  /// What the app receives for an episode's ads.
  static func object(_ id: String, _ status: AdsStatus) -> [String: Any] {
    switch status {
    case .waiting: return ["episodeId": id, "state": "waiting"]
    case .finding(let percent): return ["episodeId": id, "state": "finding", "percent": percent]
    case .found(let count), .partialFound(let count):
      return ["episodeId": id, "state": "found", "count": count]
    case .noneFound: return ["episodeId": id, "state": "noAds"]
    case .notPossible(let reason): return ["episodeId": id, "state": "unavailable", "reason": reason]
    }
  }
}
