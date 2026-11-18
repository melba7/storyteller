// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// What the head scan tells the rest of the app about the start of a stream: the first look is
// done (the player's short wait for it can end, PodcastPlayer+StartHold.swift), possibly because
// the show's own opening words were heard, the scan is over, and whether the show's episodes
// start with an ad (PodcastShowStarts).
import Foundation
import PodcastAds

extension PodcastStreamHead {
  /// The 15 second step's rules and the memory of ads are done and saved: Play may go on.
  func reportVerdict() {
    let id = episodeId
    Task { @MainActor in PodcastPlayer.shared.startHoldVerdict(id) }
  }

  /// The first look is done and it heard the words the show opens with (PodcastStreamHead+Opening):
  /// the show has begun. The ads it found are saved, so Play may go on.
  func reportShowBegan() {
    let id = episodeId
    Task { @MainActor in PodcastPlayer.shared.startHoldShowBegan(id) }
  }

  /// The scan is over, whatever the reason (finished, failed, stopped): Play must not wait for it.
  /// What it found says whether the show's episodes start with an ad.
  func reportScanEnded(ads: [FoundAd], reached: Double) {
    if let show = EpisodeShows.shared.show(for: episodeId) {
      PodcastShowStarts.shared.record(show: show, ads: ads, reached: reached)
    }
    let id = episodeId
    Task { @MainActor in PodcastPlayer.shared.startHoldScanEnded(id) }
  }
}
