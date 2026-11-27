// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// What a tap on skip forward does in an episode with ads. Every skip-forward button (the app, the
// lock screen, the headphones) ends in `PodcastPlayer.skip(by:)`, which asks here first. The rule
// is `AdSkipTap` in PodcastAds: in a known ad the tap leaves it like the Skip ad button (the ad
// and the ads that follow it, also after a hole of 15 seconds or less; one jump, one Undo), in an
// open question it is the answer yes, in a maybe it confirms the maybe, in a short hole between
// two skipped ads it goes to the next one, and anywhere else it is the plain move (taken to the
// end of a skipped ad it would land in).

import Foundation
import PodcastAds

@MainActor
extension PodcastAdSkipping {
  /// The listener tapped skip forward, which would move the playhead to `plain`. True when the tap
  /// was handled here (the playhead moved or the tap was an answer), false when the caller makes
  /// the plain move itself: nothing is loaded, or an answer or a confirmation could not be made.
  func tappedForward(plain: Double) -> Bool {
    guard let episodeId, owner.current != nil else { return false }
    let place = owner.place
    let recent = skipper.lastSkip
    let action = AdSkipTap.decide(
      position: place, plain: plain, duration: owner.currentDuration,
      file: store?.best(detector: PodcastAdFinder.detectorName), settings: settings,
      lastSkip: recent?.skip, lastSkipAge: recent.map { now - $0.at } ?? .infinity)
    switch action {
    case .plain(let to):
      // The listener's own seek, as before; only the place is kept out of a skipped ad.
      owner.seek(to: to)
      return true
    case .skip(let skip):
      skipper.noteSkip(skip, now: now)
      jump(skip, from: place)
      return true
    case .answer(let start):
      return answerQuestion(episodeId: episodeId, start: start, isAd: true)
    case .confirm(let start):
      return confirmMaybe(episodeId: episodeId, start: start)
    case .bridge(let to, let holeEnd):
      note(.missed, start: place, end: holeEnd, kind: nil)
      owner.movePlayheadByPlayer(to: to)
      return true
    }
  }

  /// The tap confirms the maybe of the loaded episode that starts at `start`: it becomes a sure
  /// ad, the finder that made it is told it was right, and the playhead leaves it. False when no
  /// open maybe starts there or the file could not be saved (nothing is noted then, and the
  /// caller makes the plain move).
  ///
  /// This is the yes branch of `answerQuestion`. The maybe's own `source` is read before the
  /// confirmation and goes into the note's `by` and to the finder, as the question's does.
  func confirmMaybe(episodeId id: String, start: Double) -> Bool {
    guard id == episodeId, let store,
      let maybe = AdMaybes.confirm(
        store: store, detector: PodcastAdFinder.detectorName, maybeStart: start)
    else { return false }
    var ad = maybe
    ad.confidence = .sure
    ad.source = AdAsking.source
    note(.confirmed, start: ad.start, end: ad.end, kind: ad.kind, by: maybe.source)
    PodcastAdFinder.shared.learnAnswered(
      id, source: maybe.source, start: ad.start, end: ad.end, isAd: true)
    // A confirmation after the stretch is over teaches but has nothing left to skip.
    let place = owner.place
    if place < ad.end {
      let from = max(place, ad.start)
      var skip = AdSkip(ad: ad, target: AdSkipper.target(for: ad, duration: owner.currentDuration))
      // The stretch is a known ad of the saved file now, so the rule gives the skip with the ads
      // that follow it at once: one jump, one note and one Undo for all of them.
      if case .skip(let whole) = AdSkipTap.decide(
        position: from, plain: from, duration: owner.currentDuration,
        file: store.best(detector: PodcastAdFinder.detectorName), settings: settings,
        lastSkip: nil, lastSkipAge: .infinity)
      {
        skip = whole
      }
      skipper.noteSkip(skip, now: now)
      jump(skip, from: from)
    }
    refresh()
    return true
  }
}
