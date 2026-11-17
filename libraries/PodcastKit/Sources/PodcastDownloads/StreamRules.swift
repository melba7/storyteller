// LOFI-FORK: playing an episode while it downloads (see FORK.md).
//
// With "Skip ads" on, an episode that is not downloaded plays from its own download as the
// bytes arrive, so what is heard is the file that is then saved, transcribed and checked for
// ads. The player asks for byte ranges; these are the rules for what can be answered from the
// file so far, what type to tell the player, and when to play this way at all. Plain values:
// AVFoundation's side is in the app's PodcastStreamDownload.
import Foundation

/// The bytes of a request that can be handed over now.
public struct StreamSlice: Sendable, Equatable {
  public var offset: Int64
  /// How many bytes, from `offset`, are on disk and asked for. Zero when there is nothing yet.
  public var length: Int64
  /// Handing these over finishes the request.
  public var complete: Bool

  public init(offset: Int64, length: Int64, complete: Bool) {
    self.offset = offset
    self.length = length
    self.complete = complete
  }
}

public enum StreamRules {
  /// What part of a request can be answered now. `offset` is where the request has got to and
  /// `length` the bytes it still wants (nil: to the end of the file). `available` is how many
  /// bytes of the file are on disk. `expected` is the file's whole length, nil while unknown;
  /// the caller sets it to `available` once the download has ended, so a request to the end
  /// then completes.
  public static func answerable(offset: Int64, length: Int64?, available: Int64, expected: Int64?)
    -> StreamSlice
  {
    let start = max(0, offset)
    var end: Int64? = expected
    if let length {
      let asked = start + max(0, length)
      end = min(asked, expected ?? asked)
    }
    let limit = min(available, end ?? available)
    let count = max(0, limit - start)
    let complete = end.map { start + count >= $0 } ?? false
    return StreamSlice(offset: start, length: count, complete: complete)
  }
}

public enum StreamContentType {
  private static let byExtension: [String: String] = [
    "mp3": "public.mp3", "m4a": "com.apple.m4a-audio", "m4b": "com.apple.m4a-audio",
    "mp4": "public.mpeg-4-audio", "aac": "public.aac-audio", "wav": "com.microsoft.waveform-audio",
    "aif": "public.aiff-audio", "aiff": "public.aiff-audio", "caf": "com.apple.coreaudio-format",
  ]

  /// The type to tell AVFoundation, as a UTI string. The response's MIME type decides, then
  /// the feed's, then the address's file extension; MP3 when none of them is known. The plain
  /// "audio/mp4" is MPEG-4 audio; the m4a types are Apple's m4a.
  public static func uti(responseType: String?, enclosureType: String?, url: URL?) -> String {
    for type in [responseType, enclosureType] {
      guard let ext = DownloadFile.knownExtension(forType: type) else { continue }
      if ext == "m4a" {
        let kind = (type ?? "").split(separator: ";").first?.lowercased() ?? ""
        if kind.trimmingCharacters(in: .whitespaces) == "audio/mp4" { return "public.mpeg-4-audio" }
      }
      return byExtension[ext] ?? "public.mp3"
    }
    return byExtension[DownloadFile.fileExtension(type: nil, url: url)] ?? "public.mp3"
  }
}

public enum StreamThroughDownload {
  /// Whether an episode plays from its own download. `asked` is the app saying so (Skip ads is
  /// on and the episode is a feed episode). Not for an added file or a preview (their ids are
  /// not folder names, or start with "file-"), not when the episode already has a download or
  /// one on its way (`hasDownload`), and with "Download only on Wi-Fi" on only while on Wi-Fi.
  public static func shouldUse(
    asked: Bool, episodeId: String, hasDownload: Bool, wifiOnly: Bool, onWiFi: Bool
  ) -> Bool {
    guard asked, !hasDownload, DownloadFile.isSafeEpisodeId(episodeId),
      !episodeId.hasPrefix("file-")
    else { return false }
    return !wifiOnly || onWiFi
  }
}

public enum StreamScheme {
  /// The episode's address with its scheme replaced, so AVFoundation hands the request to the
  /// app's resource loader instead of fetching it. Nil for anything but http and https.
  public static func customURL(for url: URL) -> URL? {
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
      var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return nil }
    parts.scheme = scheme == "https" ? "lofistreams" : "lofistream"
    return parts.url
  }
}
