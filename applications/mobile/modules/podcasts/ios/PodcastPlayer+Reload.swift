// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Play on an episode that failed. An AVPlayerItem that failed no longer plays (Apple's words), so
// pressing Play on it did nothing: the listener had to pick another episode and come back. Now
// Play loads the same episode again at the last good place (PodcastPlayback's PlayRecovery
// keeps it). Only a press of Play does this, never the player by itself, so a source that keeps
// failing shows its error once for every press and nothing else.

import Foundation
import PodcastPlayback

@MainActor
extension PodcastPlayer {
  /// Play was pressed. When the loaded item has failed, loads the episode again from its
  /// download or its address, at the last good place, and starts it. Returns whether it did.
  /// Up Next is not touched, because this goes through `begin` and not `load`.
  func reloadIfFailed() -> Bool {
    guard let reloadPlace = recovery.reloadPlace, let item = current,
      let source = QueueSource.url(
        for: item, localFile: PodcastDownloader.shared.localFile(for: item.id))
    else { return false }
    begin(
      Episode(
        id: item.id, url: source, title: item.title, showTitle: item.showTitle,
        artworkUrl: item.artworkUrl, savedPosition: reloadPlace, duration: item.duration,
        played: false, autoplay: true, type: item.type, showId: item.showId,
        chaptersUrl: item.chaptersUrl,
        // As the app asks when the listener plays an episode (see startNextInQueue).
        playThroughDownload: skipAds(forShow: item.showId), language: item.language,
        notes: item.notes, showLink: item.showLink, queueURL: item.url))
    return true
  }
}
