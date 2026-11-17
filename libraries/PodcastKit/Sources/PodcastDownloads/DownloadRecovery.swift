// LOFI-FORK: what to do when a download stops with an error (see FORK.md).
import Foundation

/// What a stopped download looked like, as plain numbers and flags the caller reads from the
/// URLSession error, so the rule below needs no URLSession.
public struct DownloadFailure: Sendable, Equatable {
  /// `URLError.Code.rawValue`, when the error was a URLError.
  public var urlErrorCode: Int?
  /// The server's status, when it answered.
  public var httpStatus: Int?
  /// The error carried resume data (`URLError.downloadTaskResumeData`).
  public var hasResumeData: Bool
  /// `URLError.backgroundTaskCancelledReason` was `.userForceQuitApplication`: the listener
  /// swiped the app away and iOS stopped the transfer.
  public var forceQuit: Bool
  /// The phone had no room for the file.
  public var diskFull: Bool
  /// How many times this download has already been retried after a dropped connection.
  public var attempts: Int

  public init(
    urlErrorCode: Int? = nil, httpStatus: Int? = nil, hasResumeData: Bool = false,
    forceQuit: Bool = false, diskFull: Bool = false, attempts: Int = 0
  ) {
    self.urlErrorCode = urlErrorCode
    self.httpStatus = httpStatus
    self.hasResumeData = hasResumeData
    self.forceQuit = forceQuit
    self.diskFull = diskFull
    self.attempts = attempts
  }
}

public enum RecoveryAction: Sendable, Equatable {
  /// Carry on with `downloadTask(withResumeData:)`.
  case resume
  /// Start again from the address.
  case restart
  /// Give up, with a short reason for the episode's row.
  case fail(String)
}

public enum DownloadRecovery {
  /// A dropped connection is retried this many times before the row says it failed.
  public static let maxRetries = 3

  /// URLError codes for a connection that may come back: timed out, cannot connect, lost,
  /// no internet, DNS trouble.
  private static let transient: Set<Int> = [-1001, -1003, -1004, -1005, -1006, -1009]

  /// URLError codes for an https address that could not be reached or trusted: secure
  /// connection failed, the server certificate was bad, dated, untrusted or from an unknown
  /// root, cannot find or connect to the host.
  private static let httpsUnreachable: Set<Int> = [-1200, -1201, -1202, -1203, -1204, -1003, -1004]

  /// Whether a download that was upgraded from plain http should try the original http
  /// address, because https could not connect or its certificate was refused. The server
  /// answering anything, or the user or the phone stopping the download, never counts.
  public static func shouldFallBackToPlainHTTP(_ failure: DownloadFailure, plainURL: String?)
    -> Bool
  {
    guard plainURL != nil, failure.httpStatus == nil, !failure.forceQuit, !failure.diskFull,
      let code = failure.urlErrorCode
    else { return false }
    return httpsUnreachable.contains(code)
  }

  /// Whether to resume, start again or give up. A swipe-away always carries on (resuming
  /// when iOS left resume data), and the state stays "downloading" meanwhile. Real errors,
  /// such as the server saying 404 or a full phone, fail with a reason the listener can read.
  public static func decide(_ failure: DownloadFailure) -> RecoveryAction {
    if failure.forceQuit { return failure.hasResumeData ? .resume : .restart }
    if failure.diskFull { return .fail("The phone is full") }
    if let status = failure.httpStatus, !(200..<300).contains(status) {
      if status == 404 || status == 410 { return .fail("The episode is no longer there (\(status))") }
      return .fail("The server answered \(status)")
    }
    // -1022: App Transport Security refused a plain http address.
    if failure.urlErrorCode == -1022 {
      return .fail("The episode's link is plain http, which iOS blocks")
    }
    if let code = failure.urlErrorCode, transient.contains(code) {
      guard failure.attempts < maxRetries else { return .fail("No connection, tap to try again") }
      return failure.hasResumeData ? .resume : .restart
    }
    return .fail("The download failed, tap to try again")
  }
}
