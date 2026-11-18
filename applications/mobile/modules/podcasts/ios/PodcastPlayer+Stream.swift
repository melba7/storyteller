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
    playsPlainAddress = false
    if let file = PodcastDownloader.shared.localFile(for: episode.id) {
      return AVPlayerItem(url: file)
    }
    let entry = PodcastDownloader.shared.store?.entry(for: episode.id)
    // A new episode's automatic download that is still waiting for Wi-Fi has nothing to play,
    // so it does not keep the listener from a download of their own.
    let waiting = entry.map(StreamThroughDownload.isWaitingAutomatic) ?? false
    // A play-through entry nobody is feeding is left over from a run that was stopped; the new
    // loader replaces it.
    let stale = (entry?.playThrough ?? false) && !PodcastDownloader.shared.isPlayThrough(episode.id)
    let hasDownload = (entry?.state.isActive ?? false) && !waiting && !stale
    guard
      StreamThroughDownload.shouldUse(
        asked: episode.playThroughDownload, episodeId: episode.id, hasDownload: hasDownload,
        wifiOnly: DownloadSettings.wifiOnly, onWiFi: PodcastNetwork.shared.onWiFi),
      let loader = PodcastStreamDownload(
        episodeId: episode.id, url: episode.url, type: episode.type)
    else {
      playsPlainAddress = true
      return AVPlayerItem(url: episode.url)
    }
    if waiting { try? PodcastDownloader.shared.cancel(episodeId: episode.id) }
    // The language is noted before the download can finish, as when a download is asked for.
    PodcastTranscriber.shared.noteLanguage(episode.language, for: episode.id)
    loader.onFallback = { [weak self, weak loader] reason in
      Task { @MainActor in
        guard let self, let loader else { return }
        self.fallBackToStream(from: loader, reason: reason)
      }
    }
    loader.head.setLanguage(episode.language)
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
    // The old item is let go first, so its requests failing in stop() never reach the player.
    removeItemObservers()
    loader.stop()
    streamDownload = nil
    playsPlainAddress = true
    if reason == .noLength, let type = current?.type {
      // The ad finder still needs the file; an ordinary download handles any length. stop()
      // forgot the show's language, so it is noted again for the transcriber.
      PodcastTranscriber.shared.noteLanguage(current?.language, for: loader.episodeId)
      try? PodcastDownloader.shared.download(
        episodeId: loader.episodeId, url: loader.originalURL.absoluteString, type: type,
        automatic: false)
    }
    let item = AVPlayerItem(url: loader.originalURL)
    item.audioTimePitchAlgorithm = .timeDomain
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
