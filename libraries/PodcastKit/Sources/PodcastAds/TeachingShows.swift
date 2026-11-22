// LOFI-FORK: which feed is which show, as the app tells the phone's teaching files (see FORK.md).
import Foundation

/// The table that turns the Mac's feed addresses into the app's show ids: `{"<feed key>": "<show id>"}`,
/// kept as `shows.json` in the teaching folder.
public enum TeachingShows {
  public static let fileName = "shows.json"

  /// The table in `json`. Each key is made a feed key; an entry whose key or show id is empty, or
  /// whose value is not text, is left out. Nil when the text is not a JSON object.
  public static func parse(_ json: String) -> [String: String]? {
    guard let root = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
    else { return nil }
    var table: [String: String] = [:]
    for (feed, value) in root {
      let key = FeedKey.key(feed)
      guard !key.isEmpty, let show = value as? String, !show.isEmpty else { continue }
      table[key] = show
    }
    return table
  }

  /// The table saved in `folder`, or an empty one when there is none or it cannot be read.
  public static func load(from folder: URL) -> [String: String] {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)),
      let table = try? JSONDecoder().decode([String: String].self, from: data)
    else { return [:] }
    return table
  }

  public static func save(_ table: [String: String], to folder: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try encoder.encode(table).write(to: folder.appendingPathComponent(fileName), options: .atomic)
  }
}
