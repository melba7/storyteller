// LOFI-FORK: what the phone checks before it swaps in the Mac's prepared copy (see FORK.md and
// docs/PLAN.md, milestone Y5). Plain values. Foundation only.
import Foundation

public enum PreparedInstall {
  /// Why a copy is not installed, in one word. The raw value is what the app's JavaScript reads.
  public enum Refusal: String, Sendable, Equatable {
    /// The Mac lists no copy for the episode.
    case noCopy
    /// The episode is in the player: its file is open.
    case playing
    /// The episode is being downloaded right now.
    case downloading
    /// The file's size is not the listed one.
    case size
    /// The file's SHA-256 is not the listed one.
    case hash
  }

  /// The checks made before the file is read. The player comes before the download: a file the
  /// player has open is the one thing that must never be swapped.
  public static func early(listed: PreparedCopy?, inPlayer: Bool, moving: Bool) -> Refusal? {
    guard listed != nil else { return .noCopy }
    if inPlayer { return .playing }
    if moving { return .downloading }
    return nil
  }

  /// The checks made on the file itself. The phone trusts the copy only when both match; the
  /// size is looked at first because it needs no reading of the file.
  public static func late(listed: PreparedCopy, bytes: Int64, sha256: String) -> Refusal? {
    guard bytes == listed.bytes else { return .size }
    guard sha256.lowercased() == listed.sha256 else { return .hash }
    return nil
  }

  /// The extension the installed file gets: the copy's own, in lower case, one to five letters or
  /// digits as the download store wants. Nil when the copy has none.
  public static func fileExtension(of copy: PreparedCopy) -> String? {
    let name = copy.file.split(separator: "/").last.map(String.init) ?? ""
    guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
    let ext = name[name.index(after: dot)...].lowercased()
    let plain = ext.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) }
    return (1...5).contains(ext.utf8.count) && plain ? ext : nil
  }

  /// The for-list flag of the installed entry: an entry that existed keeps its own (a download the
  /// listener asked for stays theirs), a new one gets what the caller says.
  public static func forList(existing: Bool?, forListOnly: Bool) -> Bool {
    existing ?? forListOnly
  }
}
