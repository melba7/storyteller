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

import AVFoundation
import Foundation
import PodcastDownloads

final class PodcastStreamDownload: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate,
  @unchecked Sendable
{
  /// The most bytes handed to the player in one piece.
  private static let chunk: Int64 = 1 << 20

  let queue = DispatchQueue(label: "PodcastStreamDownload")
  /// The address AVFoundation is given, which comes back to this class.
  let assetURL: URL
  private let episodeId: String
  private let enclosureType: String
  private let fileExtension: String
  private let store: DownloadStore
  private var address: URL
  private var plainURL: URL?

  private var session: URLSession?
  private var task: URLSessionDataTask?
  private var stagedURL: URL?
  private var writer: FileHandle?
  private var reader: FileHandle?
  private var available: Int64 = 0
  private var expected: Int64?
  private var contentType: String?
  private var throttle = ProgressThrottle()
  private var pending: [AVAssetResourceLoadingRequest] = []
  private var started = false
  private var stopped = false
  /// The data task is over, one way or the other.
  private var ended = false
  /// The task finished without error: the file is whole and is being filed.
  private var completed = false
  private var failure: Error?

  /// Nil when downloads are not available or the episode cannot be played this way.
  init?(episodeId: String, url: URL, type: String) {
    guard let store = PodcastDownloader.shared.store, DownloadFile.isSafeEpisodeId(episodeId)
    else { return nil }
    let upgraded = url.upgradedToHTTPS
    guard let custom = StreamScheme.customURL(for: upgraded) else { return nil }
    self.store = store
    self.episodeId = episodeId
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

  /// Starts fetching. Call it before the player is given the asset.
  func start() {
    queue.async { self.begin() }
  }

  /// Another episode is starting. A download that is not whole is dropped (its entry, staging
  /// file and task), so no half file is left; a finished one stays as it is. Waits for the
  /// queue, so a new loader for the same episode never meets the old one's clean-up.
  func stop() {
    queue.sync {
      guard !stopped else { return }
      stopped = true
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
      if let entry = store.entry(for: episodeId), entry.state.isActive {
        try? PodcastDownloader.shared.remove(episodeId: episodeId)
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
      writer = try FileHandle(forWritingTo: staged)
      reader = try FileHandle(forReadingFrom: staged)
      let entry = DownloadEntry(
        episodeId: episodeId, url: address.absoluteString, fileExtension: fileExtension,
        state: .downloading(bytes: 0, expected: nil), automatic: false,
        plainURL: plainURL?.absoluteString)
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
    var request = URLRequest(url: address)
    let wifiOnly = NetworkPolicy.wifiOnly(automatic: false, setting: DownloadSettings.wifiOnly)
    request.allowsCellularAccess = !wifiOnly
    request.allowsExpensiveNetworkAccess = !wifiOnly
    let config = URLSessionConfiguration.default
    config.urlCache = nil
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    let operations = OperationQueue()
    operations.maxConcurrentOperationCount = 1
    operations.underlyingQueue = queue
    let made = URLSession(configuration: config, delegate: self, delegateQueue: operations)
    session = made
    let fetching = made.dataTask(with: request)
    task = fetching
    fetching.resume()
  }

  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard !stopped, !ended, dataTask === task else { return completionHandler(.cancel) }
    let http = response as? HTTPURLResponse
    if let status = http?.statusCode, !(200..<300).contains(status) {
      completionHandler(.cancel)
      return failed(DownloadFailure(httpStatus: status))
    }
    // A length that is for the compressed bytes says nothing about the file.
    let encoded = http?.value(forHTTPHeaderField: "Content-Encoding").map { $0 != "identity" } ?? false
    if response.expectedContentLength > 0, !encoded { expected = response.expectedContentLength }
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
      // A dropped connection is not retried: the bytes after a new request could be another
      // file (ads inserted on the fly), which is what this exists to avoid.
      return failed(
        DownloadFailure(
          error: error, response: task.response, attempts: DownloadRecovery.maxRetries))
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
    try? writer?.close()
    writer = nil
    session?.finishTasksAndInvalidate()
    session = nil
    serve()
    guard let staged = stagedURL else { return }
    let (store, id, ext) = (self.store, episodeId, fileExtension)
    // Off the player's queue, so hashing a long episode does not hold up a request.
    DispatchQueue.global(qos: .utility).async {
      do {
        let done = try store.installStaged(staged, episodeId: id, fileExtension: ext)
        PodcastDownloader.shared.emit(done)
        PodcastTranscriber.shared.downloaded(id)
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
  private func failed(_ failure: DownloadFailure) {
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
    ended = true
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

  // MARK: Answering the player

  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
  ) -> Bool {
    guard !stopped else { return false }
    if !answer(loadingRequest) { pending.append(loadingRequest) }
    return true
  }

  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest
  ) {
    pending.removeAll { $0 === loadingRequest }
  }

  /// Answers every waiting request as far as the file allows.
  private func serve() {
    pending = pending.filter { request in
      guard !request.isCancelled, !request.isFinished else { return false }
      return !answer(request)
    }
  }

  /// Hands over what can be handed over now. True when the request is finished (done or failed).
  private func answer(_ request: AVAssetResourceLoadingRequest) -> Bool {
    if let info = request.contentInformationRequest {
      if let contentType, let expected {
        info.contentType = contentType
        info.contentLength = expected
        info.isByteRangeAccessSupported = true
      } else if let failure {
        request.finishLoading(with: failure)
        return true
      } else {
        // The length is not known yet; it is when the response says so, or the download ends.
        return false
      }
    }
    guard let data = request.dataRequest else {
      request.finishLoading()
      return true
    }
    guard let reader else {
      request.finishLoading(with: failure ?? PodcastFetchError(message: "The download was stopped."))
      return true
    }
    do {
      while true {
        let wanted: Int64? =
          data.requestsAllDataToEndOfResource
          ? nil : max(0, data.requestedOffset + Int64(data.requestedLength) - data.currentOffset)
        let slice = StreamRules.answerable(
          offset: data.currentOffset, length: wanted, available: available, expected: expected)
        if slice.length > 0 {
          try reader.seek(toOffset: UInt64(slice.offset))
          guard let bytes = try reader.read(upToCount: Int(min(slice.length, Self.chunk))),
            !bytes.isEmpty
          else { throw PodcastFetchError(message: "The downloaded part couldn't be read.") }
          data.respond(with: bytes)
          continue
        }
        if slice.complete {
          request.finishLoading()
          return true
        }
        if let failure {
          request.finishLoading(with: failure)
          return true
        }
        return false
      }
    } catch {
      request.finishLoading(with: error)
      return true
    }
  }
}
