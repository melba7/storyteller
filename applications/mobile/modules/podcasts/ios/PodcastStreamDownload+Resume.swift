// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// PodcastStreamDownload's side for a download that has to carry on or give up: asking for the
// rest of the file after a dropped connection (only a 206 that starts where the file on disk
// ends, for the same ETag or Last-Modified, is used), keeping the app running while the bytes
// arrive with the screen locked, and telling the player to play the plain address when this
// way of playing does not work. Runs on the loader's queue, like the rest of the class.

import Foundation
import PodcastDownloads
import UIKit

/// Why playing from the download is given up for the episode's plain address.
enum StreamFallback: Sendable {
  /// The server refused or failed before the first byte.
  case noFirstByte
  /// The server sends no length, so playing would wait for the whole file. The player also
  /// starts an ordinary download, so the ads can still be found.
  case noLength
  /// The listener removed the download while it was arriving.
  case removed
}

extension PodcastStreamDownload {
  // MARK: Requests

  /// A request for `url` that follows the Wi-Fi only setting as it is now.
  func makeRequest(for url: URL) -> URLRequest {
    var request = URLRequest(url: url)
    let wifiOnly = NetworkPolicy.wifiOnly(automatic: false, setting: DownloadSettings.wifiOnly)
    request.allowsCellularAccess = !wifiOnly
    request.allowsExpensiveNetworkAccess = !wifiOnly
    return request
  }

  // MARK: Carrying on

  /// The connection dropped with part of the file on disk: asks again a little later.
  func scheduleResume() {
    let wait = StreamResume.delay(afterResumes: resumes)
    resumes += 1
    task = nil
    queue.asyncAfter(deadline: .now() + wait) { [weak self] in self?.resume() }
  }

  /// Asks for the bytes after the ones on disk, from the address the first request ended at.
  private func resume() {
    guard !stopped, !ended, let session, let validator else { return }
    var request = makeRequest(for: finalURL ?? address)
    for (name, value) in StreamResume.headers(available: available, validator: validator) {
      request.setValue(value, forHTTPHeaderField: name)
    }
    resuming = true
    let again = session.dataTask(with: request)
    task = again
    again.resume()
  }

  /// The answer to a resuming request. Only the rest of the same file is used; anything else
  /// (the whole file again, another start) fails the download as it would have.
  func answerResume(
    _ http: HTTPURLResponse?, _ completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard
      StreamResume.accepts(
        status: http?.statusCode ?? 0, contentRange: http?.value(forHTTPHeaderField: "Content-Range"),
        available: available)
    else {
      completionHandler(.cancel)
      return failed(DownloadFailure())
    }
    resuming = false
    completionHandler(.allow)
  }

  // MARK: Giving up streaming

  /// Playing from this download does not work: the player plays the plain address. Whatever is
  /// waiting for bytes is finished when the player stops this loader.
  func giveUp(_ reason: StreamFallback) {
    guard !ended, !stopped else { return }
    ended = true
    task?.cancel()
    session?.invalidateAndCancel()
    task = nil
    session = nil
    PodcastDownloader.shared.unregisterPlayThrough(episodeId)
    releaseBackground()
    onFallback?(reason)
  }

  /// The downloader's call when the listener removes the download while it arrives.
  func requestFallback(_ reason: StreamFallback) {
    queue.async {
      // Already over (filed, failed or given up): the player knows, or the file is whole.
      guard !self.stopped, !self.completed, !self.ended else { return }
      self.giveUp(reason)
    }
  }

  // MARK: The app stays awake

  /// Keeps the app running for a while when it goes to the background, so a download that is
  /// not whole yet carries on with the screen locked.
  @MainActor
  func holdBackground() {
    backgroundLock.withLock {
      guard backgroundTask == .invalid else { return }
      backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PodcastStreamDownload") {
        [weak self] in
        self?.releaseBackground()
      }
    }
  }

  /// Ends the background task, once. Safe from any queue.
  func releaseBackground() {
    let id = backgroundLock.withLock { () -> UIBackgroundTaskIdentifier in
      defer { backgroundTask = .invalid }
      return backgroundTask
    }
    guard id != .invalid else { return }
    DispatchQueue.main.async { UIApplication.shared.endBackgroundTask(id) }
  }
}
