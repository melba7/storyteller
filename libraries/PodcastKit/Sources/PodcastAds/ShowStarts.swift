// LOFI-FORK: whether a show's episodes start with an ad (see FORK.md).
//
// One bit per show, kept beside the known ads: did each of its last five checked episodes have
// no ad before 30 seconds. A show that does not start with an ad is not waited for (StartHold).
// Beside each bit, from version 2 on, the second at which that opening ad ended, so a show the
// Mac never sampled can still be given the longer wait and the first look at its usual end
// (`habits()` in ShowHabits+Own.swift). Not a template of where ads are: a template that says
// "skip the first 60 seconds" is wrong whenever the host inserts a different number of ads.
// Foundation only.
import Foundation

public struct ShowStarts: Codable, Sendable, Equatable {
  /// Version 2 keeps where each opening ad ended. A version 1 file is still read, its ends unknown.
  public static let currentVersion = 2
  static let oldestVersion = 1
  public static let fileName = "show-starts.json"

  /// How many episodes of a show are remembered, and how many shows.
  public static let kept = 5
  public static let mostShows = 200
  /// A file larger than this is not read: 200 shows take about 30 KB.
  public static let maxBytes = 1_000_000
  /// An ad that starts before this many seconds is an ad at the start of an episode.
  public static let window = 30.0
  /// A scan that did not reach this many seconds did not check the start well enough to count:
  /// the model may only answer for the first seconds from the 60 second step on.
  public static let checkedSeconds = 60.0
  /// Ads that start this many seconds after the last one ended are one opening, as the Mac counts
  /// it (`JOIN_SECONDS` in teach_habits.py).
  static let joinSeconds = 20.0
  /// An opening end later than this many seconds (a day) is not believed. It keeps the sums finite.
  public static let latestEnd = 86_400.0

  /// One show's results, the newest last: whether that episode had an ad at its start.
  public struct Show: Codable, Sendable, Equatable {
    public var id: String
    public var results: [Bool]
    /// Beside each result, where that episode's opening ad ended, in seconds. Nil for an episode
    /// that had no opening ad or whose end was not seen. The whole list is nil when the ends are
    /// unknown (a version 1 file); otherwise it is as long as `results`.
    public var ends: [Double?]?

    /// The ends beside the results: all unknown when they are not known or do not fit.
    var knownEnds: [Double?] {
      if let ends, ends.count == results.count { return ends }
      return Array(repeating: nil, count: results.count)
    }

    /// At most `kept` results, and only the ends that can be believed: not a NaN, not negative,
    /// not past `latestEnd`, and only for an episode that had an opening ad.
    func normalized() -> Show {
      let hadAd = Array(results.suffix(ShowStarts.kept))
      guard let ends, ends.count == results.count else {
        return Show(id: id, results: hadAd, ends: nil)
      }
      let believed = zip(hadAd, ends.suffix(ShowStarts.kept)).map { pair in
        pair.0 ? ShowStarts.believed(pair.1) : nil
      }
      return Show(id: id, results: hadAd, ends: believed)
    }
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

  /// Where the opening ad ended: the end of the first skipped ad that starts inside the first
  /// `window` seconds, grown over each skipped ad that starts within `joinSeconds` of where the
  /// opening ended so far. Nil when there is no opening ad or its end is not a number.
  public static func openingEnd(_ ads: [FoundAd]) -> Double? {
    let skipped = ads.filter { $0.confidence >= .unsure && $0.start.isFinite }
      .sorted { $0.start < $1.start }
    guard let first = skipped.first, first.start < window else { return nil }
    var end = first.end
    for ad in skipped.dropFirst() {
      if ad.start - end > joinSeconds { break }
      end = max(end, ad.end)
    }
    return believed(end)
  }

  /// `end` when it can be an end: a number above zero and not past `latestEnd`.
  static func believed(_ end: Double?) -> Double? {
    guard let end, end.isFinite, end > 0, end <= latestEnd else { return nil }
    return end
  }

  /// Notes one more episode of the show. `openingEnd` is where its opening ad ended, when it had
  /// one and the end is known; it is kept beside the bit.
  public mutating func record(show: String, hadAdAtStart: Bool, openingEnd: Double? = nil) {
    let known = shows.first(where: { $0.id == show })
    var results = known?.results ?? []
    var ends = known?.knownEnds ?? []
    results.append(hadAdAtStart)
    ends.append(hadAdAtStart ? Self.believed(openingEnd) : nil)
    shows.removeAll { $0.id == show }
    shows.append(
      Show(
        id: show, results: Array(results.suffix(Self.kept)), ends: Array(ends.suffix(Self.kept))))
    if shows.count > Self.mostShows { shows.removeFirst(shows.count - Self.mostShows) }
  }

  /// Records what a head scan found, when it reached far enough to say. The opening ad's end is
  /// kept only when the scan heard `joinSeconds` past it: by the Mac's rule a later ad that starts
  /// within that long still joins the opening, so an end nearer the edge of what was checked is
  /// not known yet.
  public mutating func record(show: String, ads: [FoundAd], reached: Double) {
    guard reached >= Self.checkedSeconds else { return }
    let end = Self.openingEnd(ads).flatMap { $0 + Self.joinSeconds <= reached ? $0 : nil }
    record(show: show, hadAdAtStart: Self.hadAdAtStart(ads), openingEnd: end)
  }

  /// What was saved at `url`, or nothing when there is no file, it cannot be read, it is larger
  /// than `maxBytes` or it is of a version this app does not know. A version 1 file reads with its
  /// ends unknown, and is written as version 2.
  public static func load(from url: URL) -> ShowStarts {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return ShowStarts() }
    defer { try? handle.close() }
    // One byte more than the limit is read, to tell a file at the limit from one over it.
    guard let data = try? handle.read(upToCount: maxBytes + 1), data.count <= maxBytes,
      var saved = try? JSONDecoder().decode(ShowStarts.self, from: data),
      (oldestVersion...currentVersion).contains(saved.version)
    else { return ShowStarts() }
    saved.version = currentVersion
    saved.shows = saved.shows.suffix(mostShows).map { $0.normalized() }
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
