// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Downloads the next episodes of Up Next ahead of time, so their first minutes are checked for
// ads before they play and the first ad can be skipped at 0:00. The rules (which episodes, how
// many, what to take back) are PodcastDownloads' DownloadAhead. The download is the same one a
// new episode gets: automatic, so it waits for Wi-Fi, gives way to the play-through when the
// episode is started before it is done, and is deleted after it was played like any other. It
// follows "Skip ads" (the show's own choice, else the listener's); it has no switch of its own.

import Foundation
import PodcastDownloads
import PodcastPlayback

@MainActor
final class PodcastDownloadAhead {
  static let shared = PodcastDownloadAhead()

  /// Up Next must stay as it is this long before it is looked at. A drag or a few quick taps
  /// cause one look, and an episode that has just started has been loaded by then.
  private static let settleSeconds = 3.0

  private var pending: Task<Void, Never>?

  private init() {}

  /// Up Next changed, or an episode started or ended (the player changes Up Next then too).
  func changed() {
    pending?.cancel()
    pending = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(PodcastDownloadAhead.settleSeconds * 1_000_000_000))
      guard !Task.isCancelled else { return }
      self?.look()
    }
  }

  /// Asks the rule what to do now and does it.
  private func look() {
    let player = PodcastPlayer.shared
    let downloader = PodcastDownloader.shared
    guard let store = downloader.store else { return }
    let queued = player.queue.items
    let plan = DownloadAhead.plan(
      upNext: queued.map {
        DownloadAhead.Item(id: $0.id, url: $0.url, skipAds: player.skipAds(forShow: $0.showId))
      },
      playingId: player.current?.id, entries: store.entries(), onWiFi: PodcastNetwork.shared.onWiFi)

    for id in plan.adopt {
      do { try store.clearAhead(episodeId: id) } catch {
        NSLog("Podcasts: an ahead download could not be handed over to the listener: \(error)")
      }
    }
    for id in plan.drop {
      do { try downloader.remove(episodeId: id) } catch {
        NSLog("Podcasts: an ahead download could not be removed: \(error)")
      }
    }
    for id in plan.start {
      guard let item = queued.first(where: { $0.id == id }) else { continue }
      // The language is noted before the download can finish, as when the app asks for one.
      PodcastTranscriber.shared.noteLanguage(item.language, for: id)
      do {
        try downloader.download(
          episodeId: id, url: item.url, type: item.type, automatic: true, ahead: true)
      } catch {
        NSLog("Podcasts: an episode could not be downloaded ahead: \(error)")
      }
    }
  }
}
