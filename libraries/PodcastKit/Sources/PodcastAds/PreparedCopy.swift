// LOFI-FORK: the copy of an episode the Mac prepared, as `ahead-ads.json` names it (see FORK.md,
// AheadFile.swift and docs/PLAN.md, milestone Y4). Foundation only.
import Foundation

/// The audio file the Mac marked an episode on and put in the linked folder, so that the phone can
/// play that very file and the marks' times hold to the frame. The phone trusts the copy only when
/// the size and the SHA-256 of what it got match these.
///
/// A copy that is not exactly as it must be reads as no copy (the entry is still read), so a damaged
/// or hostile file can never point the phone outside the `prepared` folder.
public struct PreparedCopy: Codable, Sendable, Equatable {
  /// The folder of the copies, inside `Podcasts/` of the linked folder.
  public static let folder = "prepared"

  /// Where the file is, `prepared/<a plain name>`.
  public var file: String
  /// The SHA-256 of the file, 64 hex digits in lower case.
  public var sha256: String
  public var bytes: Int64

  public init(file: String, sha256: String, bytes: Int64) {
    self.file = file
    self.sha256 = sha256
    self.bytes = bytes
  }

  private enum CodingKeys: String, CodingKey { case file, sha256, bytes }

  public init(from decoder: Decoder) throws {
    let box = try decoder.container(keyedBy: CodingKeys.self)
    let file = try box.decode(String.self, forKey: .file)
    let sha256 = try box.decode(String.self, forKey: .sha256).lowercased()
    let bytes = try box.decode(Int64.self, forKey: .bytes)
    guard Self.isPlain(file: file), Self.isHash(sha256), bytes > 0 else {
      throw DecodingError.dataCorruptedError(
        forKey: .file, in: box, debugDescription: "not a copy the phone may take")
    }
    self.init(file: file, sha256: sha256, bytes: bytes)
  }

  /// `prepared/<name>` with one name that is not empty, does not start with a dot, holds no
  /// slash, backslash, control character or `..`.
  static func isPlain(file: String) -> Bool {
    let prefix = folder + "/"
    guard file.hasPrefix(prefix) else { return false }
    let name = file.dropFirst(prefix.count)
    return !name.isEmpty && !name.hasPrefix(".") && !name.contains("..")
      && !name.unicodeScalars.contains { $0 == "/" || $0 == "\\" || $0.value < 0x20 || $0.value == 0x7f }
  }

  static func isHash(_ text: String) -> Bool {
    text.utf8.count == 64 && text.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }
  }
}
