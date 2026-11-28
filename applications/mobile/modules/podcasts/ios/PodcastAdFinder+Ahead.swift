// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The "ahead" finder on the phone: the ads the Mac marked in an episode the night before, found
// again in the phone's own transcript by their words (PodcastAds' `AheadAds`). The Mac's file is
// `ahead-ads.json`; which entry is which episode comes from the table the app sends
// (`PodcastTeaching.aheadEntry`). Every decision is in PodcastAds; this file only runs it under the
// finder guard: in the whole-transcript pass, in the head scan of a stream, and in a pass of its
// own for an episode whose ads file is final already (the Mac marks at night, and the phone has
// usually checked the episode the evening before).
import Foundation
import PodcastAds
import PodcastDownloads
import PodcastTranscripts

extension PodcastAdFinder {
  /// What the marks of this episode give in a whole transcript, or nil when the episode has no
  /// marks or iOS did not hold the time. `judged` are the stretches the listener undid, said no to
  /// or was asked about: nothing is given over them. The marks used are noted for the episode, so
  /// the pass below does not look again unless newer marks come; a caller that saves what the
  /// marks gave itself passes `recordPass: false` and notes them once the save is done.
  func aheadFound(
    _ id: String, transcript: Transcript, judged: [(start: Double, end: Double)],
    recordPass: Bool = true
  ) -> AheadFound? {
    guard let entry = PodcastTeaching.shared.aheadEntry(episode: id) else { return nil }
    let found = PodcastFinderGuard.shared.hold([FinderNames.ahead], episode: id) { _ in
      AheadAds.find(entry, words: transcript.words, judged: judged)
    }
    if recordPass, found != nil {
      PodcastTeaching.shared.recordAheadPass(episode: id, marked: entry.marked)
    }
    return found
  }

  // MARK: The episodes whose ads are final

  /// Looks, in the background, at the downloaded episodes whose final ads file is made and that
  /// have marks from the Mac the finder has not used yet. Returns at once; asking again while a
  /// pass runs makes it look once more when it is done.
  func lookAhead() {
    refreshMacMarks()
    lock.withLock {
      guard aheadWorker == nil else {
        aheadAgain = true
        return
      }
      aheadWorker = Task.detached(priority: .utility) { [self] in
        var again = true
        while again {
          aheadPassOverDownloads()
          again = lock.withLock {
            let more = aheadAgain
            aheadAgain = false
            if !more { aheadWorker = nil }
            return more
          }
        }
      }
    }
  }

  private func aheadPassOverDownloads() {
    guard let downloads = PodcastDownloader.shared.store else { return }
    for entry in downloads.entries() {
      guard allowedNow else { return }
      aheadPass(entry.episodeId, in: downloads)
    }
  }

  /// The pass over one episode: the finder is run over its stored transcript and what it finds goes
  /// into its final ads file (`AheadPass.merge`). An episode that is waiting for its own pass, or
  /// is in one, is left to it: that pass runs the finder too. No model is asked and no sound read.
  private func aheadPass(_ id: String, in downloads: DownloadStore) {
    guard let marks = PodcastTeaching.shared.aheadEntry(episode: id),
      PodcastTeaching.shared.aheadPassNeeded(episode: id, marked: marks.marked),
      !lock.withLock({ waiting.contains(id) || partialWanted.contains(id) }), !isFinding(id),
      let (ads, transcripts) = stores(for: id, in: downloads), transcripts.hasTranscript,
      let file = ads.load(detector: Self.detectorName), let modes = newModes(id),
      modes.level(FinderNames.ahead) != .off, let transcript = transcripts.loadTranscript(),
      let found = aheadFound(
        id, transcript: transcript, judged: AheadPass.judged(in: file), recordPass: false)
    else { return }
    let made = AheadPass.merge(
      found, into: file, show: modes.show, listener: modes.listener, tuning: modes.tuning,
      level: modes.level(FinderNames.ahead))
    PodcastTimeline.mark(
      id, "marks of the night before: \(made.skips) ads, \(made.questions) questions")
    // The marks count as used once what they gave is saved, or when they gave nothing new. When
    // the save fails they are not noted, so the next pass looks again.
    let changed = made.file != file
    if changed, (try? ads.save(made.file)) == nil { return }
    PodcastTeaching.shared.recordAheadPass(episode: id, marked: marks.marked)
    guard changed else { return }
    set(id, AdsRules.finished(ads.load(detector: Self.detectorName) ?? made.file))
    // The playing episode skips the new ads at once.
    Task { @MainActor in PodcastPlayer.shared.adSkipping.refresh() }
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
