// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The ad finder's work loop: which piece of work is next (every waiting episode's head before
// any episode's rest, the playing episode first; PrepQueue and PodcastAds' PrepOrder), and the
// pass over the transcript made so far.

import Foundation
import PodcastAds
import PodcastAdsOnDevice
import PodcastDownloads
import PodcastTranscripts

extension PodcastAdFinder {
  /// The next piece of work: a partial pass (the playing episode's growing transcript, or another
  /// episode's head) or a full pass (a rest).
  private func peekNext() -> PrepStep? {
    let (rests, heads, playing) = lock.withLock { (waiting, partialWanted, urgent) }
    return PrepQueue.nextStep(heads: heads, rests: rests, playing: playing)
  }

  /// Takes the next piece of work off its list.
  private func takeNext() -> PrepStep? {
    guard let step = peekNext() else { return nil }
    lock.withLock {
      if step.stage == .head {
        _ = partialWanted.remove(step.id)
      } else {
        waiting.removeAll { $0 == step.id }
      }
    }
    return step
  }

  /// Whether the work at hand should stop at its next piece to make way (its answers so far are
  /// kept): a rest for any head that waits, a head for the playing episode.
  private func makesWay(_ working: PrepStep) -> Bool {
    PrepOrder.shouldYield(working: working, next: peekNext(), playing: lock.withLock { urgent })
  }

  var allowedNow: Bool {
    lock.withLock {
      AdsRules.mayRun(appActive: appActive, playing: playing, inBackgroundTask: inBackgroundTask)
    }
  }
  var hasWork: Bool { lock.withLock { !waiting.isEmpty || !partialWanted.isEmpty } }

  /// Starts the worker when there is work and it may run; otherwise asks iOS for a turn.
  func kick() {
    let started = lock.withLock { () -> Bool in
      guard worker == nil, !waiting.isEmpty || !partialWanted.isEmpty,
        AdsRules.mayRun(appActive: appActive, playing: playing, inBackgroundTask: inBackgroundTask)
      else { return false }
      var priority = TaskPriority.utility
      if let urgent, waiting.contains(urgent) || partialWanted.contains(urgent) {
        priority = .userInitiated
      }
      worker = Task.detached(priority: priority) { [self] in await drain() }
      return true
    }
    if !started && hasWork { askForBackgroundTime() }
  }

  private func drain() async {
    while allowedNow, let step = takeNext() {
      switch step.stage {
      case .head: await findPartial(step.id)
      case .rest: await find(step.id)
      }
    }
    lock.withLock { worker = nil }
    kick()
  }

  func mayContinue(_ step: PrepStep) -> Bool {
    allowedNow && !makesWay(step) && PodcastDownloader.shared.store?.entry(for: step.id) != nil
  }

  /// Checks the transcript's finished pieces so far, so the player can skip ads in an episode
  /// that is still being transcribed. For an episode that is not playing, only its head (the
  /// first three minutes) is looked at. A failure is shown in the status and asked again after
  /// the next piece of transcript; the full pass runs when the transcript is done.
  private func findPartial(_ id: String) async {
    guard let downloads = PodcastDownloader.shared.store,
      let (ads, transcripts) = stores(for: id, in: downloads)
    else { return }
    let isPlaying = lock.withLock { urgent == id }
    // The playing episode's whole transcript goes to the full pass, which asks everything.
    guard let partial = transcripts.loadPartial() ?? (isPlaying ? nil : wholeAsPartial(transcripts))
    else { return }
    let step = PrepStep(id: id, stage: .head)
    // Later passes are noted only when what they say changes (the diary drops a repeat).
    if ads.loadPartial(detector: Self.detectorName) == nil {
      PodcastTimeline.mark(
        id, "first partial pass started: \(isPlaying ? "playing episode" : "head only")")
    }
    // The phone's own finders go first, on the words looked at, whatever the model can do.
    let local = localAds(
      id, ads: ads, partial: partial, limit: isPlaying ? nil : PrepRules.headSeconds)
    if addLocalToPartial(local, ads: ads, duration: partial.duration) { refreshIfPlaying(id) }
    // Apple's model is asked here only on a show where its level is skip: its answers elsewhere
    // are questions, which only the full pass makes (PodcastAdFinder+Apple.swift).
    let placing = Self.modelPlacing(forEpisode: id)
    guard placing.level == .skip, let model = askableDetector() else {
      // Nothing more to ask: the list and the seek bar show the local ads.
      scan()
      return
    }
    do {
      let outcome = try await AdsRunner.runPartial(
        partial: partial, detector: model, store: ads,
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        limit: isPlaying ? nil : PrepRules.headSeconds, placing: placing,
        shouldContinue: { [weak self] in self?.mayContinue(step) ?? false })
      switch outcome {
      case .finished(let found):
        PodcastTimeline.mark(
          id, "partial pass: \(found.ads.count) ads, \(found.refusedPieces ?? 0) pieces refused")
        lock.withLock { partialFailures[id] = nil }
        // The model's answers replaced the local ads inside the stretch it asked about: again.
        addLocalToPartial(local, ads: ads, duration: partial.duration)
        // The ads the phone remembers join what the model found, in the stretch it looked at.
        let head = PrepRules.headSeconds
        let looked = isPlaying ? partial.words : partial.words.filter { $0.end <= head }
        addRemembered(id, ads: ads, words: looked)
        // The list and the seek bar show what was found so far.
        scan()
        // The player hears the new ranges of the episode it plays at once.
        if isPlaying { Task { @MainActor in PodcastPlayer.shared.adSkipping.refresh() } }
      case .stopped:
        PodcastTimeline.mark(id, "partial pass stopped to make way")
        // Stopped to make way or because the app left the screen: ask again when it can.
        if !mayContinue(step) { lock.withLock { _ = partialWanted.insert(id) } }
      }
    } catch is CancellationError {
      PodcastTimeline.mark(id, "partial pass cancelled")
      lock.withLock { _ = partialWanted.insert(id) }
    } catch AdDetectorError.unavailable(let reason) {
      PodcastTimeline.mark(id, "partial pass failed: model unavailable, \(reason.reason)")
      lock.withLock { partialFailures[id] = reason.reason }
      scan()
    } catch {
      NSLog("Podcasts: ads in the transcript so far could not be checked: \(error)")
      PodcastTimeline.mark(id, "partial pass failed: \(AdDiary.note(for: error))")
      lock.withLock { partialFailures[id] = Self.reason(for: error) }
      scan()
    }
  }

  /// A whole transcript read as a partial one that reached its end, so its head is checked the
  /// same way as a head that is still being transcribed.
  private func wholeAsPartial(_ transcripts: TranscriptStore) -> PartialTranscript? {
    guard let whole = transcripts.loadTranscript() else { return nil }
    return PartialTranscript(
      identity: whole.identity, duration: whole.duration, reached: whole.duration, words: whole.words)
  }
}
