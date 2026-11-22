// LOFI-FORK: what the phone tells the Mac about ad skipping (see FORK.md and
// docs/PODCASTS-ADS-TEACHING.md). Foundation only.
import Foundation

/// One thing that happened with an ad, as the player writes it to the pending file. The app
/// adds the feed, guid, title and audio address before the line goes to the linked folder.
public struct PhoneNote: Codable, Equatable, Sendable {
  public enum What: String, Codable, Sendable {
    case skipped, undone, trimmed, missed
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

  public init(
    at: Double, what: What, episode: String, show: String?, start: Double, end: Double?,
    kind: AdKind?
  ) {
    self.v = 1
    self.at = at
    self.what = what
    self.episode = episode
    self.show = show ?? ""
    self.start = start
    self.end = end
    self.kind = kind
  }

  /// The contract's fields, with `end` and `kind` written as null when there are none.
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
}
