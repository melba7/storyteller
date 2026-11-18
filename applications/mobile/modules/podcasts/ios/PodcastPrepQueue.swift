// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Picks the next piece of work for the transcriber and the ad finder alike. The rule itself is
// PodcastAds' PrepOrder (tested on Linux); this reads what it needs: when each download was
// filed, and the Up Next list.

import Foundation
import PodcastAds
import PodcastDownloads
import PodcastPlayback

enum PrepQueue {
  /// The next piece of work for the episodes in `rests` (their rest still to do) and `heads`
  /// (their head still to do): every waiting episode's head comes before any episode's rest,
  /// except the one loaded in the player, which goes first with its head and then its rest. Within
  /// each, Up Next in its order, then the newest downloads. Nil when nothing waits.
  static func nextStep(heads: Set<String>, rests: [String], playing: String?) -> PrepStep? {
    let ids = rests + heads.filter { !rests.contains($0) }
    guard !ids.isEmpty else { return nil }
    var added: [String: Date] = [:]
    for entry in PodcastDownloader.shared.store?.entries() ?? [] { added[entry.episodeId] = entry.updatedAt }
    let works = ids.map {
      PrepWork(
        id: $0, addedAt: added[$0] ?? .distantPast, headPending: heads.contains($0),
        restPending: rests.contains($0))
    }
    let upNext = UpNextQueue.load(from: UpNextFile.url).items.map(\.id)
    return PrepOrder.nextStep(works, playing: playing, upNext: upNext)
  }
}
