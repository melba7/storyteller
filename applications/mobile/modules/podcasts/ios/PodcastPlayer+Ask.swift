// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The questions the phone asks about a stretch it is not sure is an ad (`AdAsking` in PodcastAds,
// kept in the ads file as `asks`). When the playhead enters one that is still open, the app is
// told once (the event `onAdAsk`) and shows "Ad? Skip" with two answers. "Yes" skips the stretch
// like any other skip, with its note, tally and Undo; "no" stops the phone asking about it. Both
// are noted for the Mac with the name of the finder that asked, and the finder is told what the
// answer was (`PodcastAdFinder.learnAnswered`). A question is only shown on the screen: with the
// phone locked the stretch plays.
//
// Nothing polls. Like the skip markers, a boundary time observer is set at the start of each
// open question, and the saved file is read again by `PodcastAdSkipping.refresh()` (which also
// runs when a seek lands), so a question the playhead is already in is found there.

import AVFoundation
import Foundation
import PodcastAds

/// An answer names its question by the start the app was told; this much off still counts (the
/// same as `AdAsking`'s own rule).
private let askStartTolerance = 0.5

/// Watches the questions of the loaded episode and tells the app when the playhead enters one.
@MainActor
final class PodcastAsking {
  private unowned let owner: PodcastPlayer
  private var episodeId: String?
  /// The ads file as it was read last.
  private var file: AdsFile?
  /// The starts of the questions that were announced in this playback.
  private var announced: Set<Double> = []
  /// The starts the boundary observer is set at.
  private var marked: [Double] = []
  private var observer: Any?

  init(_ owner: PodcastPlayer) { self.owner = owner }

  /// An episode was loaded: none of its questions was announced yet.
  func begin(_ id: String, file: AdsFile?) {
    removeMarkers()
    announced = []
    update(file, episode: id)
  }

  /// The ads file of `episode` was read again (ads or questions were found, or an answer was
  /// saved).
  func update(_ file: AdsFile?, episode id: String) {
    episodeId = id
    self.file = file
    let starts = file.map { AdAsking.open(in: $0).map(\.start) } ?? []
    if starts != marked { setMarkers(starts) }
    // An answered question is not asked again, so it need not be remembered.
    announced.formIntersection(starts)
    look()
  }

  /// The question the playhead is in at `time`, from the file as it was read last.
  func live(at time: Double) -> FoundAd? {
    guard let file else { return nil }
    return AdAsking.live(in: file, at: time)
  }

  /// The playhead was moved to `position` by a seek. A question it is no longer in is announced
  /// again when it gets in (a seek back before it, or past it and back).
  func seeked(to position: Double) {
    guard let file else { return }
    let inside = AdAsking.open(in: file).filter { $0.start <= position && position < $0.end }
    announced.formIntersection(inside.map(\.start))
  }

  /// Tells the app about the question the playhead is in, once. While a seek is on its way the
  /// playhead still reads the old place: the seek's landing looks again.
  private func look() {
    guard let episodeId, !owner.seekPending, let ask = live(at: owner.position),
      !announced.contains(ask.start)
    else { return }
    announced.insert(ask.start)
    owner.sink?(
      "onAdAsk",
      [
        "episodeId": episodeId, "start": ask.start, "end": ask.end, "kind": ask.kind.rawValue,
      ])
  }

  private func setMarkers(_ starts: [Double]) {
    removeMarkers()
    marked = starts
    // A marker at zero is never crossed; a question that starts there is found by `look`.
    let times = starts.map {
      NSValue(time: CMTime(seconds: max(0.05, $0), preferredTimescale: 600))
    }
    guard !times.isEmpty else { return }
    observer = owner.player.addBoundaryTimeObserver(forTimes: times, queue: .main) { [weak self] in
      Task { @MainActor in self?.look() }
    }
  }

  private func removeMarkers() {
    if let observer { owner.player.removeTimeObserver(observer) }
    observer = nil
    marked = []
  }
}

@MainActor
extension PodcastAdSkipping {
  /// The listener's answer to the question of the loaded episode that starts at `start`: yes
  /// (`isAd`) skips the stretch, no says it is not an ad. False when no open question starts
  /// there (it was answered, an ad covers it now, or another episode is loaded), and for a no
  /// that could not be saved.
  ///
  /// The question's own `source` (the finder that made it) is read before the answer, because a
  /// yes replaces it with "tap". It goes into the note's `by`, which is how the Mac learns which
  /// finder was right, and to the finder (`learnAnswered`, after a yes and after a no that was
  /// saved), which does the learning of its own: the known ads, its guard and the repeated words.
  func answerQuestion(episodeId id: String, start: Double, isAd: Bool) -> Bool {
    guard id == episodeId, let store,
      let file = store.best(detector: PodcastAdFinder.detectorName),
      let ask = AdAsking.open(in: file).first(where: { abs($0.start - start) < askStartTolerance })
    else { return false }
    let finder = ask.source
    let answered = AdAsking.answer(
      store: store, detector: PodcastAdFinder.detectorName, askStart: ask.start, isAd: isAd)
    guard isAd else {
      // Nothing was saved, so nothing is noted: the question may be asked again.
      guard let answered else { return false }
      note(.denied, start: answered.start, end: answered.end, kind: answered.kind, by: finder)
      PodcastAdFinder.shared.learnAnswered(
        id, source: finder, start: answered.start, end: answered.end, isAd: false)
      refresh()
      return true
    }
    // A yes skips the stretch even when saving it failed or an ad covers it by now: the listener
    // pressed Skip. The stretch is the one that was read (`answered` is the same question).
    var ad = answered ?? ask
    ad.confidence = .sure
    ad.source = AdAsking.source
    note(.confirmed, start: ad.start, end: ad.end, kind: ad.kind, by: finder)
    if answered != nil {
      PodcastAdFinder.shared.learnAnswered(
        id, source: finder, start: ad.start, end: ad.end, isAd: true)
    }
    // A yes after the stretch is over teaches but has nothing left to skip.
    let place = owner.place
    if place < ad.end {
      let skip = AdSkip(ad: ad, target: AdSkipper.target(for: ad, duration: owner.currentDuration))
      skipper.noteSkip(skip, now: now)
      jump(skip, from: max(place, ad.start))
    }
    refresh()
    return true
  }
}
