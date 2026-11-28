// LOFI-FORK: the opening and return lines the Mac learned (`ad-cues.json`, see FORK.md and
// CueAds.swift). Foundation only.
import Foundation

// THE FILE (`ad-cues.json`, version 1) is written by the Mac (teach_cues.py), read by the phone
// and the scorecard, and holds words of transcripts, so it is never committed:
//
//   {"version": 1, "writtenAt": 1700000000, "episodes": 1170,
//    "starts": ["this episode is brought", "..."], "returns": ["..."],
//    "shows": [{"feed": "<feed address>", "starts": ["..."], "returns": ["..."],
//               "phrases": ["a word from", "..."]}],
//    "common": ["about", "..."], "usual": ["..."]}
//
// A cue is the first 3 to 6 words of a transcript line, as `AdWordModel.tokens` makes words,
// joined by one space. A line matches a list when one of its own first 3, 4, 5 or 6 words, joined
// the same way, is in the list. `starts` are lines that open an ad and `returns` are lines where
// the show comes back. `common` words occur in more than 15 in 100 episodes and `usual` ones in
// more than 5 and at most 15 in 100; the rest of the words are rare.
//
// A show's `phrases` are optional: the handoff, segment and plug phrases of the show's playbook
// (teach_playbook.py), each 2 words or more joined by one space. A line matches when it holds a
// phrase of its show as whole words, anywhere in the line. Builds that do not know the list
// ignore it, so the version stays 1.

/// The cues the Mac learned, for every show and for each show on its own.
public struct AdCues: Sendable, Equatable {
  public static let fileName = "ad-cues.json"
  public static let currentVersion = 1
  /// The cues are the first this many words of a line, at least `shortest`.
  static let shortest = 3
  static let longest = 6

  struct Lists: Sendable, Equatable {
    var starts: Set<String> = []
    var returns: Set<String> = []
    /// The phrases of the show's playbook; only a show's own lists have any.
    var phrases: Set<String> = []
    var isEmpty: Bool { starts.isEmpty && returns.isEmpty && phrases.isEmpty }
  }

  var general = Lists()
  /// Each show's own lists, by the app's show id.
  var shows: [String: Lists] = [:]
  var common: Set<String> = []
  var usual: Set<String> = []
  /// How many episodes the Mac learned them from; 0 when the file does not say.
  public private(set) var episodes = 0

  /// No cues: nothing matches.
  public init() {}

  /// Whether no line can match.
  public var isEmpty: Bool { general.isEmpty && shows.values.allSatisfy(\.isEmpty) }

  // MARK: What the file holds, for the scorecard

  public var generalStarts: Int { general.starts.count }
  public var generalReturns: Int { general.returns.count }
  public var showStarts: Int { shows.values.reduce(0) { $0 + $1.starts.count } }
  public var showReturns: Int { shows.values.reduce(0) { $0 + $1.returns.count } }
  public var showCount: Int { shows.count }
  public var showPhrases: Int { shows.values.reduce(0) { $0 + $1.phrases.count } }
  /// How many shows have a phrase.
  public var phraseShows: Int { shows.values.filter { !$0.phrases.isEmpty }.count }
  public var commonWords: Int { common.count }
  public var usualWords: Int { usual.count }

  // MARK: Matching

  /// Whether the line with these words opens an ad on `show`: one of its first 3 to 6 words is a
  /// start cue of every show or of this one.
  public func opens(_ words: [String], show: String) -> Bool {
    matches(words) { general.starts.contains($0) || shows[show]?.starts.contains($0) == true }
  }

  /// Whether the line with these words is where the show comes back, in the same way.
  public func returns(_ words: [String], show: String) -> Bool {
    matches(words) { general.returns.contains($0) || shows[show]?.returns.contains($0) == true }
  }

  /// Whether the line with these words holds a phrase of the playbook of `show` as whole words,
  /// anywhere in the line. Another show's phrases never match.
  public func playbookOpens(_ words: [String], show: String) -> Bool {
    guard let phrases = shows[show]?.phrases, !phrases.isEmpty, !words.isEmpty else { return false }
    let line = " " + words.joined(separator: " ") + " "
    return phrases.contains { line.contains(" " + $0 + " ") }
  }

  private func matches(_ words: [String], _ isCue: (String) -> Bool) -> Bool {
    for count in Self.shortest...Self.longest where words.count >= count {
      if isCue(words.prefix(count).joined(separator: " ")) { return true }
    }
    return false
  }

  /// A word that says something about the topic: 4 letters or more and not a common word.
  public func isContent(_ word: String) -> Bool { word.count >= 4 && !common.contains(word) }

  /// A content word that is not a usual one either.
  public func isRare(_ word: String) -> Bool { isContent(word) && !usual.contains(word) }

  // MARK: Reading

  /// One value of a list, nil when it is of the wrong shape.
  private struct Lossy<Value: Decodable>: Decodable {
    var value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
  }

  /// A list of words; a list of the wrong shape is read as no list.
  private struct Words: Decodable {
    var list: [Lossy<String>]
    init(from decoder: Decoder) throws {
      list = (try? [Lossy<String>](from: decoder)) ?? []
    }
  }

  private struct Entry: Decodable {
    var feed: String?
    var starts: [Lossy<String>] = []
    var returns: [Lossy<String>] = []
    var phrases: [Lossy<String>] = []

    private enum Keys: String, CodingKey { case feed, starts, returns, phrases }

    init(from decoder: Decoder) throws {
      let box = try decoder.container(keyedBy: Keys.self)
      feed = try? box.decode(String.self, forKey: .feed)
      starts = (try? box.decode(Words.self, forKey: .starts))?.list ?? []
      returns = (try? box.decode(Words.self, forKey: .returns))?.list ?? []
      phrases = (try? box.decode(Words.self, forKey: .phrases))?.list ?? []
    }
  }

  private struct File: Decodable {
    var version: Int?
    var episodes: Int?
    var starts: [Lossy<String>] = []
    var returns: [Lossy<String>] = []
    var shows: [Lossy<Entry>] = []
    var common: [Lossy<String>] = []
    var usual: [Lossy<String>] = []

    private enum Keys: String, CodingKey { case version, episodes, starts, returns, shows, common, usual }

    init(from decoder: Decoder) throws {
      let box = try decoder.container(keyedBy: Keys.self)
      version = try? box.decode(Int.self, forKey: .version)
      episodes = try? box.decode(Int.self, forKey: .episodes)
      starts = (try? box.decode(Words.self, forKey: .starts))?.list ?? []
      returns = (try? box.decode(Words.self, forKey: .returns))?.list ?? []
      shows = (try? box.decode([Lossy<Entry>].self, forKey: .shows)) ?? []
      common = (try? box.decode(Words.self, forKey: .common))?.list ?? []
      usual = (try? box.decode(Words.self, forKey: .usual))?.list ?? []
    }
  }

  private static func words(_ list: [Lossy<String>]) -> Set<String> {
    Set(list.compactMap(\.value).filter { !$0.isEmpty })
  }

  /// The phrases of a list, each made into words again and joined by one space; one of fewer
  /// than 2 words is left out.
  private static func phrases(_ list: [Lossy<String>]) -> Set<String> {
    Set(
      list.compactMap(\.value).map { AdWordModel.tokens($0) }.filter { $0.count >= 2 }
        .map { $0.joined(separator: " ") })
  }

  /// The cues in `data`. A file that is damaged, is of another version or is over 5 MB reads as
  /// no cues. An entry of the wrong shape is skipped. A show's feed address is turned into the
  /// app's show id by `showOf`; a show it does not know is left out.
  public init(data: Data, showOf: MacFiles.ShowOf = MacFiles.feedAsShow) {
    self.init()
    guard data.count <= TeachingFiles.maxBytes,
      let file = try? JSONDecoder().decode(File.self, from: data),
      file.version == Self.currentVersion
    else { return }
    general = Lists(starts: Self.words(file.starts), returns: Self.words(file.returns))
    common = Self.words(file.common)
    usual = Self.words(file.usual)
    if let count = file.episodes, count > 0 { episodes = count }
    for item in file.shows {
      guard let entry = item.value, let feed = entry.feed, let show = showOf(feed), !show.isEmpty
      else { continue }
      var lists = shows[show] ?? Lists()
      lists.starts.formUnion(Self.words(entry.starts))
      lists.returns.formUnion(Self.words(entry.returns))
      lists.phrases.formUnion(Self.phrases(entry.phrases))
      shows[show] = lists
    }
  }

  /// Whether `data` is a version 1 object that holds the five lists, which is all the phone asks
  /// of the file before it keeps it. Each entry is read leniently later.
  public static func isShape(_ data: Data) -> Bool {
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let version = root["version"] as? Int, version == currentVersion
    else { return false }
    return ["starts", "returns", "shows", "common", "usual"].allSatisfy { root[$0] is [Any] }
  }
}
