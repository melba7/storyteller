// LOFI-FORK: what a Mac's teaching run learned about how each show starts (see FORK.md).
//
// `show-habits.json` says, per show, how many marked episodes it is from, how many opened with an
// ad and where those openings usually ended. It is read beside `ShowStarts` (what the phone saw
// itself) and only ever tells the phone to wait longer or not at all. Foundation only.
import Foundation

public struct ShowHabits: Codable, Sendable, Equatable {
  public static let currentVersion = 1
  public static let fileName = "show-habits.json"

  public struct Show: Codable, Sendable, Equatable {
    /// The app's id of the show.
    public var id: String
    /// How many marked episodes this is from.
    public var episodes: Int
    /// How many of them opened with an ad.
    public var opensWithAd: Int
    /// Where those openings usually ended, in seconds.
    public var openingEnds: Double?

    /// Whether the numbers are possible. A show whose numbers are not says nothing.
    var isSound: Bool {
      (0...1_000_000).contains(episodes) && (0...episodes).contains(opensWithAd) && (openingEnds?.isFinite ?? true)
    }
  }

  public var version: Int
  public var shows: [Show]

  public init() {
    version = Self.currentVersion
    shows = []
  }

  private func sound(_ id: String) -> Show? {
    shows.first(where: { $0.id == id }).flatMap { $0.isSound ? $0 : nil }
  }

  /// At least 3 episodes, and at least three in five of them opened with an ad.
  public func usuallyOpensWithAd(show: String) -> Bool {
    guard let known = sound(show) else { return false }
    return known.episodes >= 3 && known.opensWithAd * 5 >= known.episodes * 3
  }

  /// At least 4 episodes and none of them opened with an ad.
  public func startsClean(show: String) -> Bool {
    guard let known = sound(show) else { return false }
    return known.episodes >= 4 && known.opensWithAd == 0
  }

  /// Where the show's opening ad usually ends, when it usually opens with one: `openingEnds`
  /// kept inside 5...300. Nil otherwise.
  public func openingEnd(show: String) -> Double? {
    guard usuallyOpensWithAd(show: show), let ends = sound(show)?.openingEnds else { return nil }
    return min(max(ends, 5), 300)
  }

  /// How far a head scan should look first for a show that usually opens with an ad: the end of
  /// its usual opening plus 10 seconds. Nil for any other show.
  public func firstLook(show: String) -> Double? {
    openingEnd(show: show).map { $0 + 10 }
  }

  /// The habits in `data`, nil when it is not this format or version.
  public init?(data: Data) {
    guard let read = try? JSONDecoder().decode(ShowHabits.self, from: data),
      read.version == Self.currentVersion
    else { return nil }
    self = read
  }

  /// What was saved at `url`, or nothing when there is no file, it cannot be read or it is of
  /// another version.
  public static func load(from url: URL) -> ShowHabits {
    guard let data = try? Data(contentsOf: url), let saved = ShowHabits(data: data) else {
      return ShowHabits()
    }
    return saved
  }

  public func save(to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(self).write(to: url, options: .atomic)
  }
}
