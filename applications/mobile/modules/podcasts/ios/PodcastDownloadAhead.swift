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
  /// Every episode started ahead since the app was opened. One in it is not started again until
  /// the app is opened anew, so a file the listener deleted, or one taken back and then queued
  /// again, is not fetched over and over (50 to 100 MB each time).
  private var started = Set<String>()

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

  /// An episode starts to play or load: it is the listener's from here on, so its download (if it
  /// was fetched ahead) is no longer marked and is never dropped for leaving Up Next. The player
  /// calls this the moment it begins an episode, because the look below waits a few seconds, and
  /// an episode paused and put aside, or the app closed, within them would lose its file.
  func handOver(_ episodeId: String) {
    do { try PodcastDownloader.shared.store?.clearAhead(episodeId: episodeId) } catch {
      NSLog("Podcasts: an ahead download could not be handed over to the listener: \(error)")
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
      playingId: player.current?.id, entries: store.entries(), started: started,
      onWiFi: PodcastNetwork.shared.onWiFi)

    for id in plan.adopt { handOver(id) }
    for id in plan.drop {
      do { try downloader.remove(episodeId: id) } catch {
        NSLog("Podcasts: an ahead download could not be removed: \(error)")
      }
    }
    for id in plan.start {
      guard let item = queued.first(where: { $0.id == id }) else { continue }
      // Noted before the try, so an episode that cannot be fetched is not asked for again.
      started.insert(id)
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
