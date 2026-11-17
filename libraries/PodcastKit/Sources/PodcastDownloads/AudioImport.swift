// LOFI-FORK: the rules for audio files the listener adds from the Files app (see FORK.md).
//
// An added file is installed like a finished download: `<episodeId>/<sha256>.<ext>`. Its
// episode id comes from its content, so adding the same file twice finds the first copy.
import Foundation

public enum AudioImport {
  /// What AVPlayer plays that a person is likely to have as a file.
  public static let extensions: [String] = [
    "mp3", "m4a", "m4b", "aac", "wav", "aif", "aiff", "caf", "flac", "mp4",
  ]

  /// The start of every added file's episode id.
  public static let idPrefix = "file-"

  /// How many hash characters the id keeps: 128 bits, far more than a library ever needs.
  private static let idLength = 32

  /// The lowercase extension of an accepted file name, or nil for any other file.
  public static func fileExtension(fileName: String) -> String? {
    let ext = (fileName as NSString).pathExtension.lowercased()
    guard !(fileName as NSString).deletingPathExtension.isEmpty, extensions.contains(ext),
      DownloadFile.isSafeExtension(ext)
    else { return nil }
    return ext
  }

  public static func isAccepted(fileName: String) -> Bool {
    fileExtension(fileName: fileName) != nil
  }

  /// `file-<first 32 characters of the SHA-256>`, or nil when the text is not a SHA-256.
  public static func episodeId(sha256: String) -> String? {
    guard DownloadFile.isSha256(sha256) else { return nil }
    return idPrefix + sha256.prefix(idLength)
  }

  public static func isImportedId(_ id: String) -> Bool {
    id.hasPrefix(idPrefix) && DownloadFile.isSafeEpisodeId(id)
  }

  /// The tag's title when it has one, else the file name without its extension.
  public static func title(fileName: String, tagTitle: String?) -> String {
    let tag = (tagTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !tag.isEmpty { return tag }
    let name = (fileName as NSString).lastPathComponent
    // A name that is only an extension (".mp3") has no title in it.
    let base = name.hasPrefix(".")
      ? "" : (name as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
    return base.isEmpty ? "Untitled file" : base
  }

  /// Whether this entry already holds exactly this content, so adding it again changes nothing
  /// (installing again would delete the transcript and ad finding made for it).
  public static func isInstalled(_ entry: DownloadEntry?, sha256: String) -> Bool {
    guard let entry, case .downloaded(_, let have, _, _) = entry.state else { return false }
    return have == sha256
  }
}
