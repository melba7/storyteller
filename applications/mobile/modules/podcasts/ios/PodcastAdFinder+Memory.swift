// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The ad finder and the memory of ads (PodcastKnownAds): the ads the memory knows in an episode's
// transcript so far are added to what the model found. It runs in the finder's own background
// task, never on the main thread. What a finished episode teaches the memory is learned in
// PodcastAdFinder+Learn.swift.
import Foundation
import PodcastAds
import PodcastTranscripts

extension PodcastAdFinder {
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
