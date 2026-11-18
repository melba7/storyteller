// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Picks the next episode for the transcriber and the ad finder alike. The rule itself is
// PodcastAds' PrepOrder (tested on Linux); this reads what it needs: when each download was
// filed, and the Up Next list.

import Foundation
import PodcastAds
import PodcastDownloads
import PodcastPlayback

enum PrepQueue {
  /// The waiting episode to work on next: the one loaded in the player, then Up Next in its
  /// order, then the newest downloads. Nil when nothing waits.
  static func next(waiting: [String], playing: String?) -> String? {
    guard !waiting.isEmpty else { return nil }
    var added: [String: Date] = [:]
    for entry in PodcastDownloader.shared.store?.entries() ?? [] { added[entry.episodeId] = entry.updatedAt }
    let candidates = waiting.map {
      PrepCandidate(id: $0, addedAt: added[$0] ?? .distantPast, state: .needsWork)
    }
    let upNext = UpNextQueue.load(from: UpNextFile.url).items.map(\.id)
    return PrepOrder.next(candidates, playing: playing, upNext: upNext)
  }
}
