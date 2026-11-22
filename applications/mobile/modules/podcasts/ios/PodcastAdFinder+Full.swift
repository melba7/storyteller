// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The full pass over a whole transcript. The phone's own finders (PodcastAdFinder+Local.swift) go
// first and their ads are in the episode's ads files before Apple's model is asked. When the model
// cannot be asked, or its run fails, the local result is saved as the episode's final file
// (`detectorVersion` empty); the episode is asked again when the model can be.
import Foundation
import PodcastAds
import PodcastAdsOnDevice
import PodcastDownloads
import PodcastTranscripts

extension PodcastAdFinder {
  func find(_ id: String) async {
    guard let downloads = PodcastDownloader.shared.store,
      let (ads, transcripts) = stores(for: id, in: downloads)
    else { return }
    // At once, so a scan that runs meanwhile does not queue the episode a second time.
    set(id, .finding(percent: 0))
    lock.withLock { _ = localRerun.remove(id) }
    guard let transcript = transcripts.loadTranscript() else {
      PodcastTimeline.mark(id, "full pass: the transcript could not be read")
      return fail(id, "The transcript could not be read")
    }
    let local = localAds(id, ads: ads, transcript: transcript)
    guard let model = askableDetector() else {
      PodcastTimeline.mark(id, "full pass without the model")
      return await saveLocalOnly(id, ads: ads, transcript: transcript, local: local)
    }
    // A local-only result is about to be replaced: what the listener undid in it is kept.
    LocalAdsFile.carryChoices(store: ads, detector: Self.detectorName)
    if addLocalToPartial(local, ads: ads, duration: transcript.duration) { refreshIfPlaying(id) }
    do {
      let outcome = try await AdsRunner.run(
        transcript: transcript, detector: model, store: ads,
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        progress: { [weak self] done, total in
          guard let self else { return }
          if done == 0 { PodcastTimeline.mark(id, "full pass started: \(total) pieces") }
          set(id, .finding(percent: AdsRules.percent(done: done, total: total)))
          // Each piece is saved as a partial file, which replaces the local ads in it: they go
          // in again, and the playing episode skips its ads at once.
          if done > 0 { addLocalToPartial(local, ads: ads, duration: transcript.duration) }
          refreshIfPlaying(id)
        },
        shouldContinue: { [weak self] in self?.mayContinue(PrepStep(id: id, stage: .rest)) ?? false })
      switch outcome {
      case .finished(let found):
        lock.withLock { failureCounts[id] = nil }
        // The local ads join the model's, then chapters named like an ad break (with words that
        // sell inside) add to both.
        let joined = LocalAdsFile.addToFinal(local, store: ads, detector: Self.detectorName) ?? found
        let file = await withChapterAds(id, ads: ads, finished: joined, transcript: transcript)
        set(id, AdsRules.finished(file))
        PodcastTimeline.mark(
          id, "full pass ended: \(file.ads.count) ads, \(file.refusedPieces ?? 0) pieces refused")
        // The sure ads are remembered by their words, so a repeat is found at once. Only sure ads
        // are taken: the local ones are sure when a strong rule or an exact taught sound says so.
        learnRemembered(id, ads: ads, finished: file, transcript: transcript)
        // The words the show opens with are learned from the episode's first minutes.
        learnOpening(id, ads: ads, finished: file, transcript: transcript)
        // An episode that is playing now starts skipping the new ads.
        Task { @MainActor in PodcastPlayer.shared.adSkipping.refresh() }
      case .stopped:
        PodcastTimeline.mark(id, "full pass stopped to make way")
        pause(id)
      }
    } catch AdDetectorError.unavailable(let reason) {
      PodcastTimeline.mark(id, "full pass failed: model unavailable, \(reason.reason)")
      noteFailure(id, reason.reason, retry: reason.passesByItself)
      await saveLocalOnly(id, ads: ads, transcript: transcript, local: local)
    } catch is CancellationError {
      PodcastTimeline.mark(id, "full pass cancelled")
      pause(id)
    } catch {
      if downloads.entry(for: id) == nil { return removed(id) }
      // The error's type name and case name, not its words.
      PodcastTimeline.mark(id, "full pass failed: \(AdDiary.note(for: error))")
      noteFailure(id, Self.reason(for: error))
      await saveLocalOnly(id, ads: ads, transcript: transcript, local: local)
    }
  }

  /// Saves the local ads as the episode's final file, then chapters, the status and the player's
  /// refresh as after a finished pass. What the model found so far and its answers are kept. This
  /// result is not learned into the memory of ads or the show's opening words: only the model's
  /// own pass is trusted for that, and it runs when the model can be asked again.
  private func saveLocalOnly(
    _ id: String, ads: AdsStore, transcript: Transcript, local: [FoundAd]
  ) async {
    let saved: AdsFile
    do {
      saved = try LocalAdsFile.saveFinal(
        local, store: ads, detector: Self.detectorName, detectorVersion: LocalAdsFile.localVersion,
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        duration: transcript.duration, afterFailure: true)
    } catch {
      PodcastTimeline.mark(id, "local result could not be saved: \(AdDiary.note(for: error))")
      set(id, .notPossible(reason: "The ads could not be saved"))
      return
    }
    let file = await withChapterAds(id, ads: ads, finished: saved, transcript: transcript)
    set(id, AdsRules.finished(file))
    PodcastTimeline.mark(id, "full pass ended without the model: \(file.ads.count) ads")
    Task { @MainActor in PodcastPlayer.shared.adSkipping.refresh() }
  }
}
