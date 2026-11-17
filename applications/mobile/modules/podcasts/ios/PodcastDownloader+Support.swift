// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Small pieces of the downloader: the Wi-Fi only setting, how a URLSession error reads as a
// DownloadFailure, and how a download becomes the object the app receives.
import Foundation
import PodcastDownloads

/// The listener's download settings, kept in UserDefaults so Swift code that runs with the
/// app closed (the downloader, later the automatic downloads) can read them too.
enum DownloadSettings {
  private static let wifiOnlyKey = "podcasts.downloads.wifiOnly"

  /// Off until the listener turns it on. With it on, a download started on mobile data waits
  /// for Wi-Fi without saying so, which would look like a download that does nothing.
  static var wifiOnly: Bool {
    get { UserDefaults.standard.object(forKey: wifiOnlyKey) as? Bool ?? false }
    set { UserDefaults.standard.set(newValue, forKey: wifiOnlyKey) }
  }
}

extension DownloadFailure {
  /// Reads what the rule needs from a URLSession error and the server's answer, if any.
  init(error: Error, response: URLResponse?, attempts: Int) {
    let urlError = error as? URLError
    self.init(
      urlErrorCode: urlError?.errorCode,
      httpStatus: (response as? HTTPURLResponse)?.statusCode,
      hasResumeData: urlError?.downloadTaskResumeData != nil,
      forceQuit: urlError?.backgroundTaskCancelledReason == .userForceQuitApplication,
      diskFull: Self.isDiskFull(error),
      attempts: attempts)
  }

  /// A full phone shows up as a Cocoa "out of space" error or POSIX ENOSPC, sometimes inside
  /// another error.
  static func isDiskFull(_ error: Error) -> Bool {
    var current: NSError? = error as NSError
    while let found = current {
      if found.domain == NSCocoaErrorDomain && found.code == NSFileWriteOutOfSpaceError { return true }
      if found.domain == NSPOSIXErrorDomain && found.code == Int(ENOSPC) { return true }
      current = found.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    return false
  }
}

enum DownloadJSON {
  /// What the app receives for an episode's download: its state and the numbers that go with it.
  static func object(_ entry: DownloadEntry) -> [String: Any] {
    var object: [String: Any] = [
      "episodeId": entry.episodeId,
      "updatedAt": entry.updatedAt.timeIntervalSince1970 * 1000,
      "automatic": entry.automatic,
    ]
    switch entry.state {
    case .queued:
      object["state"] = "queued"
    case .downloading(let bytes, let expected):
      object["state"] = "downloading"
      object["bytes"] = Double(bytes)
      if let expected { object["expected"] = Double(expected) }
    case .downloaded(let file, let sha256, let bytes, let date):
      object["state"] = "downloaded"
      object["file"] = file
      object["sha256"] = sha256
      object["bytes"] = Double(bytes)
      object["date"] = date.timeIntervalSince1970 * 1000
    case .failed(let reason):
      object["state"] = "failed"
      object["reason"] = reason
    }
    return object
  }
}
