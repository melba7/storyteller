// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Transcribes downloaded episodes, one at a time, in the show's language. The pieces, files and
// resume rules are PodcastTranscripts; the recogniser is PodcastSpeech (iOS 26 only). This
// file is the queue and the state of each episode. It runs while the app is open or a podcast
// is playing; with the app closed, iOS gives it turns through a background processing task
// (PodcastTranscriber+Background.swift). Every turn carries on from the partial file.

import Foundation
import PodcastDownloads
import PodcastSpeech
import PodcastTranscripts

final class PodcastTranscriber: @unchecked Sendable {
  static let shared = PodcastTranscriber()

  let lock = NSLock()
  private var sink: ((String, [String: Any]) -> Void)?
  private var statuses: [String: TranscriptStatus] = [:]
  private var waiting: [String] = []
  /// The episode that is loaded in the player: it goes first, and the one at work makes way.
  private var urgent: String?
  var worker: Task<Void, Never>?
  /// The app is on the screen, a podcast is playing, or iOS gave a background turn.
  var appActive = false
  var playing = false
  var inBackgroundTask = false
  var lastAsked: Date?
  var started = false
  private let languages: TranscriptLanguages?
  private let recogniser = AppleSpeech.makeRecogniser()

  private init() {
    languages = PodcastDownloader.shared.store.map {
      TranscriptLanguages(url: $0.root.appendingPathComponent("transcript-languages.json"))
    }
  }

  func setSink(_ sink: ((String, [String: Any]) -> Void)?) {
    lock.withLock { self.sink = sink }
  }

  // MARK: What the app tells us

  /// The language an episode is to be transcribed in, noted when its download starts. A start
  /// that does not know the language leaves the one already noted.
  func noteLanguage(_ language: String?, for episodeId: String) {
    languages?.remember(language, for: episodeId)
  }

  /// A download was installed: transcribe it.
  func downloaded(_ episodeId: String) {
    scan()
  }

  /// A download was deleted (its folder, and the transcript with it).
  func removed(_ episodeId: String) {
    let send = lock.withLock { () -> ((String, [String: Any]) -> Void)? in
      waiting.removeAll { $0 == episodeId }
      statuses[episodeId] = nil
      return sink
    }
    languages?.note(nil, for: episodeId)
    PodcastAdFinder.shared.removed(episodeId)
    send?("onTranscriptChange", ["episodeId": episodeId, "state": "none"])
  }

  func playbackChanged(isPlaying: Bool) {
    lock.withLock { playing = isPlaying }
    PodcastAdFinder.shared.playbackChanged(isPlaying: isPlaying)
    if isPlaying { kick() }
  }

  /// Every episode's state, for the app to read at start.
  func all() -> [[String: Any]] {
    lock.withLock { statuses }.map { TranscriptJSON.object($0.key, $0.value) }
  }

  /// A finished transcript's JSON, for the app to read, or nil.
  func transcriptJSON(_ episodeId: String) -> String? {
    guard let downloads = PodcastDownloader.shared.store, let files = files(for: episodeId, in: downloads)
    else { return nil }
    return files.transcriptJSON()
  }

  /// The lines transcribed so far, as the JSON of a transcript (its `lines`), or nil.
  func partialJSON(_ episodeId: String) -> String? {
    guard let downloads = PodcastDownloader.shared.store, let files = files(for: episodeId, in: downloads)
    else { return nil }
    return files.partialJSON()
  }

  // MARK: Looking at the downloads

  private func files(for episodeId: String, in downloads: DownloadStore) -> TranscriptStore? {
    guard let entry = downloads.entry(for: episodeId),
      case .downloaded(_, let sha, _, _) = entry.state,
      let folder = try? downloads.folder(for: episodeId)
    else { return nil }
    return TranscriptStore(folder: folder, sha256: sha)
  }

  /// Reads every download's files, queues the episodes that still need a transcript and
  /// forgets the ones whose download is gone. Safe to call often.
  func scan() {
    guard let downloads = PodcastDownloader.shared.store else { return }
    var present = Set<String>()
    for entry in downloads.entries() {
      let id = entry.episodeId
      guard let files = files(for: id, in: downloads) else { continue }
      present.insert(id)
      if recogniser == nil && !files.hasTranscript {
        set(id, .notSupported(reason: AppleSpeech.needsNewerSystem))
        continue
      }
      switch files.status() {
      case .waiting:
        let current = lock.withLock { statuses[id] }
        if case .transcribing? = current { continue }
        if current != .waiting { set(id, .waiting) }
        lock.withLock { if !waiting.contains(id) { waiting.append(id) } }
      case let settled:
        set(id, settled)
      }
    }
    let gone = lock.withLock { Set(statuses.keys).subtracting(present) }
    for id in gone { removed(id) }
    // Keep the language of an episode that is still downloading too: it is saved when the
    // download starts and is needed when the file arrives.
    languages?.prune(keeping: Set(downloads.entries().map(\.episodeId)))
    kick()
  }

  private func set(_ id: String, _ status: TranscriptStatus) {
    let send = lock.withLock { () -> ((String, [String: Any]) -> Void)? in
      guard statuses[id] != status else { return nil }
      statuses[id] = status
      return sink
    }
    send?("onTranscriptChange", TranscriptJSON.object(id, status))
  }

  // MARK: Working

  /// The episode the player has loaded, or nil: it is worked on first. Called when the player
  /// loads an episode and when it unloads.
  func prefer(_ id: String?) {
    lock.withLock { urgent = id }
    kick()
  }

  /// Takes the next episode off the queue: the urgent one when it waits, otherwise the first.
  private func takeNext() -> String? {
    lock.withLock {
      guard let id = QueueOrder.next(waiting: waiting, urgent: urgent) else { return nil }
      waiting.removeAll { $0 == id }
      return id
    }
  }

  /// Whether another episode is urgent and waiting, so the one at work should stop.
  private func makesWayForUrgent(_ id: String) -> Bool {
    lock.withLock { QueueOrder.shouldStop(working: id, waiting: waiting, urgent: urgent) }
  }

  var allowedNow: Bool { lock.withLock { appActive || playing || inBackgroundTask } }
  var hasWork: Bool { lock.withLock { !waiting.isEmpty } }

  /// Starts the worker when there is work and it may run; otherwise asks iOS for a turn.
  func kick() {
    let started = lock.withLock { () -> Bool in
      guard worker == nil, !waiting.isEmpty, appActive || playing || inBackgroundTask else {
        return false
      }
      var priority = TaskPriority.utility
      if let urgent, waiting.contains(urgent) { priority = .userInitiated }
      worker = Task.detached(priority: priority) { [self] in await drain() }
      return true
    }
    if !started && hasWork { askForBackgroundTime() }
  }

  private func drain() async {
    while allowedNow, let id = takeNext() {
      await transcribe(id)
    }
    lock.withLock { worker = nil }
    kick()
  }

  /// Whether the episode may go on with its next piece.
  private func mayContinue(_ id: String) -> Bool {
    allowedNow && !makesWayForUrgent(id) && PodcastDownloader.shared.store?.entry(for: id) != nil
  }

  /// A piece of the playing episode is saved: its ads can be looked for now.
  private func tellAdFinder(_ id: String) {
    guard lock.withLock({ urgent == id }) else { return }
    PodcastAdFinder.shared.transcriptGrew(id)
  }

  private func transcribe(_ id: String) async {
    guard let downloads = PodcastDownloader.shared.store, let recogniser,
      let entry = downloads.entry(for: id), case .downloaded(let file, _, _, _) = entry.state,
      let files = files(for: id, in: downloads)
    else { return }
    if files.hasTranscript { return set(id, .done) }
    let phone = Locale.preferredLanguages.first ?? "en-US"
    let locale = LocalePick.identifier(feedLanguage: languages?.language(for: id), phone: phone)
    set(id, .transcribing(percent: 0))
    do {
      let outcome = try await TranscriptRunner.run(
        audio: files.folder.appendingPathComponent(file), sha256: files.sha256, locale: locale,
        recogniser: recogniser, store: files,
        progress: { [weak self] percent in
          self?.set(id, .transcribing(percent: percent))
          self?.tellAdFinder(id)
        },
        shouldContinue: { [weak self] in self?.mayContinue(id) ?? false })
      switch outcome {
      case .finished:
        set(id, .done)
        PodcastAdFinder.shared.scan()
      case .paused: pause(id)
      }
    } catch let error as TranscriptError {
      switch error {
      case .notSupported(let reason):
        try? files.saveSkip(TranscriptSkip(reason: reason, locale: locale))
        set(id, .notSupported(reason: reason))
      case .failed(let reason):
        set(id, .failed(reason: reason))
      }
    } catch is CancellationError {
      pause(id)
    } catch {
      if downloads.entry(for: id) == nil { return removed(id) }
      set(id, .failed(reason: "Transcribing stopped: \(error.localizedDescription)"))
    }
  }

  /// Back to the front of the queue, with its partial file saved; its download may be gone.
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

enum TranscriptJSON {
  /// What the app receives for an episode's transcript.
  static func object(_ id: String, _ status: TranscriptStatus) -> [String: Any] {
    switch status {
    case .waiting: return ["episodeId": id, "state": "waiting"]
    case .transcribing(let percent):
      return ["episodeId": id, "state": "transcribing", "percent": percent]
    case .done: return ["episodeId": id, "state": "done"]
    case .notSupported(let reason): return ["episodeId": id, "state": "unsupported", "reason": reason]
    case .failed(let reason): return ["episodeId": id, "state": "failed", "reason": reason]
    }
  }
}
