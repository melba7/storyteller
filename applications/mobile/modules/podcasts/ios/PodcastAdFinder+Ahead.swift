// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The "ahead" finder on the phone: the ads the Mac marked in an episode the night before, found
// again in the phone's own transcript by their words (PodcastAds' `AheadAds`). The Mac's file is
// `ahead-ads.json`; which entry is which episode comes from the table the app sends
// (`PodcastTeaching.aheadEntry`). Every decision is in PodcastAds; this file only runs it under the
// finder guard, for a whole transcript here and for the words so far of a stream's head.
import Foundation
import PodcastAds
import PodcastTranscripts

extension PodcastAdFinder {
  /// What the marks of this episode give in a whole transcript, or nil when the episode has no
  /// marks or iOS did not hold the time. `judged` are the stretches the listener undid, said no to
  /// or was asked about: nothing is given over them.
  func aheadFound(
    _ id: String, transcript: Transcript, judged: [(start: Double, end: Double)]
  ) -> AheadFound? {
    guard let entry = PodcastTeaching.shared.aheadEntry(episode: id) else { return nil }
    return PodcastFinderGuard.shared.hold([FinderNames.ahead], episode: id) { _ in
      AheadAds.find(entry, words: transcript.words, judged: judged)
    }
  }
}

extension PodcastStreamHead {
  /// The skips the marks of this episode give in the words heard so far, outside `blockers` (the
  /// ads of the other layers). A stream's head asks no questions, so only the skips count. Empty
  /// when the episode has no marks, the listener skips nothing, the finder is not allowed to skip
  /// here, or iOS did not hold the time.
  func findAhead(words: [TranscriptWord], blockers: [FoundAd]) -> [FoundAd] {
    guard let show = EpisodeShows.shared.show(for: episodeId), !show.isEmpty,
      let entry = PodcastTeaching.shared.aheadEntry(episode: episodeId)
    else { return [] }
    let listener = PodcastAdFinder.listenerSwitches(forShow: show)
    guard listener.skipsAnySort else { return [] }
    let tuning = PodcastTeaching.shared.files.tuning
    let level = ShowTuning.stricter(
      PodcastFinderGuard.shared.mode(finder: FinderNames.ahead, show: show, episode: episodeId),
      tuning.level(forFinder: FinderNames.ahead, show: show))
    guard level == .skip else { return [] }
    let found = PodcastFinderGuard.shared.hold([FinderNames.ahead], episode: episodeId) { _ in
      AheadAds.find(entry, words: words).ads
    }
    let heard = (found ?? []).filter { listener.allows($0.kind) }.map { ad -> FoundAd in
      var one = ad
      one.source = FinderNames.ahead
      one.confidence = min(ad.confidence, .unsure)
      return one
    }
    return tuning.apply(to: NewAds.outside(heard, of: blockers), show: show).skip
  }
}
