// LOFI-FORK: `ahead-ads.json`, the ads the Mac marked in the next episodes the night before, and the
// table that tells which episode of the app is which entry (see FORK.md and AheadAds.swift).
// Foundation only.
import Foundation

// THE FILE (`ahead-ads.json`, version 1) is written by the Mac's nightly read-ahead and published
// beside the other teaching files:
//
//   {"version": 1, "writtenAt": 1700000000,
//    "episodes": [{"feed": "<feed address>", "guid": "<episode guid>", "title": "...",
//                  "marked": 1700000000,
//                  "ads": [{"kind": "ad", "confidence": "high", "start": 612.0, "end": 671.5,
//                           "startWords": "the first up to 40 words of the ad",
//                           "endWords": "the last up to 40 words of the ad"}]}]}
//
// The marks are by WORDS and not by times: the phone's copy of an episode can carry other inserted
// ads than the Mac's copy, so the times of the Mac's copy do not hold on the phone (the times are
// only the length an ad had). An entry is ignored 14 days after `marked`. Anything of the wrong
// type or of an unknown kind is left out; a file that is damaged, too big or of another version
// reads as no file, and with no file nothing changes.

/// One ad the Mac marked in an episode.
public struct AheadMark: Codable, Sendable, Equatable {
  /// How sure Claude was.
  public enum Confidence: String, Codable, Sendable, Equatable { case high, medium, low }

  public var kind: AdKind
  public var confidence: Confidence
  /// Where the ad was on the Mac's copy, in seconds. Only its length is used on the phone.
  public var start: Double
  public var end: Double
  /// The first and the last words of the ad, as the Mac heard them, up to 40 words each.
  public var startWords: String
  public var endWords: String

  public init(
    kind: AdKind, confidence: Confidence, start: Double, end: Double, startWords: String,
    endWords: String
  ) {
    self.kind = kind
    self.confidence = confidence
    self.start = start
    self.end = end
    self.startWords = startWords
    self.endWords = endWords
  }

  private enum CodingKeys: String, CodingKey {
    case kind, confidence, start, end, startWords, endWords
  }

  /// The Mac marks plain ads, promos and the hosts' own plugs; the credits are never marked.
  public init(from decoder: Decoder) throws {
    let box = try decoder.container(keyedBy: CodingKeys.self)
    kind = try box.decode(AdKind.self, forKey: .kind)
    guard kind != .credits else {
      throw DecodingError.dataCorruptedError(
        forKey: .kind, in: box, debugDescription: "the credits are not an ad to skip")
    }
    confidence = try box.decode(Confidence.self, forKey: .confidence)
    start = try box.decode(Double.self, forKey: .start)
    end = try box.decode(Double.self, forKey: .end)
    startWords = try box.decode(String.self, forKey: .startWords)
    endWords = try box.decode(String.self, forKey: .endWords)
  }
}

/// The marks of one episode.
public struct AheadEntry: Codable, Sendable, Equatable {
  public var feed: String
  public var guid: String
  public var title: String
  /// When Claude marked the episode, in seconds since 1970.
  public var marked: Double
  public var ads: [AheadMark]

  public init(feed: String, guid: String, title: String, marked: Double, ads: [AheadMark]) {
    self.feed = feed
    self.guid = guid
    self.title = title
    self.marked = marked
    self.ads = ads
  }
}

public struct AheadFile: Codable, Sendable, Equatable {
  public static let fileName = "ahead-ads.json"
  public static let currentVersion = 1
  /// An entry marked longer ago than this is ignored.
  public static let maxAgeDays = 14.0
  /// A file bigger than this reads as no file (the limit of every teaching file).
  public static let maxBytes = TeachingFiles.maxBytes

  public var version = AheadFile.currentVersion
  public var writtenAt: Double
  public var episodes: [AheadEntry]

  public init(writtenAt: Double = 0, episodes: [AheadEntry] = []) {
    self.writtenAt = writtenAt
    self.episodes = episodes
  }

  /// Reads one value of a list and keeps nil when it is of the wrong shape, so one bad entry does
  /// not fail the whole list.
  private struct Lossy<Value: Decodable>: Decodable {
    var value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
  }

  private enum Keys: String, CodingKey { case version, writtenAt, episodes }
  private enum EntryKeys: String, CodingKey { case feed, guid, title, marked, ads }

  /// An entry (or an ad) of the wrong shape is left out; the file as a whole must be an object
  /// with a list of episodes.
  public init(from decoder: Decoder) throws {
    let box = try decoder.container(keyedBy: Keys.self)
    version = try box.decode(Int.self, forKey: .version)
    writtenAt = (try? box.decode(Double.self, forKey: .writtenAt)) ?? 0
    episodes = try box.decode([Lossy<Entry>].self, forKey: .episodes).compactMap { $0.value?.entry }
  }

  /// An entry as the file has it, where each ad is read on its own.
  private struct Entry: Decodable {
    var entry: AheadEntry

    init(from decoder: Decoder) throws {
      let box = try decoder.container(keyedBy: EntryKeys.self)
      entry = AheadEntry(
        feed: try box.decode(String.self, forKey: .feed),
        guid: try box.decode(String.self, forKey: .guid),
        title: try box.decode(String.self, forKey: .title),
        marked: try box.decode(Double.self, forKey: .marked),
        ads: try box.decode([Lossy<AheadMark>].self, forKey: .ads).compactMap(\.value))
    }
  }

  /// The marks in `data`. A file that is damaged, over the limit or not version 1 is no file.
  public init(data: Data) {
    var read: AheadFile?
    if data.count <= Self.maxBytes,
      let decoded = try? JSONDecoder().decode(AheadFile.self, from: data),
      decoded.version == Self.currentVersion
    {
      read = decoded
    }
    self = read ?? AheadFile()
  }

  /// What is at `url`; no file when it is missing or cannot be read.
  public static func load(from url: URL) -> AheadFile {
    guard let data = try? Data(contentsOf: url) else { return AheadFile() }
    return AheadFile(data: data)
  }

  /// The file's bytes, as the Mac writes it (keys in order).
  public func encoded() -> Data? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try? encoder.encode(self)
  }

  // MARK: Finding the entry of an episode

  /// The entry for an episode of the app, or nil: the newest marking that is not older than
  /// `maxAgeDays` at `now`, has at least one ad, and names the episode. An entry and an episode
  /// that both have a guid are the same episode when the guids are equal and, when both name a
  /// feed, the feeds are the same (as feed keys), since two shows can use the same style of guid.
  /// When either has no guid, the feed (as a feed key) and the title (lower case, letters and
  /// digits only) must be equal.
  public func entry(guid: String, feed: String, title: String, now: Date) -> AheadEntry? {
    let oldest = now.timeIntervalSince1970 - Self.maxAgeDays * 86_400
    let wantedFeed = FeedKey.key(feed)
    let wantedTitle = Self.plain(title)
    return episodes.filter { entry in
      guard entry.marked >= oldest, !entry.ads.isEmpty else { return false }
      if !guid.isEmpty, !entry.guid.isEmpty {
        guard entry.guid == guid else { return false }
        let entryFeed = FeedKey.key(entry.feed)
        return wantedFeed.isEmpty || entryFeed.isEmpty || entryFeed == wantedFeed
      }
      return !wantedTitle.isEmpty && Self.plain(entry.title) == wantedTitle
        && !wantedFeed.isEmpty && FeedKey.key(entry.feed) == wantedFeed
    }.max { $0.marked < $1.marked }
  }

  /// A title as it is compared: lower case, words of letters and digits, one space apart.
  static func plain(_ title: String) -> String {
    title.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
  }
}

/// What the app knows of the episodes the marks may be about, since the phone's native side knows
/// an episode by its id only: `{"<episode id>": {"feed", "guid", "title"}}`, which the app's
/// TypeScript sends from its database and the phone keeps as `ahead-episodes.json` in the folder
/// of the teaching files.
public enum AheadEpisodes {
  public static let fileName = "ahead-episodes.json"
  /// The most episodes kept (the Mac marks 8 a night and keeps them 14 days).
  public static let most = 500

  public struct Facts: Codable, Sendable, Equatable {
    public var feed: String
    public var guid: String
    public var title: String

    public init(feed: String, guid: String, title: String) {
      self.feed = feed
      self.guid = guid
      self.title = title
    }
  }

  private struct Lossy: Decodable {
    var value: Facts?
    init(from decoder: Decoder) throws { value = try? Facts(from: decoder) }
  }

  /// The table in `json`. An entry with no id or of the wrong shape is left out, and at most
  /// `most` entries are kept (the ones with the smallest ids if there are more, so the same text
  /// always gives the same table). Nil when the text is not a JSON object.
  public static func parse(_ json: String) -> [String: Facts]? {
    guard let table = try? JSONDecoder().decode([String: Lossy].self, from: Data(json.utf8))
    else { return nil }
    var kept: [String: Facts] = [:]
    for id in table.keys.sorted() where !id.isEmpty && kept.count < most {
      if let facts = table[id]?.value { kept[id] = facts }
    }
    return kept
  }

  /// The table saved in `folder`, or an empty one when there is none or it cannot be read.
  public static func load(from folder: URL) -> [String: Facts] {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)),
      let table = try? JSONDecoder().decode([String: Facts].self, from: data)
    else { return [:] }
    return table
  }

  public static func save(_ table: [String: Facts], to folder: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try encoder.encode(table).write(to: folder.appendingPathComponent(fileName), options: .atomic)
  }
}

extension TeachingFiles {
  /// The marks of an episode of the app: its facts from `table` looked up in the file. Nil with no
  /// file, no facts for the episode, or no entry that names it.
  public func aheadEntry(
    episode: String, table: [String: AheadEpisodes.Facts], now: Date
  ) -> AheadEntry? {
    guard let facts = table[episode] else { return nil }
    return ahead.entry(guid: facts.guid, feed: facts.feed, title: facts.title, now: now)
  }
}
