// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Which source an episode plays from: its downloaded file, its own download as it arrives
// (PodcastStreamDownload, so ads can be found in the exact file that is heard), or its address.
import AVFoundation
import Foundation
import PodcastDownloads

extension PodcastPlayer {
  /// The item for an episode that is about to play. The download of the episode that played
  /// before is dropped first, if it was not whole.
  func makeItem(for episode: Episode) -> AVPlayerItem {
    streamDownload?.stop()
    streamDownload = nil
    if let file = PodcastDownloader.shared.localFile(for: episode.id) {
      return AVPlayerItem(url: file)
    }
    let entry = PodcastDownloader.shared.store?.entry(for: episode.id)
    // A new episode's automatic download that is still waiting for Wi-Fi has nothing to play,
    // so it does not keep the listener from a download of their own.
    let waiting = entry.map(StreamThroughDownload.isWaitingAutomatic) ?? false
    let hasDownload = (entry?.state.isActive ?? false) && !waiting
    guard
      StreamThroughDownload.shouldUse(
        asked: episode.playThroughDownload, episodeId: episode.id, hasDownload: hasDownload,
        wifiOnly: DownloadSettings.wifiOnly, onWiFi: PodcastNetwork.shared.onWiFi),
      let loader = PodcastStreamDownload(
        episodeId: episode.id, url: episode.url, type: episode.type)
    else { return AVPlayerItem(url: episode.url) }
    if waiting { try? PodcastDownloader.shared.cancel(episodeId: episode.id) }
    // The language is noted before the download can finish, as when a download is asked for.
    PodcastTranscriber.shared.noteLanguage(episode.language, for: episode.id)
    loader.onFallback = { [weak self, weak loader] reason in
      Task { @MainActor in
        guard let self, let loader else { return }
        self.fallBackToStream(from: loader, reason: reason)
      }
    }
    streamDownload = loader
    loader.start()
    return AVPlayerItem(asset: loader.makeAsset())
  }

  /// Playing from the download does not work (the server refused it or sends no length, or the
  /// listener removed it): the same place plays from the episode's plain address instead.
  func fallBackToStream(from loader: PodcastStreamDownload, reason: StreamFallback) {
    guard streamDownload === loader else { return }
    // A seek to the saved place may not have happened yet on an item that never became ready.
    let ready = player.currentItem?.status == .readyToPlay
    let place = ready ? position : max(position, itemStart)
    loader.stop()
    streamDownload = nil
    if reason == .noLength, let type = current?.type {
      // The ad finder still needs the file; an ordinary download handles any length.
      try? PodcastDownloader.shared.download(
        episodeId: loader.episodeId, url: loader.originalURL.absoluteString, type: type,
        automatic: false)
    }
    let item = AVPlayerItem(url: loader.originalURL)
    item.audioTimePitchAlgorithm = .timeDomain
    removeItemObservers()
    player.replaceCurrentItem(with: item)
    watch(item)
    if place > 0 {
      player.seek(
        to: CMTime(seconds: place, preferredTimescale: 600), toleranceBefore: .zero,
        toleranceAfter: .zero)
    }
    if wantsToPlay { player.play() }
    sound.refresh()
    publish()
  }
}
