// LOFI-FORK: the podcast downloads' rules as plain values (see FORK.md).
import Foundation

/// Names of folders and files, and which ids and extensions are allowed in them.
public enum DownloadFile {
  /// Episode ids are UUIDs. Anything that could climb out of the folder (a slash, dots, an
  /// empty name) is refused, so only letters, digits, "-" and "_" pass.
  public static func isSafeEpisodeId(_ id: String) -> Bool {
    guard !id.isEmpty, id.utf8.count <= 100 else { return false }
    return id.unicodeScalars.allSatisfy { scalar in
      (scalar.value < 128)
        && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_")
    }
  }

  public static func isSha256(_ text: String) -> Bool {
    text.utf8.count == 64 && text.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }
  }

  public static func isSafeExtension(_ ext: String) -> Bool {
    (1...5).contains(ext.utf8.count)
      && ext.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) }
  }

  /// `<sha256>.<ext>`.
  public static func name(sha256: String, fileExtension: String) -> String {
    "\(sha256).\(fileExtension)"
  }

  private static let byType: [String: String] = [
    "audio/mpeg": "mp3", "audio/mp3": "mp3", "audio/mpeg3": "mp3", "audio/x-mpeg": "mp3",
    "audio/x-mp3": "mp3", "audio/mp4": "m4a", "audio/x-m4a": "m4a", "audio/m4a": "m4a",
    "audio/x-mp4": "m4a", "video/mp4": "mp4", "audio/aac": "aac", "audio/x-aac": "aac",
    "audio/ogg": "ogg", "audio/opus": "opus", "audio/wav": "wav", "audio/x-wav": "wav",
    "audio/wave": "wav", "audio/flac": "flac", "audio/x-flac": "flac", "audio/aiff": "aiff",
    "audio/x-aiff": "aiff", "audio/webm": "webm", "audio/x-m4b": "m4b",
  ]

  private static let known: Set<String> = [
    "mp3", "m4a", "m4b", "mp4", "aac", "ogg", "opus", "wav", "flac", "aif", "aiff", "webm", "caf",
  ]

  /// The extension for a MIME type this app knows, ignoring case and any parameters.
  public static func knownExtension(forType type: String?) -> String? {
    guard let kind = (type ?? "").split(separator: ";").first.map({
      $0.trimmingCharacters(in: .whitespaces).lowercased()
    }) else { return nil }
    return byType[kind]
  }

  /// The file extension for an episode: from the enclosure's type, else from the address's
  /// path, else "mp3" (by far the most common).
  public static func fileExtension(type: String?, url: URL?) -> String {
    if let ext = knownExtension(forType: type) { return ext }
    if let ext = url?.pathExtension.lowercased(), known.contains(ext) { return ext }
    return "mp3"
  }
}

public enum NetworkPolicy {
  /// Whether a download may only use Wi-Fi. The app's own downloads of new episodes always
  /// wait for Wi-Fi; the listener's follow the "Download only on Wi-Fi" switch.
  public static func wifiOnly(automatic: Bool, setting: Bool) -> Bool { automatic || setting }
}

/// What to do with an index entry when the app starts again.
public enum RelaunchAction: Sendable, Equatable {
  case keep
  /// Start the download again from the beginning.
  case restart
  case fail(String)
  /// Forget it, with its folder: a download the player fed as the episode played, which the
  /// listener never asked for and which is no use unfinished.
  case drop
}

public enum Relaunch {
  public static let stoppedReason = "Stopped, tap to try again"

  /// The rule for one entry. `taskIsAlive` says whether the URLSession still has a task for
  /// it. Finished and failed entries stay as they are, and so do active ones with a task. A
  /// download that was moving but lost its task (the listener force-quit the app, which
  /// cancels background downloads) is marked failed, so a phone on mobile data does not
  /// start a big download by itself. One that was only queued has lost nothing, so it
  /// restarts. An unfinished play-through download is dropped when the player is not feeding
  /// it (`taskIsAlive` is then false); the player registers itself, so one that is still
  /// playing is kept.
  public static func action(for state: DownloadState, taskIsAlive: Bool, playThrough: Bool = false)
    -> RelaunchAction
  {
    if playThrough, state.isActive { return taskIsAlive ? .keep : .drop }
    switch state {
    case .downloaded, .failed: return .keep
    case .queued: return taskIsAlive ? .keep : .restart
    case .downloading: return taskIsAlive ? .keep : .fail(stoppedReason)
    }
  }

  /// The action for every entry, by episode id.
  public static func plan(entries: [DownloadEntry], liveEpisodeIds: Set<String>)
    -> [String: RelaunchAction]
  {
    var actions: [String: RelaunchAction] = [:]
    for entry in entries {
      actions[entry.episodeId] = action(
        for: entry.state, taskIsAlive: liveEpisodeIds.contains(entry.episodeId),
        playThrough: entry.playThrough)
    }
    return actions
  }
}

/// Decides when a progress report goes to the app: at most every half second, or sooner
/// when the download moved by 1% of its size.
public struct ProgressThrottle: Sendable {
  public let minimumInterval: TimeInterval
  public let minimumFraction: Double
  private var lastTime: Date?
  private var lastFraction: Double?

  public init(minimumInterval: TimeInterval = 0.5, minimumFraction: Double = 0.01) {
    self.minimumInterval = minimumInterval
    self.minimumFraction = minimumFraction
  }

  /// True when this reading should be reported (and then counts as the last one reported).
  public mutating func shouldReport(bytes: Int64, expected: Int64?, at now: Date) -> Bool {
    var fraction: Double?
    if let expected, expected > 0 { fraction = min(1, Double(bytes) / Double(expected)) }
    if let lastTime {
      let waited = now.timeIntervalSince(lastTime) >= minimumInterval
      var moved = false
      if let fraction, let lastFraction { moved = fraction - lastFraction >= minimumFraction }
      guard waited || moved else { return false }
    }
    lastTime = now
    lastFraction = fraction
    return true
  }
}
