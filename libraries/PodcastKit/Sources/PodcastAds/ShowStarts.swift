// LOFI-FORK: whether a show's episodes start with an ad (see FORK.md).
//
// One bit per show, kept beside the known ads: did each of its last five checked episodes have
// no ad before 30 seconds. A show that does not start with an ad is not waited for (StartHold).
// Not a template of where ads are: a template that says "skip the first 60 seconds" is wrong
// whenever the host inserts a different number of ads. Foundation only.
import Foundation

public struct ShowStarts: Codable, Sendable, Equatable {
  public static let currentVersion = 1
  public static let fileName = "show-starts.json"

  /// How many episodes of a show are remembered, and how many shows.
  public static let kept = 5
  public static let mostShows = 200
  /// An ad that starts before this many seconds is an ad at the start of an episode.
  public static let window = 30.0
  /// A scan that did not reach this many seconds did not check the start well enough to count:
  /// the model may only answer for the first seconds from the 60 second step on.
  public static let checkedSeconds = 60.0

  /// One show's results, the newest last: whether that episode had an ad at its start.
  public struct Show: Codable, Sendable, Equatable {
    public var id: String
    public var results: [Bool]
  }

  public var version: Int
  /// The shows in the order they were last recorded, the oldest first.
  public var shows: [Show]

  public init() {
    version = Self.currentVersion
    shows = []
  }

  /// Whether the show's last `kept` checked episodes all had no ad at the start.
  public func startsClean(show: String) -> Bool {
    guard let known = shows.first(where: { $0.id == show }) else { return false }
    return known.results.count >= Self.kept && !known.results.contains(true)
  }

  /// Whether any ad that is skipped starts inside the first `window` seconds.
  public static func hadAdAtStart(_ ads: [FoundAd]) -> Bool {
    ads.contains { $0.confidence >= .unsure && $0.start < window }
  }

  public mutating func record(show: String, hadAdAtStart: Bool) {
    var results = shows.first(where: { $0.id == show })?.results ?? []
    shows.removeAll { $0.id == show }
    results.append(hadAdAtStart)
    shows.append(Show(id: show, results: Array(results.suffix(Self.kept))))
    if shows.count > Self.mostShows { shows.removeFirst(shows.count - Self.mostShows) }
  }

  /// Records what a head scan found, when it reached far enough to say.
  public mutating func record(show: String, ads: [FoundAd], reached: Double) {
    guard reached >= Self.checkedSeconds else { return }
    record(show: show, hadAdAtStart: Self.hadAdAtStart(ads))
  }

  /// What was saved at `url`, or nothing when there is no file, it cannot be read or it is of
  /// another version.
  public static func load(from url: URL) -> ShowStarts {
    guard let data = try? Data(contentsOf: url),
      let saved = try? JSONDecoder().decode(ShowStarts.self, from: data),
      saved.version == currentVersion
    else { return ShowStarts() }
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
