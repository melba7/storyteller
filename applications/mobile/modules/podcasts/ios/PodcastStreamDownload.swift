// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Plays an episode from its own download while the bytes arrive. Ads are found only in the
// exact file that was downloaded (ads inserted on the fly differ between requests), so a
// separate stream can never be skipped; this makes the player listen to the file that is then
// saved, transcribed and checked for ads.
//
// The player's asset has a made-up address (see StreamScheme), so AVFoundation asks this class
// for the bytes. One foreground data task fetches the episode and appends to a staging file;
// each request for a byte range is answered from that file, and a request for bytes that are
// not there yet waits until they are (the download is far faster than playback). The Downloads
// list shows the episode as a manual download with its progress. When the task ends the file
// is hashed and filed like any finished download and the transcriber is told. The player keeps
// reading from the same open file handle after the file is moved into place (a rename on the
// same volume keeps the handle valid), so playback never switches files.
//
// Everything below runs on `queue`: AVFoundation's delegate calls and the data task's callbacks.
// The rules (what can be answered, the type, the made-up address) are PodcastDownloads' StreamRules.
//
// A dropped connection is carried on with a Range request that proves it is the same file
// (PodcastStreamDownload+Resume.swift), and an app that goes to the background keeps running
// until the download ends. A server that cannot be fetched this way (it refuses, or sends no
// length) is not an error for the listener: the player plays the plain address instead.

import AVFoundation
import Foundation
import PodcastDownloads
import UIKit

final class PodcastStreamDownload: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate,
  @unchecked Sendable
{
  /// The most bytes handed to the player in one piece.
  static let chunk: Int64 = 1 << 20
  /// The most bytes handed to one request in one turn of the queue. The rest follows in the
  /// next turn, so a request the player cancels (it has enough) is seen between turns and a
  /// whole file is never pushed at once.
  static let perTurn: Int64 = 4 << 20

  let queue = DispatchQueue(label: "PodcastStreamDownload")
  /// The address AVFoundation is given, which comes back to this class.
  let assetURL: URL
  let episodeId: String
  private let enclosureType: String
  private let fileExtension: String
  private let store: DownloadStore
  /// The episode's own address, as the feed gives it.
  let originalURL: URL
  var address: URL
  private var plainURL: URL?

  var session: URLSession?
  var task: URLSessionDataTask?
  private var stagedURL: URL?
  private var writer: FileHandle?
  var reader: FileHandle?
  var available: Int64 = 0
  var expected: Int64?
  var contentType: String?
  private var throttle = ProgressThrottle()
  var pending: [AVAssetResourceLoadingRequest] = []
  private var started = false
  /// The address after redirects, the validator of the first response and how often in a row
  /// the download was carried on (see PodcastStreamDownload+Resume.swift).
  var finalURL: URL?
  var validator: String?
  var resumes = 0
  /// How many times in a row the network was missing when a resume was due.
  var waits = 0
  var resuming = false
  /// Told when playing from this download is given up and the plain address should play.
  var onFallback: (@Sendable (StreamFallback) -> Void)?
  let backgroundLock = NSLock()
  var backgroundTask = UIBackgroundTaskIdentifier.invalid
  private let shaLock = NSLock()
  /// Checks the first minutes for ads while the rest downloads (PodcastStreamHead.swift).
  let head: PodcastStreamHead
  private var filed: String?
  var serveScheduled = false
  var stopped = false
  /// The data task is over, one way or the other.
  var ended = false
  /// The task finished without error: the file is whole and is being filed.
  var completed = false
  var failure: Error?

  /// Nil when downloads are not available or the episode cannot be played this way.
  init?(episodeId: String, url: URL, type: String) {
    guard let store = PodcastDownloader.shared.store, DownloadFile.isSafeEpisodeId(episodeId)
    else { return nil }
    let upgraded = url.upgradedToHTTPS
    guard let custom = StreamScheme.customURL(for: upgraded) else { return nil }
    self.store = store
    self.episodeId = episodeId
    self.head = PodcastStreamHead(episodeId: episodeId, store: store)
    self.originalURL = url
    self.enclosureType = type
    self.fileExtension = DownloadFile.fileExtension(type: type, url: upgraded)
    self.address = upgraded
    self.plainURL = url.scheme?.lowercased() == "http" ? url : nil
    self.assetURL = custom
    super.init()
  }

  /// The asset for the player item, with this class as its loader.
  func makeAsset() -> AVURLAsset {
    let asset = AVURLAsset(url: assetURL)
    asset.resourceLoader.setDelegate(self, queue: queue)
    return asset
  }

  /// The hash of the file this download filed, once it has. The ads of a filed download are the
  /// player's only when this is the file it hears.
  var filedSha: String? { shaLock.withLock { filed } }

  /// Starts fetching. Call it before the player is given the asset.
  @MainActor
  func start() {
    PodcastTimeline.tap(episodeId)
    holdBackground()
    // The downloader keeps its own clean-up and any second download away from this episode,
    // and calls this when the listener removes the download.
    PodcastDownloader.shared.registerPlayThrough(episodeId) { [weak self] in
      self?.requestFallback(.removed)
    }
    queue.async { self.begin() }
  }

  /// Another episode is starting. A download that is not whole is dropped (its entry, staging
  /// file and task), so no half file is left; a finished one stays as it is. Waits for the
  /// queue, so a new loader for the same episode never meets the old one's clean-up.
  func stop() {
    queue.sync {
      guard !stopped else { return }
      stopped = true
      head.stop()
      PodcastDownloader.shared.unregisterPlayThrough(episodeId)
      releaseBackground()
      task?.cancel()
      session?.invalidateAndCancel()
      task = nil
      session = nil
      let gone = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
      for request in pending where !request.isFinished { request.finishLoading(with: gone) }
      pending = []
      try? writer?.close()
      try? reader?.close()
      writer = nil
      reader = nil
      guard started, !completed else { return }
      if let staged = stagedURL { try? FileManager.default.removeItem(at: staged) }
      // Only this loader's own entry: a download of the background session is not touched.
      if let entry = store.entry(for: episodeId), entry.state.isActive, entry.playThrough {
        _ = try? store.delete(episodeId: episodeId)
        PodcastDownloader.shared.emitRemoved(episodeId)
        PodcastTranscriber.shared.removed(episodeId)
      }
    }
  }

  // MARK: Fetching

  private func begin() {
    guard !started, !stopped else { return }
    started = true
    do {
      let staged = try store.newStagingFile(episodeId: episodeId)
      stagedURL = staged
      head.begin(staged: staged)
      writer = try FileHandle(forWritingTo: staged)
      reader = try FileHandle(forReadingFrom: staged)
      let entry = DownloadEntry(
        episodeId: episodeId, url: address.absoluteString, fileExtension: fileExtension,
        state: .downloading(bytes: 0, expected: nil), automatic: false,
        plainURL: plainURL?.absoluteString, playThrough: true)
      try store.put(entry)
      PodcastDownloader.shared.emit(entry)
    } catch {
      return failed(DownloadFailure(diskFull: DownloadFailure.isDiskFull(error)))
    }
    fetch()
  }

  /// One foreground data task for the current address. Wi-Fi only is read now, as for a
  /// download the listener asked for.
  private func fetch() {
    let request = makeRequest(for: address)
    let config = URLSessionConfiguration.default
    config.urlCache = nil
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    // A request made with no network waits for it instead of failing at once.
    config.waitsForConnectivity = true
    config.timeoutIntervalForResource = 6 * 60 * 60
    let operations = OperationQueue()
    operations.maxConcurrentOperationCount = 1
    operations.underlyingQueue = queue
    let made = URLSession(configuration: config, delegate: self, delegateQueue: operations)
    session = made
    let fetching = made.dataTask(with: request)
    task = fetching
    fetching.resume()
  }

  /// No network: before the first byte the player plays the plain address instead, which says
  /// at once that it couldn't be played. After bytes arrived the wait goes on for a resume.
  func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
    guard StreamResume.givesUpWaiting(available: available), !stopped, onFallback != nil else {
      return
    }
    giveUp(.noFirstByte)
  }

  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard !stopped, !ended, dataTask === task else { return completionHandler(.cancel) }
    let http = response as? HTTPURLResponse
    if resuming { return answerResume(http, completionHandler) }
    if let status = http?.statusCode, !(200..<300).contains(status) {
      completionHandler(.cancel)
      return failed(DownloadFailure(httpStatus: status))
    }
    // A length that is for the compressed bytes says nothing about the file.
    let encoded = http?.value(forHTTPHeaderField: "Content-Encoding").map { $0 != "identity" } ?? false
    if response.expectedContentLength > 0, !encoded { expected = response.expectedContentLength }
    // Without a length the player would wait for the whole file before a sound is heard.
    guard expected != nil else {
      completionHandler(.cancel)
      return giveUp(.noLength)
    }
    finalURL = http?.url
    validator = StreamResume.validator(
      etag: http?.value(forHTTPHeaderField: "ETag"),
      lastModified: http?.value(forHTTPHeaderField: "Last-Modified"))
    contentType = StreamContentType.uti(
      responseType: response.mimeType, enclosureType: enclosureType, url: address)
    completionHandler(.allow)
    if let entry = store.updateProgress(episodeId: episodeId, bytes: available, expected: expected) {
      PodcastDownloader.shared.emit(entry)
    }
    serve()
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard !stopped, !ended, dataTask === task, let writer else { return }
    do {
      try writer.write(contentsOf: data)
    } catch {
      return failed(DownloadFailure(diskFull: DownloadFailure.isDiskFull(error)))
    }
    available += Int64(data.count)
    head.noteBytes(available)
    resumes = 0
    waits = 0
    if throttle.shouldReport(bytes: available, expected: expected, at: Date()),
      let entry = store.updateProgress(episodeId: episodeId, bytes: available, expected: expected)
    {
      PodcastDownloader.shared.emit(entry)
    }
    serve()
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    // A task that was replaced (the plain http try) still reports; it is not this one.
    guard !stopped, !ended, task === self.task else { return }
    if let error {
      let failure = DownloadFailure(
        error: error, response: task.response, attempts: DownloadRecovery.maxRetries)
      // A dropped connection is carried on only with a request that proves the bytes after it
      // are the same file (ads inserted on the fly differ between requests).
      if StreamResume.shouldResume(
          failure, available: available, validator: validator, resumes: resumes, waits: waits)
      {
        return scheduleResume(for: failure)
      }
      return failed(failure)
    }
    guard available > 0 else { return failed(DownloadFailure()) }
    complete()
  }

  /// The whole file is there: the end of the file is now known, so requests to the end finish,
  /// then it is hashed and filed like a finished download.
  private func complete() {
    ended = true
    completed = true
    expected = available
    head.noteBytes(available)
    head.noMoreBytes()
    try? writer?.close()
    writer = nil
    session?.finishTasksAndInvalidate()
    session = nil
    serve()
    guard let staged = stagedURL else { return }
    let (store, id, ext) = (self.store, episodeId, fileExtension)
    // Off the player's queue, so hashing a long episode does not hold up a request.
    DispatchQueue.global(qos: .utility).async {
      defer {
        PodcastDownloader.shared.unregisterPlayThrough(id)
        self.releaseBackground()
      }
      do {
        let done = try store.installStaged(staged, episodeId: id, fileExtension: ext)
        if case .downloaded(_, let sha, _, _) = done.state {
          self.noteFiled(sha)
          self.head.filed(sha: sha, file: store.localFile(for: id))
        }
        PodcastDownloader.shared.emit(done)
        // The head scan may still be at work on the same first minutes: its analyzer and model
        // session go first, and the transcriber starts when the scan ends (or after 90 seconds).
        self.head.afterScan(timeout: 90) { PodcastTranscriber.shared.downloaded(id) }
      } catch DownloadError.noEntry {
        // Removed by the listener while it was being filed: nothing is brought back.
      } catch {
        let full = DownloadFailure.isDiskFull(error)
        let reason = DownloadRecovery.reason(
          for: DownloadFailure(diskFull: full, attempts: DownloadRecovery.maxRetries))
        if let entry = try? store.markFailed(episodeId: id, reason: reason) {
          PodcastDownloader.shared.emit(entry)
        }
      }
    }
  }

  /// The task failed. An address that was upgraded from http gets its own http address once,
  /// when nothing has arrived. Otherwise the row says why, and requests for bytes that never
  /// came fail with that reason.
  func failed(_ failure: DownloadFailure) {
    task?.cancel()
    if DownloadRecovery.shouldFallBackToPlainHTTP(failure, plainURL: plainURL?.absoluteString),
      available == 0, let plain = plainURL
    {
      session?.invalidateAndCancel()
      if var entry = store.entry(for: episodeId) {
        entry.fallBackToPlainHTTP()
        entry.updatedAt = Date()
        try? store.put(entry)
      }
      address = plain
      plainURL = nil
      return fetch()
    }
    // Nothing arrived, so nothing is lost by playing the plain address instead.
    if available == 0, !stopped, onFallback != nil { return giveUp(.noFirstByte) }
    ended = true
    head.stop()
    PodcastDownloader.shared.unregisterPlayThrough(episodeId)
    releaseBackground()
    let reason = DownloadRecovery.reason(for: failure)
    self.failure = PodcastFetchError(message: reason)
    try? writer?.close()
    writer = nil
    session?.invalidateAndCancel()
    session = nil
    if let entry = try? store.markFailed(episodeId: episodeId, reason: reason) {
      PodcastDownloader.shared.emit(entry)
    }
    serve()
  }
}

extension PodcastStreamDownload {
  func noteFiled(_ sha256: String) { shaLock.withLock { filed = sha256 } }
}
