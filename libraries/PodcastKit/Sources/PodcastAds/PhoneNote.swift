// LOFI-FORK: what the phone tells the Mac about ad skipping (see FORK.md and
// docs/PODCASTS-ADS-TEACHING.md). Foundation only.
import Foundation

/// One thing that happened with an ad, as the player writes it to the pending file. The app
/// adds the feed, guid, title and audio address before the line goes to the linked folder.
public struct PhoneNote: Codable, Equatable, Sendable {
  public enum What: String, Codable, Sendable {
    case skipped, undone, trimmed, missed
    /// The listener answered a question "yes, skip it": a stretch the phone was unsure of is an ad.
    case confirmed
    /// The listener answered a question "not an ad".
    case denied
  }

  public var v: Int
  /// Milliseconds since 1970.
  public var at: Double
  public var what: What
  /// The episode's id in the app.
  public var episode: String
  /// The show's id, empty when it is not known.
  public var show: String
  /// Seconds into the episode.
  public var start: Double
  /// Seconds into the episode, nil when there is none.
  public var end: Double?
  /// The `rawValue` of the ad's `AdKind`, nil when no ad was known there.
  public var kind: AdKind?
  /// The name of the finder that made the ad this note is about ("own-sound", "meaning"), nil
  /// when it is not known. Older notes have none.
  public var by: String?

  public init(
    at: Double, what: What, episode: String, show: String?, start: Double, end: Double?,
    kind: AdKind?, by: String? = nil
  ) {
    self.v = 1
    self.at = at
    self.what = what
    self.episode = episode
    self.show = show ?? ""
    self.start = start
    self.end = end
    self.kind = kind
    self.by = by
  }

  /// The contract's fields, with `end` and `kind` written as null when there are none. `by` is
  /// left out when there is none, so a note without a finder reads the same as in older builds.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(v, forKey: .v)
    try container.encode(at, forKey: .at)
    try container.encode(what, forKey: .what)
    try container.encode(episode, forKey: .episode)
    try container.encode(show, forKey: .show)
    try container.encode(start, forKey: .start)
    try container.encode(end, forKey: .end)
    try container.encode(kind, forKey: .kind)
    try container.encodeIfPresent(by, forKey: .by)
  }

  /// The note as one line of JSON, with no line break.
  public var line: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8)
    else { return "" }
    return text
  }
}

/// The rules of the pending file (`Podcasts/pending-ad-notes.jsonl`), on its text.
public enum PendingNotes {
  /// The most lines that wait; past it the oldest go.
  public static let maxLines = 2000

  /// The text with `line` added at the end and only the newest `maxLines` kept. Blank lines go.
  public static func appending(_ line: String, to text: String, maxLines: Int = maxLines) -> String {
    let lines = (text.split(separator: "\n", omittingEmptySubsequences: true) + [Substring(line)])
      .filter { !$0.isEmpty }.suffix(max(0, maxLines))
    return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
  }

  /// The text without its first `count` lines (the ones the app has saved). Blank lines go.
  public static func dropping(_ count: Int, from text: String) -> String {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true).dropFirst(max(0, count))
    return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
  }

  /// The text without its first `count` lines at most, and only those whose `at` is `upToAt`
  /// (milliseconds) or earlier: the lines the app has saved. A note written since stays, also
  /// when the cap pushed older lines out meanwhile. A line that cannot be read is dropped with
  /// the ones before it. Blank lines go.
  public static func dropping(_ count: Int, upToAt: Double, from text: String) -> String {
    struct Stamp: Decodable { var at: Double }
    var lines = text.split(separator: "\n", omittingEmptySubsequences: true)[...]
    var left = max(0, count)
    while left > 0, let first = lines.first {
      if let stamp = try? JSONDecoder().decode(Stamp.self, from: Data(first.utf8)), stamp.at > upToAt {
        break
      }
      lines = lines.dropFirst()
      left -= 1
    }
    return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
  }
}
