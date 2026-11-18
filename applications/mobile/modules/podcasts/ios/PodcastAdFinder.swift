// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Finds the ads in downloaded episodes once their transcripts are ready, one episode at a
// time, with Apple's on-device model (PodcastAdsOnDevice, iOS 26). The pieces, the clean-up,
// the files and the status rules are PodcastAds; this file is the queue and the state of
// each episode. It runs while the app is open or a podcast is playing; with the app closed,
// iOS gives it turns through a background processing task (PodcastAdFinder+Background.swift).
// An episode joins the queue when its transcript is whole, and the order is PrepQueue's.

import Foundation
import PodcastAds
import PodcastAdsOnDevice
import PodcastDownloads
import PodcastTranscripts

final class PodcastAdFinder: @unchecked Sendable {
  static let shared = PodcastAdFinder()
  /// The detector whose files the app reads and the player skips.
  static let detectorName = "apple-on-device"

  let lock = NSLock()
  private var sink: ((String, [String: Any]) -> Void)?
  private var statuses: [String: AdsStatus] = [:]
  private var waiting: [String] = []
  /// The episode that is loaded in the player: it goes first, and the one at work makes way.
  private var urgent: String?
  /// Episodes whose transcript grew since their last partial pass, so the finished pieces of it
  /// can be checked for ads now.
  private var partialWanted: Set<String> = []
  /// Why the last full pass of an episode failed; it is tried again after a wait
  /// (PodcastAdFinder+Retry.swift).
  var failures: [String: String] = [:]
  /// How many full passes of an episode failed in a row.
  var failureCounts: [String: Int] = [:]
  /// Why the last partial pass of an episode failed. The next piece of transcript asks again.
  private var partialFailures: [String: String] = [:]
  private var retryScheduled = false
  var worker: Task<Void, Never>?
  /// The app is on the screen, a podcast is playing, or iOS gave a background turn.
  var appActive = false
  var playing = false
  var inBackgroundTask = false
  var lastAsked: Date?
  var started = false
  private let detector = AppleAds.makeDetector()

  private init() {}

  func setSink(_ sink: ((String, [String: Any]) -> Void)?) {
    lock.withLock { self.sink = sink }
  }

  // MARK: What the app tells us

  /// A download was deleted (its folder, and the ads with it).
  func removed(_ episodeId: String) {
    let send = lock.withLock { () -> ((String, [String: Any]) -> Void)? in
      waiting.removeAll { $0 == episodeId }
      partialWanted.remove(episodeId)
      failures[episodeId] = nil
      failureCounts[episodeId] = nil
      partialFailures[episodeId] = nil
      guard statuses.removeValue(forKey: episodeId) != nil else { return nil }
      return sink
    }
    send?("onAdsChange", ["episodeId": episodeId, "state": "none"])
  }

  func playbackChanged(isPlaying: Bool) {
    lock.withLock { playing = isPlaying }
    if isPlaying { kick() }
  }

  /// Every episode's state, for the app to read at start.
  func all() -> [[String: Any]] {
    lock.withLock { statuses }.map { AdsJSON.object($0.key, $0.value) }
  }

  /// An episode's saved ads as JSON (`AdsFile` in PodcastAds), or nil when there are none. While
  /// the full pass is not done, the ads found so far (the ones the player already skips).
  func adsJSON(_ episodeId: String) -> String? {
    guard let downloads = PodcastDownloader.shared.store,
      let (ads, _) = stores(for: episodeId, in: downloads)
    else { return nil }
    return ads.bestJSON(detector: Self.detectorName)
  }

  // MARK: Looking at the downloads

  private func stores(for episodeId: String, in downloads: DownloadStore) -> (AdsStore, TranscriptStore)? {
    guard let entry = downloads.entry(for: episodeId),
      case .downloaded(_, let sha, _, _) = entry.state,
      let folder = try? downloads.folder(for: episodeId)
    else { return nil }
    return (AdsStore(folder: folder, sha256: sha), TranscriptStore(folder: folder, sha256: sha))
  }

  /// Reads every download's files, queues the episodes with a transcript that still need
  /// their ads found and forgets the ones whose download is gone. Safe to call often.
  func scan() {
    guard let downloads = PodcastDownloader.shared.store else { return }
    let unavailable = AppleAds.unavailable()
    var present = Set<String>()
    for entry in downloads.entries() {
      let id = entry.episodeId
      guard let (ads, transcripts) = stores(for: id, in: downloads) else { continue }
      guard transcripts.hasTranscript else {
        // The transcript is still being made: the ads found in it so far, or why they cannot be
        // found, are shown, and the episode is not queued until the transcript is whole.
        let status = AdsRules.status(
          file: nil, partial: ads.loadPartial(detector: Self.detectorName),
          detectorVersion: detector?.version ?? "", finding: nil, unavailable: unavailable,
          failure: lock.withLock { partialFailures[id] })
        present.insert(id)
        switch status {
        case .partialFound, .notPossible:
          set(id, status)
        default:
          // What was shown before no longer holds (the model works now): back to nothing yet.
          if case .notPossible? = lock.withLock({ statuses[id] }) { set(id, .waiting) }
        }
        continue
      }
      present.insert(id)
      var finding: Int?
      if case .finding(let percent)? = lock.withLock({ statuses[id] }) { finding = percent }
      let status = AdsRules.status(
        file: ads.load(detector: Self.detectorName),
        partial: ads.loadPartial(detector: Self.detectorName),
        detectorVersion: detector?.version ?? "",
        finding: finding, unavailable: unavailable, failure: lock.withLock { failures[id] })
      set(id, status)
      if AdsRules.wantsRun(status) {
        lock.withLock { if !waiting.contains(id) { waiting.append(id) } }
      }
    }
    for id in lock.withLock({ Set(statuses.keys).subtracting(present) }) { removed(id) }
    if AdsRules.looksAgainLater(unavailable) { scanAgainLater() }
    kick()
  }

  /// While the model downloads, looks again in five minutes.
  private func scanAgainLater() {
    let schedule = lock.withLock { () -> Bool in
      defer { retryScheduled = true }
      return !retryScheduled
    }
    guard schedule else { return }
    DispatchQueue.global().asyncAfter(deadline: .now() + 300) { [self] in
      lock.withLock { retryScheduled = false }
      scan()
    }
  }

  private func set(_ id: String, _ status: AdsStatus) {
    let send = lock.withLock { () -> ((String, [String: Any]) -> Void)? in
      guard statuses[id] != status else { return nil }
      statuses[id] = status
      return sink
    }
    send?("onAdsChange", AdsJSON.object(id, status))
  }

  // MARK: Working

  /// The episode the player has loaded, or nil: it is worked on first. Called when the player
  /// loads an episode and when it unloads.
  func prefer(_ id: String?) {
    lock.withLock { urgent = id }
    kick()
  }

  /// The playing episode's transcript has a new piece: its finished pieces are checked for ads
  /// before the queue goes on.
  func transcriptGrew(_ id: String) {
    lock.withLock { _ = partialWanted.insert(id) }
    kick()
  }

  /// Takes an episode that wants a partial pass off the list, the urgent one first.
  private func takePartial() -> String? {
    lock.withLock {
      guard let id = (urgent.flatMap { partialWanted.contains($0) ? $0 : nil }) ?? partialWanted.first
      else { return nil }
      partialWanted.remove(id)
      return id
    }
  }

  /// Takes the next episode off the queue: the one loaded in the player, then Up Next, then
  /// the newest downloads (PrepQueue).
  private func takeNext() -> String? {
    let (list, playing) = lock.withLock { (waiting, urgent) }
    guard let id = PrepQueue.next(waiting: list, playing: playing) else { return nil }
    lock.withLock { waiting.removeAll { $0 == id } }
    return id
  }

  /// Whether another episode is urgent and waiting, or its transcript grew and wants a partial
  /// pass, so the one at work should stop (its answers so far are kept).
  private func makesWayForUrgent(_ id: String) -> Bool {
    lock.withLock {
      QueueOrder.shouldStop(working: id, waiting: waiting, urgent: urgent)
        || (urgent != id && urgent.map { partialWanted.contains($0) } == true)
    }
  }

  var allowedNow: Bool {
    lock.withLock {
      AdsRules.mayRun(appActive: appActive, playing: playing, inBackgroundTask: inBackgroundTask)
    }
  }
  var hasWork: Bool { lock.withLock { !waiting.isEmpty } }

  /// Starts the worker when there is work and it may run; otherwise asks iOS for a turn.
  func kick() {
    let started = lock.withLock { () -> Bool in
      guard worker == nil, !waiting.isEmpty || !partialWanted.isEmpty,
        AdsRules.mayRun(appActive: appActive, playing: playing, inBackgroundTask: inBackgroundTask)
      else { return false }
      var priority = TaskPriority.utility
      if let urgent, waiting.contains(urgent) { priority = .userInitiated }
      worker = Task.detached(priority: priority) { [self] in await drain() }
      return true
    }
    if !started && hasWork { askForBackgroundTime() }
  }

  private func drain() async {
    while allowedNow {
      if let id = takePartial() {
        await findPartial(id)
      } else if let id = takeNext() {
        await find(id)
      } else {
        break
      }
    }
    lock.withLock { worker = nil }
    kick()
  }

  private func mayContinue(_ id: String) -> Bool {
    allowedNow && !makesWayForUrgent(id) && PodcastDownloader.shared.store?.entry(for: id) != nil
  }

  /// Checks the transcript's finished pieces so far, so the player can skip ads in an episode
  /// that is still being transcribed. A failure is shown in the status and asked again after
  /// the next piece of transcript; the full pass runs when the transcript is done.
  private func findPartial(_ id: String) async {
    guard let downloads = PodcastDownloader.shared.store, let detector,
      let (ads, transcripts) = stores(for: id, in: downloads),
      !transcripts.hasTranscript, let partial = transcripts.loadPartial()
    else { return }
    do {
      let outcome = try await AdsRunner.runPartial(
        partial: partial, detector: detector, store: ads,
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        shouldContinue: { [weak self] in self?.mayContinue(id) ?? false })
      switch outcome {
      case .finished:
        lock.withLock { partialFailures[id] = nil }
        // The list and the seek bar show what was found so far.
        scan()
        Task { @MainActor in PodcastPlayer.shared.adSkipping.refresh() }
      case .stopped:
        // Stopped to make way or because the app left the screen: ask again when it can.
        if !mayContinue(id) { lock.withLock { _ = partialWanted.insert(id) } }
      }
    } catch is CancellationError {
      lock.withLock { _ = partialWanted.insert(id) }
    } catch AdDetectorError.unavailable(let reason) {
      lock.withLock { partialFailures[id] = reason.reason }
      scan()
    } catch {
      NSLog("Podcasts: ads in the transcript so far could not be checked: \(error)")
      lock.withLock { partialFailures[id] = Self.reason(for: error) }
      scan()
    }
  }

  private func find(_ id: String) async {
    guard let downloads = PodcastDownloader.shared.store, let detector,
      let (ads, transcripts) = stores(for: id, in: downloads)
    else { return }
    guard let transcript = transcripts.loadTranscript() else {
      return fail(id, "The transcript could not be read")
    }
    set(id, .finding(percent: 0))
    do {
      let outcome = try await AdsRunner.run(
        transcript: transcript, detector: detector, store: ads,
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        progress: { [weak self] done, total in
          self?.set(id, .finding(percent: AdsRules.percent(done: done, total: total)))
        },
        shouldContinue: { [weak self] in self?.mayContinue(id) ?? false })
      switch outcome {
      case .finished(let file):
        lock.withLock { failureCounts[id] = nil }
        set(id, file.ads.isEmpty ? .noneFound : .found(count: file.ads.count))
        // An episode that is playing now starts skipping the new ads.
        Task { @MainActor in PodcastPlayer.shared.adSkipping.refresh() }
      case .stopped:
        pause(id)
      }
    } catch AdDetectorError.unavailable(let reason) {
      fail(id, reason.reason, retry: reason.passesByItself)
    } catch is CancellationError {
      pause(id)
    } catch {
      if downloads.entry(for: id) == nil { return removed(id) }
      fail(id, Self.reason(for: error))
    }
  }

  /// Forgets why earlier tries failed, so the next scan tries those episodes again. Called when
  /// the app comes to the front: a busy or rate-limited model works again by then.
  func forgetFailures() {
    lock.withLock {
      failures.removeAll()
      failureCounts.removeAll()
    }
  }

  /// Shows why this episode's ads could not be found, and asks again after a growing wait, a
  /// few times (PodcastAdFinder+Retry.swift). `retry` is false when waiting cannot help.
  private func fail(_ id: String, _ reason: String, retry: Bool = true) {
    lock.withLock { failures[id] = reason }
    set(id, .notPossible(reason: reason))
    if retry { retryLater(id) }
  }

  /// Back to the front of the queue; its download may be gone.
  private func pause(_ id: String) {
    guard PodcastDownloader.shared.store?.entry(for: id) != nil else { return removed(id) }
    lock.withLock {
      if !waiting.contains(id) {
        waiting.insert(id, at: QueueOrder.insertIndex(waiting: waiting, urgent: urgent))
      }
    }
    set(id, .waiting)
  }
}
