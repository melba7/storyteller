// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Downloads episodes with one background URLSession, so they carry on with the app closed.
// Closed has two meanings. Left, locked or ended by iOS while suspended: the session keeps
// going, and iOS may start the app in the background only to hand over the finished files,
// before any JavaScript runs; so the session is made at launch (PodcastsAppDelegateSubscriber)
// and each finished file is moved, hashed and filed here in Swift, with the index written
// before iOS is told the events are done. Swiped away in the app switcher: iOS stops the
// transfers and does not wake the app, so after a swipe-away the downloads continue the next
// time the app opens, because iOS stops them until then. They finish with an error that
// carries resume data, and DownloadRecovery decides to resume them, start again, or fail.
//
// The files and the index are PodcastDownloads' DownloadStore; the rules (what to do after
// a restart, after an error, how often to report progress) are plain values in that package.

import Foundation
import PodcastDownloads

final class PodcastDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  static let shared = PodcastDownloader()

  /// The same identifier every launch, so iOS can hand a relaunched app its old downloads.
  static var identifier: String {
    (Bundle.main.bundleIdentifier ?? "storyteller-lofi") + ".podcastDownloads"
  }

  /// How long after launch to wait for iOS to hand over what finished while the app was
  /// closed, before downloads that lost their task are marked failed.
  private static let settleSeconds = 5.0

  let store: DownloadStore?
  private let lock = NSLock()
  private let queue = OperationQueue()
  private var session: URLSession?
  private var sink: ((String, [String: Any]) -> Void)?
  /// Episodes that have a task in this session.
  private var active = Set<String>()
  private var throttles: [Int: ProgressThrottle] = [:]
  private var retries: [String: Int] = [:]
  private var backgroundCompletion: (() -> Void)?

  private override init() {
    queue.maxConcurrentOperationCount = 1
    queue.name = "PodcastDownloader"
    var root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Podcasts", isDirectory: true)
    do {
      store = try DownloadStore(root: root)
      // Episodes can be fetched again, so they stay out of the phone's backup.
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? root.setResourceValues(values)
    } catch {
      NSLog("Podcasts: the downloads folder could not be opened: \(error)")
      store = nil
    }
    super.init()
  }

  /// Where events go: the module's `sendEvent`. Nothing is sent until the module is up.
  func setSink(_ sink: ((String, [String: Any]) -> Void)?) {
    lock.withLock { self.sink = sink }
  }

  // MARK: Starting

  /// Makes the session and takes stock of it. Called from the app delegate while the app
  /// launches, so a background relaunch gets its finished files without JavaScript.
  func start() {
    let made: URLSession? = lock.withLock {
      guard session == nil, store != nil else { return nil }
      let config = URLSessionConfiguration.background(withIdentifier: Self.identifier)
      config.sessionSendsLaunchEvents = true
      config.isDiscretionary = false
      let made = URLSession(configuration: config, delegate: self, delegateQueue: queue)
      session = made
      return made
    }
    guard let made else { return }
    made.getAllTasks { [weak self] tasks in
      guard let self else { return }
      let live = tasks.filter { $0.state == .running || $0.state == .suspended }
      self.lock.withLock { self.active.formUnion(live.compactMap(\.taskDescription)) }
      DispatchQueue.global().asyncAfter(deadline: .now() + Self.settleSeconds) { self.settle() }
    }
  }

  /// Applies the restart rule: downloads that lost their task fail, queued ones start again.
  private func settle() {
    guard let store else { return }
    let live = lock.withLock { active }
    let before = store.entries()
    guard let restart = try? store.reconcile(liveEpisodeIds: live) else { return }
    for entry in before {
      if let now = store.entry(for: entry.episodeId), now.state != entry.state { emit(now) }
    }
    for entry in restart { begin(entry) }
  }

  /// iOS woke the app for this session's events: keep the handler until they are all handled.
  func attach(identifier: String, completionHandler: @escaping () -> Void) {
    guard identifier == Self.identifier else { return completionHandler() }
    // Kept before the session can finish its events, so the handler is never missed.
    lock.withLock { backgroundCompletion = completionHandler }
    start()
  }

  // MARK: Asking

  func download(episodeId: String, url: String, type: String) throws {
    guard let store else { throw PodcastFetchError(message: "Downloads are not available.") }
    _ = try store.folder(for: episodeId)
    guard let address = URL(string: url), let scheme = address.scheme?.lowercased(),
      scheme == "http" || scheme == "https", address.host != nil
    else { throw PodcastFetchError(message: "This episode has no downloadable link.") }
    if let existing = store.entry(for: episodeId) {
      if existing.state.isActive, lock.withLock({ active.contains(episodeId) }) { return }
      if case .downloaded = existing.state, store.localFile(for: episodeId) != nil { return }
    }
    start()
    lock.withLock { retries[episodeId] = nil }
    let entry = DownloadEntry(
      episodeId: episodeId, url: address.absoluteString,
      fileExtension: DownloadFile.fileExtension(type: type, url: address), state: .queued)
    try store.put(entry)
    emit(entry)
    begin(entry)
  }

  /// Stops an unfinished download and forgets it. A finished one is left alone.
  func cancel(episodeId: String) throws {
    guard let entry = store?.entry(for: episodeId) else { return }
    if case .downloaded = entry.state { return }
    try remove(episodeId: episodeId)
  }

  /// Stops any task for the episode and removes its folder, files and entry.
  func remove(episodeId: String) throws {
    guard let store else { return }
    _ = try store.delete(episodeId: episodeId)
    lock.withLock { active.remove(episodeId); retries[episodeId] = nil }
    session?.getAllTasks { tasks in
      for task in tasks where task.taskDescription == episodeId { task.cancel() }
    }
    emitRemoved(episodeId)
  }

  func localFile(for episodeId: String) -> URL? { store?.localFile(for: episodeId) }

  /// Begins a task for the entry's address. Wi-Fi only is read now, per request.
  private func begin(_ entry: DownloadEntry) {
    guard let address = URL(string: entry.url), let session = lock.withLock({ self.session }) else {
      return fail(entry.episodeId, "This episode has no downloadable link.")
    }
    var request = URLRequest(url: address)
    let wifiOnly = DownloadSettings.wifiOnly
    request.allowsCellularAccess = !wifiOnly
    request.allowsExpensiveNetworkAccess = !wifiOnly
    launch(session.downloadTask(with: request), for: entry.episodeId)
  }

  private func launch(_ task: URLSessionDownloadTask, for episodeId: String) {
    task.taskDescription = episodeId
    lock.withLock { active.insert(episodeId) }
    task.resume()
  }

  // MARK: Delegate

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    guard let id = downloadTask.taskDescription, let store else { return }
    let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
    let report = lock.withLock { () -> Bool in
      var throttle = throttles[downloadTask.taskIdentifier] ?? ProgressThrottle()
      let report = throttle.shouldReport(bytes: totalBytesWritten, expected: expected, at: Date())
      throttles[downloadTask.taskIdentifier] = throttle
      return report
    }
    guard report else { return }
    let wasQueued = store.entry(for: id)?.state == .queued
    guard let entry = store.updateProgress(episodeId: id, bytes: totalBytesWritten, expected: expected)
    else { return }
    // The first reading is written to the index, so a restart sees a download that was moving.
    if wasQueued { try? store.put(entry) }
    emit(entry)
  }

  /// The temporary file is deleted when this method returns, so it is moved at once. Hashing
  /// and filing happen here too, and the index is written before iOS hears the events are done.
  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
  ) {
    guard let id = downloadTask.taskDescription, let store else { return }
    let status = (downloadTask.response as? HTTPURLResponse)?.statusCode
    guard let entry = store.entry(for: id) else {
      // Cancelled or deleted while it finished.
      try? FileManager.default.removeItem(at: location)
      return
    }
    if let status, !(200..<300).contains(status) {
      return recover(id, DownloadFailure(httpStatus: status))
    }
    do {
      let staged = try store.stage(location, episodeId: id)
      let hash: String
      let bytes: Int64
      do {
        hash = try FileHash.sha256(of: staged)
        bytes = (try FileManager.default.attributesOfItem(atPath: staged.path)[.size] as? Int64) ?? 0
      } catch {
        try? FileManager.default.removeItem(at: staged)
        throw error
      }
      let done = try store.install(
        episodeId: id, staged: staged, sha256: hash, fileExtension: entry.fileExtension, bytes: bytes)
      finished(id, taskIdentifier: downloadTask.taskIdentifier)
      emit(done)
    } catch {
      let full = DownloadFailure.isDiskFull(error)
      recover(id, DownloadFailure(diskFull: full, attempts: DownloadRecovery.maxRetries))
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    lock.withLock { _ = throttles.removeValue(forKey: task.taskIdentifier) }
    guard let error, let id = task.taskDescription, let store else { return }
    // Removed by the listener (their cancel is an error too): nothing left to keep.
    guard store.entry(for: id) != nil else { return finished(id, taskIdentifier: task.taskIdentifier) }
    let attempts = lock.withLock { retries[id] ?? 0 }
    let failure = DownloadFailure(error: error, response: task.response, attempts: attempts)
    recover(id, failure, resumeData: failure.hasResumeData ? (error as? URLError)?.downloadTaskResumeData : nil)
  }

  /// Every event for this session has been handled and the index is written.
  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    let handler = lock.withLock { () -> (() -> Void)? in
      defer { backgroundCompletion = nil }
      return backgroundCompletion
    }
    DispatchQueue.main.async { handler?() }
  }

  // MARK: Outcomes

  /// Does what DownloadRecovery says: carry on from the resume data, start again, or fail.
  private func recover(_ id: String, _ failure: DownloadFailure, resumeData: Data? = nil) {
    guard let store, let entry = store.entry(for: id) else { return }
    switch DownloadRecovery.decide(failure) {
    case .resume:
      count(retry: failure, id)
      reactivate(entry)
      if let resumeData, let session = lock.withLock({ self.session }) {
        launch(session.downloadTask(withResumeData: resumeData), for: id)
      } else {
        begin(entry)
      }
    case .restart:
      count(retry: failure, id)
      reactivate(entry)
      begin(entry)
    case .fail(let reason):
      fail(id, reason)
    }
  }

  /// A swipe-away's error can arrive after the restart rule already marked the download
  /// failed. It is moving again, so its row says so and its progress is counted.
  private func reactivate(_ entry: DownloadEntry) {
    guard !entry.state.isActive else { return }
    var moving = entry
    moving.state = .queued
    moving.updatedAt = Date()
    try? store?.put(moving)
    emit(moving)
  }

  /// A swipe-away is not the connection's fault, so it does not use up a retry.
  private func count(retry failure: DownloadFailure, _ id: String) {
    guard !failure.forceQuit else { return }
    lock.withLock { retries[id, default: 0] += 1 }
  }

  private func fail(_ id: String, _ reason: String) {
    finished(id, taskIdentifier: nil)
    if let entry = try? store?.markFailed(episodeId: id, reason: reason) { emit(entry) }
  }

  private func finished(_ id: String, taskIdentifier: Int?) {
    lock.withLock {
      active.remove(id)
      retries[id] = nil
      if let taskIdentifier { throttles[taskIdentifier] = nil }
    }
  }

  private func emit(_ entry: DownloadEntry) {
    let send = lock.withLock { sink }
    send?("onDownloadChange", DownloadJSON.object(entry))
  }

  private func emitRemoved(_ id: String) {
    let send = lock.withLock { sink }
    send?("onDownloadChange", ["episodeId": id, "state": "none"])
  }
}
