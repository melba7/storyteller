// LOFI-FORK: the podcast player's rules (see FORK.md). Plain values, no AVFoundation.
import Foundation

/// A bookmark made with the headphones' button while JavaScript was not running. The player
/// appends it to `Podcasts/pending-bookmarks.json`; the app imports it into its database
/// when it runs and empties the file.
public struct PendingBookmark: Codable, Equatable, Sendable {
  /// Made by the player, so importing the same entry twice saves one bookmark.
  public var id: String
  public var episodeId: String
  public var positionSeconds: Double
  /// Milliseconds since 1970.
  public var createdAt: Double

  public init(id: String, episodeId: String, positionSeconds: Double, createdAt: Double) {
    self.id = id
    self.episodeId = episodeId
    self.positionSeconds = positionSeconds
    self.createdAt = createdAt
  }
}

public enum PendingBookmarks {
  /// The most that wait in the file; past it the oldest are dropped.
  public static let limit = 200
  /// A second press this close (in seconds) to a bookmark of the same episode is the same press.
  public static let sameSpot = 5.0

  /// Whether an episode can be bookmarked: it must be in the library, not a preview.
  public static func canBookmark(episodeId: String) -> Bool {
    !episodeId.isEmpty && !episodeId.hasPrefix("preview:")
  }

  /// The bookmarks in `data`. Anything that is not a list gives none, and an entry that
  /// cannot be read is left out.
  public static func decode(_ data: Data) -> [PendingBookmark] {
    guard let list = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
    let decoder = JSONDecoder()
    return list.compactMap { entry in
      guard JSONSerialization.isValidJSONObject(entry),
        let data = try? JSONSerialization.data(withJSONObject: entry)
      else { return nil }
      return try? decoder.decode(PendingBookmark.self, from: data)
    }
  }

  public static func encode(_ bookmarks: [PendingBookmark]) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return (try? encoder.encode(bookmarks)) ?? Data("[]".utf8)
  }

  /// The list with `bookmark` added at the end. Left out when its id is there already or it
  /// is the same press as a bookmark of the same episode within `sameSpot` seconds. Past
  /// `limit` the oldest go.
  public static func appending(
    _ bookmark: PendingBookmark, to bookmarks: [PendingBookmark]
  ) -> [PendingBookmark] {
    let repeated = bookmarks.contains {
      $0.id == bookmark.id
        || ($0.episodeId == bookmark.episodeId
          && abs($0.positionSeconds - bookmark.positionSeconds) < sameSpot)
    }
    if repeated { return bookmarks }
    return Array((bookmarks + [bookmark]).suffix(limit))
  }

  // MARK: The file

  /// The bookmarks waiting in `file`; none when it is missing or unreadable.
  public static func load(from file: URL) -> [PendingBookmark] {
    guard let data = try? Data(contentsOf: file) else { return [] }
    return decode(data)
  }

  public static func append(_ bookmark: PendingBookmark, to file: URL) throws {
    let all = appending(bookmark, to: load(from: file))
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encode(all).write(to: file, options: .atomic)
  }

  /// The bookmarks waiting in `file` as JSON text ("[]" when none).
  public static func json(from file: URL) -> String {
    String(decoding: encode(load(from: file)), as: UTF8.self)
  }

  /// Takes the bookmarks with these ids out of `file`, which the app has saved. Others
  /// stay, so one made while the app was importing is not lost.
  public static func remove(ids: Set<String>, from file: URL) throws {
    let all = load(from: file)
    let kept = all.filter { !ids.contains($0.id) }
    if kept.count == all.count { return }
    try encode(kept).write(to: file, options: .atomic)
  }
}
