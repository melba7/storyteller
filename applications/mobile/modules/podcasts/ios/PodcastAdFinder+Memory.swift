// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The ad finder and the memory of ads (PodcastKnownAds): the sure ads of a finished episode are
// learned, and the ads the memory knows in an episode's transcript so far are added to what the
// model found. Both run in the finder's own background task, never on the main thread.
import Foundation
import PodcastAds
import PodcastTranscripts

extension PodcastAdFinder {
  /// A final ads file was saved: its sure ads are remembered by their words, for the show.
  func learnRemembered(
    _ id: String, ads: AdsStore, finished file: AdsFile, transcript: Transcript
  ) {
    guard let show = EpisodeShows.shared.show(for: id) else { return }
    // The saved file also holds the skips the listener took back or trimmed meanwhile.
    let saved = ads.load(detector: Self.detectorName) ?? file
    PodcastKnownAds.shared.learn(file: saved, transcript: transcript, show: show)
  }

  /// The ads the memory finds whole in `words` are added to the episode's partial ads file, next
  /// to what the model found. One that the listener undid is left out.
  func addRemembered(_ id: String, ads: AdsStore, words: [TranscriptWord]) {
    guard let show = EpisodeShows.shared.show(for: id),
      var file = ads.loadPartial(detector: Self.detectorName)
    else { return }
    let use = KnownAdUse.from(PodcastKnownAds.shared.find(in: words, show: show), words: words)
    let whole = use.ads.filter { ad in !use.provisional.contains(ad) && !file.isUndone(ad) }
    guard !whole.isEmpty else { return }
    let merged = AdHeadRules.merge(file.ads + whole)
    guard merged != file.ads else { return }
    file.ads = merged
    try? ads.savePartial(file)
  }
}
