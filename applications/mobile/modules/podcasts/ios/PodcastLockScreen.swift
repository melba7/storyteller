// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The lock screen and headphone buttons for the podcast player: the Now Playing card and who
// answers the remote commands. The book registers its own handlers once at launch and asks
// LofiRemoteHandoff first, so while a podcast owns the lock screen its commands come here.
// When the book plays again it gets the card, the buttons and its skip intervals back.

import Foundation
import MediaPlayer
import PodcastPlayback
import Readium
import UIKit

@MainActor
final class PodcastLockScreen {
  /// The book's skip intervals (see AudiobookPlayerActor.init), put back when it plays.
  private static let bookForward: [NSNumber] = [30]
  private static let bookBack: [NSNumber] = [15]

  private(set) var owner = RemoteOwner()
  /// Handles a command from the lock screen or the headphones.
  var onCommand: (@MainActor (LofiRemoteCommand) -> Void)?

  private var savedBookInfo: [String: Any]?
  private var title = ""
  private var showTitle = ""
  private var artwork: MPMediaItemArtwork?
  private var artworkTask: Task<Void, Never>?

  /// A new episode: its card text, and its picture once that has downloaded.
  func setEpisode(title: String, showTitle: String, artworkUrl: String?) {
    self.title = title
    self.showTitle = showTitle
    artwork = nil
    artworkTask?.cancel()
    guard let artworkUrl, let url = URL(string: artworkUrl) else { return }
    artworkTask = Task { [weak self] in
      guard let image = await ArtworkLoader.image(url), !Task.isCancelled else { return }
      let artwork = Self.makeArtwork(image)
      self?.artwork = artwork
      if let self, self.owner.current == .podcast { self.refreshArtwork() }
    }
  }

  /// A podcast started playing: it owns the buttons and the card until the book plays.
  func podcastStartedPlaying() {
    guard owner.current != .podcast else { return }
    // Keep the book's card (once), so it can come back.
    if savedBookInfo == nil { savedBookInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo }
    owner.podcastStartedPlaying()
    LofiRemoteHandoff.shared.setPodcastHandler { [weak self] command in
      Task { @MainActor in self?.onCommand?(command) }
      return .success
    }
    refreshSkipIntervals()
  }

  /// The skip buttons use the amounts from the listener's playback settings.
  func refreshSkipIntervals() {
    guard owner.current == .podcast else { return }
    let settings = PlaybackSettingsStore.current
    let commands = MPRemoteCommandCenter.shared()
    commands.skipForwardCommand.preferredIntervals = [NSNumber(value: settings.skipForward)]
    commands.skipBackwardCommand.preferredIntervals = [NSNumber(value: settings.skipBack)]
  }

  /// The book started playing: it gets the card, the buttons and its intervals back.
  func bookStartedPlaying() {
    owner.bookStartedPlaying()
    LofiRemoteHandoff.shared.clearPodcastHandler()
    let commands = MPRemoteCommandCenter.shared()
    commands.skipForwardCommand.preferredIntervals = Self.bookForward
    commands.skipBackwardCommand.preferredIntervals = Self.bookBack
    // Put the book's card back only while the card is still ours. If the book has already
    // written its own, leave it.
    let current = MPNowPlayingInfoCenter.default().nowPlayingInfo
    let stillOurs =
      current?[MPMediaItemPropertyTitle] as? String == title
      && current?[MPMediaItemPropertyArtist] as? String == showTitle
    if let saved = savedBookInfo, stillOurs {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = saved
    }
    savedBookInfo = nil
  }

  /// Writes the card while the podcast owns it: elapsed time and rate follow play, pause,
  /// seeks and speed changes.
  func update(position: Double, duration: Double?, rate: Double, isPlaying: Bool) {
    guard owner.current == .podcast else { return }
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: title,
      MPMediaItemPropertyArtist: showTitle,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0.0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: rate,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
    ]
    if let duration, duration.isFinite, duration > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = duration
    }
    if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  /// Built outside the main actor: iOS calls the request handler on another thread, and a
  /// main-actor handler would crash there.
  nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
    MPMediaItemArtwork(boundsSize: image.size) { _ in image }
  }

  private func refreshArtwork() {
    guard let artwork else { return }
    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    info[MPMediaItemPropertyArtwork] = artwork
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }
}

/// Downloads a picture for the lock screen or for working out its colour.
enum ArtworkLoader {
  /// The most a picture may weigh. Real cover art is well under this.
  static let maxBytes = 15 * 1024 * 1024

  static func data(_ url: URL) async -> Data? {
    guard url.scheme == "http" || url.scheme == "https" else { return nil }
    var request = URLRequest(url: url.upgradedToHTTPS)
    request.timeoutInterval = 20
    guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
    return data.count <= maxBytes ? data : nil
  }

  static func image(_ url: URL) async -> UIImage? {
    guard let data = await data(url) else { return nil }
    return UIImage(data: data)
  }
}
