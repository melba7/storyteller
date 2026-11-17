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
    let store = PodcastDownloader.shared.store
    let hasDownload = store?.entry(for: episode.id)?.state.isActive ?? false
    guard
      StreamThroughDownload.shouldUse(
        asked: episode.playThroughDownload, episodeId: episode.id, hasDownload: hasDownload,
        wifiOnly: DownloadSettings.wifiOnly, onWiFi: PodcastNetwork.shared.onWiFi),
      let loader = PodcastStreamDownload(
        episodeId: episode.id, url: episode.url, type: episode.type)
    else { return AVPlayerItem(url: episode.url) }
    // The language is noted before the download can finish, as when a download is asked for.
    PodcastTranscriber.shared.noteLanguage(episode.language, for: episode.id)
    streamDownload = loader
    loader.start()
    return AVPlayerItem(asset: loader.makeAsset())
  }
}
