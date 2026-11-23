// LOFI-FORK: the count of ad skipping for each show (see FORK.md and
// docs/PODCASTS-ADS-TEACHING.md). Foundation only.
import Foundation

/// What happened with the ads of each show since the first count, kept on the phone as
/// `Podcasts/ad-tally.json` and shown by the app through `getAdTally()`.
public struct AdTally: Codable, Equatable, Sendable {
  public struct Counts: Codable, Equatable, Sendable {
    public var skipped = 0
    public var undone = 0
    public var trimmed = 0
    public var missed = 0
    /// The seconds skipped. An undone skip takes its seconds off again.
    public var seconds = 0.0

    public init(
      skipped: Int = 0, undone: Int = 0, trimmed: Int = 0, missed: Int = 0, seconds: Double = 0
    ) {
      self.skipped = skipped
      self.undone = undone
      self.trimmed = trimmed
      self.missed = missed
      self.seconds = seconds
    }

    /// Fields that are missing count as zero, so an older or hand-made file still loads.
    public init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      skipped = try values.decodeIfPresent(Int.self, forKey: .skipped) ?? 0
      undone = try values.decodeIfPresent(Int.self, forKey: .undone) ?? 0
      trimmed = try values.decodeIfPresent(Int.self, forKey: .trimmed) ?? 0
      missed = try values.decodeIfPresent(Int.self, forKey: .missed) ?? 0
      seconds = try values.decodeIfPresent(Double.self, forKey: .seconds) ?? 0
    }
  }

  /// Milliseconds since 1970 of the first count, nil before it.
  public var since: Double?
  /// The counts by show id. A show that is not known counts under the empty id.
  public var shows: [String: Counts]

  public init(since: Double? = nil, shows: [String: Counts] = [:]) {
    self.since = since
    self.shows = shows
  }

  private enum CodingKeys: String, CodingKey { case since, shows }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    since = try values.decodeIfPresent(Double.self, forKey: .since)
    shows = try values.decodeIfPresent([String: Counts].self, forKey: .shows) ?? [:]
  }

  /// `since` is written as null before the first count.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(since, forKey: .since)
    try container.encode(shows, forKey: .shows)
  }

  /// Counts one thing for `show` at `time` (milliseconds). `seconds` is what a skip took out of
  /// the listening, or what an undone skip gives back (never below zero in all).
  public mutating func count(
    _ what: PhoneNote.What, show: String?, seconds: Double = 0, at time: Double
  ) {
    if since == nil { since = time }
    let amount = seconds.isFinite ? max(0, seconds) : 0
    var counts = shows[show ?? ""] ?? Counts()
    switch what {
    case .skipped:
      counts.skipped += 1
      counts.seconds += amount
    case .undone:
      counts.undone += 1
      counts.seconds = max(0, counts.seconds - amount)
    case .trimmed: counts.trimmed += 1
    case .missed: counts.missed += 1
    // Answers to a question are not skips or undone skips: nothing is counted for them.
    case .confirmed, .denied: break
    }
    shows[show ?? ""] = counts
  }

  /// The tally as JSON text: `{"since": <ms or null>, "shows": {"<show id>": {...}}}`.
  public var json: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8)
    else { return #"{"since":null,"shows":{}}"# }
    return text
  }

  /// The tally in `data`; anything that cannot be read is an empty tally.
  public static func decode(_ data: Data) -> AdTally {
    (try? JSONDecoder().decode(AdTally.self, from: data)) ?? AdTally()
  }

  /// The tally saved in `file`. A missing or unreadable file means none.
  public static func load(from file: URL) -> AdTally {
    guard let data = try? Data(contentsOf: file) else { return AdTally() }
    return decode(data)
  }

  public func save(to file: URL) throws {
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(json.utf8).write(to: file, options: .atomic)
  }
}

extension AdTally {
  /// The seconds a skip took out of the listening: from where the playhead left to where it
  /// landed. An ad left from its middle counts only the rest of it.
  public static func seconds(from place: Double, to target: Double) -> Double {
    guard place.isFinite, target.isFinite else { return 0 }
    return max(0, target - place)
  }
}

/// The last skip that was noted in an episode, so an ad that is left in progress and then found
/// again longer is not counted and noted a second time.
public struct NotedSkip: Equatable, Sendable {
  private var episode: String?
  private var start = 0.0
  private var end = 0.0
  private var countedSeconds = 0.0

  public init() {}

  /// Whether a skip of `start` to `end` in `episode` is a new one to note and count. A skip that
  /// overlaps the last noted one of the same episode is not (the stretch is widened to hold it).
  public mutating func isNew(episode: String, start: Double, end: Double) -> Bool {
    if self.episode == episode, start < self.end, self.start < end {
      self.start = min(self.start, start)
      self.end = max(self.end, end)
      return false
    }
    self.episode = episode
    self.start = start
    self.end = end
    countedSeconds = 0
    return true
  }

  /// Notes the seconds the last new skip added to the tally. Call it only for a skip `isNew`
  /// said was new; a skip that was not new adds nothing.
  public mutating func counted(seconds: Double) {
    countedSeconds += seconds.isFinite ? max(0, seconds) : 0
  }

  /// The seconds to take off the tally when the last skip is undone: exactly what it added,
  /// once. Zero when nothing was added or it was already given back.
  public mutating func takeCounted() -> Double {
    defer { countedSeconds = 0 }
    return countedSeconds
  }
}
