// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// What Apple's on-device model may do on an episode's show. It asks by default: its answers are
// questions, not skips, unless the Mac's settings say "skip" for the show (or for every show). The
// level is the stricter of the Mac's settings and the finder guard, as for the new finders. The
// rules are PodcastAds' `AppleModelAds` and `ModelPlacing`; this file only reads the two inputs.
// Called from the finder's own background task or the stream head's, never the main thread:
// PodcastTeaching reads its files the first time it is asked.
import Foundation
import PodcastAds

extension PodcastAdFinder {
  /// How the model's ads are placed for this episode's show. A show that is not known has the
  /// built-in level (ask).
  static func modelPlacing(forEpisode id: String, now: Date = Date()) -> ModelPlacing {
    let show = EpisodeShows.shared.show(for: id) ?? ""
    let tuning = PodcastTeaching.shared.files.tuning
    let guarded = PodcastFinderGuard.shared.mode(
      finder: FinderNames.appleModel, show: show, episode: id, now: now)
    return ModelPlacing(
      level: AppleModelAds.level(guarded: guarded, tuning: tuning, show: show), tuning: tuning,
      show: show)
  }
}
