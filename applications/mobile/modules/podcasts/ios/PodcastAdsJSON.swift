// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// How an episode's ad finding is told to the app (the `onAdsChange` event and `listAds`).

import PodcastAds

enum AdsJSON {
  /// What the app receives for an episode's ads. `prepared` says the file is the Mac's prepared
  /// one, which the app shows as "Prepared by your Mac".
  static func object(_ id: String, _ status: AdsStatus, prepared: Bool = false) -> [String: Any] {
    var object = fields(id, status)
    if prepared { object["prepared"] = true }
    return object
  }

  private static func fields(_ id: String, _ status: AdsStatus) -> [String: Any] {
    switch status {
    case .waiting: return ["episodeId": id, "state": "waiting"]
    case .finding(let percent): return ["episodeId": id, "state": "finding", "percent": percent]
    case .found(let count), .partialFound(let count):
      return ["episodeId": id, "state": "found", "count": count]
    case .partlyChecked(let count):
      // The model refused some pieces: the app says so next to the count (or "no ads").
      return ["episodeId": id, "state": count > 0 ? "found" : "noAds", "count": count, "unchecked": true]
    case .noneFound: return ["episodeId": id, "state": "noAds"]
    case .notPossible(let reason): return ["episodeId": id, "state": "unavailable", "reason": reason]
    }
  }
}
