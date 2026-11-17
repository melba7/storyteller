// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// How the podcast player shares the phone with the book: starting a podcast pauses the book
// and takes the lock screen; the book playing stops the podcast and gives the lock screen back.

import AVFoundation
import Foundation
import PodcastPlayback
import Readium

@MainActor
extension PodcastPlayer {
  /// A podcast is playing: the book stops and the podcast owns the lock screen.
  func takeTheLockScreen() {
    guard lockScreen.owner.current != .podcast else { return }
    Task {
      let book = AudiobookPlayerActor.shared
      if await book.lofiIsPlaying() { await book.lofiPauseForPodcast() }
      // After the book has paused, so its own card updates can't overwrite ours.
      lockScreen.podcastStartedPlaying()
      publish()
    }
  }

  /// Registers once with the book's player: when the book plays, the podcast stops.
  func watchTheBook() {
    guard !watchingBook else { return }
    watchingBook = true
    Task {
      await AudiobookPlayerActor.shared.lofiObserve(
        track: { _ in },
        playing: { isPlaying, _ in
          guard isPlaying else { return }
          Task { @MainActor in PodcastPlayer.shared.bookStartedPlaying() }
        },
        clip: { _ in }
      )
    }
  }

  func bookStartedPlaying() {
    if wantsToPlay || player.timeControlStatus != .paused { pause() }
    lockScreen.bookStartedPlaying()
  }

  func handle(_ command: LofiRemoteCommand) {
    switch command {
    case .play: play()
    case .pause: pause()
    case .togglePlayPause: togglePlayPause()
    case .nextTrack: skip(by: Skip.ahead)
    case .previousTrack: skip(by: -Skip.back)
    case .skipForward(let seconds): skip(by: seconds)
    case .skipBackward(let seconds): skip(by: -seconds)
    case .changePosition(let seconds): seek(to: seconds)
    }
  }
}
