// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// What a stream's head scan does with the words its show opens with (PodcastShowOpenings): after
// each step the words so far are looked at for them, next to the memory of ads. Where they start
// the show has begun, so an ad that holds 0:00 ends just before them (or goes, when it is
// unsure), and the player's short wait for the first look can end. The opening only ever
// shortens an ad or drops an unsure one (ShowOpening).
import Foundation
import PodcastAds
import PodcastTranscripts

final class HeadOpening: @unchecked Sendable {
  private let lock = NSLock()
  /// Where the show's opening starts in the head, once it is found.
  private var at: Double?

  /// Looks for the show's opening in `words` and notes where it starts. True when it is found.
  /// Nothing is found for an episode whose show is not known, or a show with no opening.
  func look(in words: [TranscriptWord], episodeId: String) -> Bool {
    guard let show = EpisodeShows.shared.show(for: episodeId),
      let opening = PodcastShowOpenings.shared.opening(show: show)
    else { return false }
    let found = ShowOpening.find(opening, in: words)
    let changed = lock.withLock { () -> Bool in
      defer { at = found }
      return at != found
    }
    if changed, let found {
      let seconds = String(format: "%.1f", found)
      PodcastTimeline.mark(episodeId, "opening: the show begins at \(seconds) s")
    }
    return found != nil
  }

  /// `ads` with the opening's effect, when it was found: an ad that holds 0:00 ends before it.
  func shorten(_ ads: [FoundAd]) -> [FoundAd] {
    guard let opening = lock.withLock({ at }) else { return ads }
    return ShowOpening.shorten(ads, openingAt: opening)
  }
}
