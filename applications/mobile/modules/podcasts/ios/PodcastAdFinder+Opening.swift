// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// A final ads file was saved: the words the show opens with are learned from the episode's first
// five minutes outside its ads (PodcastShowOpenings). It runs in the finder's own background
// task, never on the main thread.
import Foundation
import PodcastAds
import PodcastTranscripts

extension PodcastAdFinder {
  /// Learns the show's opening words from a finished episode. The ads file on disk is read, as it
  /// also holds the skips the listener took back.
  func learnOpening(
    _ id: String, ads: AdsStore, finished file: AdsFile, transcript: Transcript
  ) {
    guard let show = EpisodeShows.shared.show(for: id) else { return }
    let saved = ads.load(detector: Self.detectorName) ?? file
    PodcastShowOpenings.shared.learn(file: saved, transcript: transcript, show: show, episode: id)
  }
}
