// LOFI-FORK: keeps a new ad finder from hurting playback (see FORK.md and the round plan,
// section 8). Pure: Foundation only, no clock, no shared state.
import Foundation

// The API the phone's wiring uses. The file is Application Support/Podcasts/finder-guard.json.
//
//   FinderGuard.fileName                                  "finder-guard.json"
//   FinderGuard(appBuild: String)                         an empty guard for this build
//   FinderGuard.read(_ text: String?, appBuild:) -> FinderGuard   a damaged file reads as empty
//   FinderGuard.load(from url: URL, appBuild:) -> FinderGuard     a missing file reads as empty
//   var text: String                                      the file's text
//   func save(to url: URL) throws                         atomic; makes the folder
//
//   mutating func recover() -> [Trap]                     once at launch, before any begin
//   mutating func begin(finder:episode:)                  then save(to:) BEFORE the finder runs
//   mutating func end(finder:episode:)                    when the finder returns or throws
//   mutating func undone(finder:show:)                    the listener undid a skip it made
//   mutating func denied(finder:show:)                    the listener said "not an ad" to it
//   mutating func confirmed(finder:show:)                 the listener said "yes" to it
//   func mode(finder:show:episode:) -> FinderMode         .skip, .ask or .off
//
// Finder names are plain strings ("own-sound", "repeat-sound", "repeat-words", "meaning",
// "joints"). Swift cannot catch a trap, so a mark is written before a finder runs and cleared
// when it returns: a mark found at the next launch means the app died inside that finder.

/// What a finder may do on one episode of one show.
public enum FinderMode: String, Sendable, Equatable {
  /// Skip what it finds (as an `unsure` ad, so the listener can undo it).
  case skip
  /// Only ask about what it finds.
  case ask
  /// Do not run it.
  case off
}

/// The marks, traps and answers of the new finders, as a small value kept in one JSON file.
public struct FinderGuard: Codable, Sendable, Equatable {
  public static let fileName = "finder-guard.json"
  static let currentVersion = 1
  /// A file bigger than this reads as empty.
  static let maxFileBytes = 256 * 1024
  /// Longest finder, episode or show name kept (in Unicode scalars).
  static let maxNameLength = 80
  static let maxMarks = 20
  static let maxTrappedEpisodes = 100
  static let maxTrappedFinders = 20
  static let maxShows = 60
  static let maxFindersPerShow = 8
  /// How many of a finder's last answers on a show are looked at.
  static let answerWindow = 5
  /// Bad answers in the window that turn a finder to `ask` (undone) or `off` (denied).
  static let badAnswersToAct = 2
  /// Traps after which a finder is off everywhere. It never counts higher.
  static let trapLimit = 2

  struct Mark: Codable, Sendable, Equatable {
    var finder: String
    var episode: String
  }

  enum Answer: String, Codable, Sendable, Equatable { case undone, denied, confirmed }

  struct FinderAnswers: Codable, Sendable, Equatable {
    var finder: String
    var last: [Answer]
  }

  struct ShowAnswers: Codable, Sendable, Equatable {
    var show: String
    var finders: [FinderAnswers]
  }

  /// A finder found marked at launch: the app died while it ran on `episode`.
  public struct Trap: Sendable, Equatable {
    public var finder: String
    public var episode: String
    /// Whether this was its second trap, which switches it off everywhere.
    public var offEverywhere: Bool
  }

  var version = FinderGuard.currentVersion
  /// The app build the traps below belong to. A new build starts them again.
  public internal(set) var appBuild: String
  /// Finders that began and have not returned.
  var marks: [Mark] = []
  /// How many times each finder trapped in this build (at most `trapLimit`).
  var traps: [String: Int] = [:]
  /// Finders switched off for one episode because they trapped on it, oldest first.
  var trapped: [Mark] = []
  /// The listener's answers, the show answered for last at the end.
  var shows: [ShowAnswers] = []

  public init(appBuild: String) { self.appBuild = Self.name(appBuild) }

  // MARK: Marks and traps

  /// Writes a mark: this finder is about to run on this episode. Save the guard before it runs.
  public mutating func begin(finder: String, episode: String) {
    let mark = Mark(finder: Self.name(finder), episode: Self.name(episode))
    guard !mark.finder.isEmpty else { return }
    marks.removeAll { $0 == mark }
    marks.append(mark)
    clamp()
  }

  /// Clears the mark: the finder returned (with ads, with none or with an error).
  public mutating func end(finder: String, episode: String) {
    let mark = Mark(finder: Self.name(finder), episode: Self.name(episode))
    marks.removeAll { $0 == mark }
  }

  /// Turns the marks a crash left into traps: each finder is off for the episode it was on, and
  /// a second trap of one finder switches it off everywhere. Marks of one finder found together
  /// are one crash and count once. Call it once at launch, before any `begin`.
  @discardableResult
  public mutating func recover() -> [Trap] {
    let found = marks
    marks = []
    for finder in Set(found.map(\.finder)) {
      traps[finder] = min((traps[finder] ?? 0) + 1, Self.trapLimit)
    }
    for mark in found where !mark.episode.isEmpty {
      trapped.removeAll { $0 == mark }
      trapped.append(mark)
    }
    clamp()
    return found.map {
      Trap(finder: $0.finder, episode: $0.episode, offEverywhere: isOffEverywhere($0.finder))
    }
  }

  private func isOffEverywhere(_ finder: String) -> Bool {
    (traps[finder] ?? 0) >= Self.trapLimit
  }

  // MARK: Answers

  /// The listener undid a skip this finder made on this show.
  public mutating func undone(finder: String, show: String) { record(.undone, finder, show) }

  /// The listener answered "not an ad" to a stretch this finder asked about on this show.
  public mutating func denied(finder: String, show: String) { record(.denied, finder, show) }

  /// The listener answered "yes" to a stretch this finder asked about on this show. Without
  /// good answers the last five could never move on from two bad ones.
  public mutating func confirmed(finder: String, show: String) { record(.confirmed, finder, show) }

  private mutating func record(_ answer: Answer, _ finder: String, _ show: String) {
    let finder = Self.name(finder)
    let show = Self.name(show)
    guard !finder.isEmpty, !show.isEmpty else { return }
    var entry = shows.first { $0.show == show } ?? ShowAnswers(show: show, finders: [])
    var one = entry.finders.first { $0.finder == finder } ?? FinderAnswers(finder: finder, last: [])
    shows.removeAll { $0.show == show }
    entry.finders.removeAll { $0.finder == finder }
    one.last.append(answer)
    entry.finders.append(one)
    shows.append(entry)
    clamp()
  }

  // MARK: The decision

  /// What `finder` may do on `episode` of `show`. A name that is empty or unknown is not held
  /// back. Off everywhere (two traps) or off for the episode (a trap) comes first; then two
  /// denied answers in the last five turn it off for the show, and two undone skips make it ask.
  public func mode(finder: String, show: String, episode: String) -> FinderMode {
    let finder = Self.name(finder)
    guard !finder.isEmpty else { return .skip }
    if isOffEverywhere(finder) { return .off }
    let episode = Self.name(episode)
    if !episode.isEmpty, trapped.contains(Mark(finder: finder, episode: episode)) { return .off }
    let shown = shows.first { $0.show == Self.name(show) }
    let last = (shown?.finders.first { $0.finder == finder }?.last ?? []).suffix(Self.answerWindow)
    if last.filter({ $0 == .denied }).count >= Self.badAnswersToAct { return .off }
    if last.filter({ $0 == .undone }).count >= Self.badAnswersToAct { return .ask }
    return .skip
  }

  // MARK: Limits

  /// A name as kept: cut to its limit and trimmed. Empty means "no name".
  static func name(_ text: String) -> String {
    String(String.UnicodeScalarView(text.unicodeScalars.prefix(maxNameLength)))
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Cuts every list to its limit, the oldest going first, so the file stays small.
  mutating func clamp() {
    marks = Array(marks.suffix(Self.maxMarks))
    trapped = Array(trapped.suffix(Self.maxTrappedEpisodes))
    var counts = traps.compactMapValues { $0 > 0 ? min($0, Self.trapLimit) : nil }
    if counts.count > Self.maxTrappedFinders {
      let keep = counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        .prefix(Self.maxTrappedFinders).map(\.key)
      counts = counts.filter { keep.contains($0.key) }
    }
    traps = counts
    shows = shows.suffix(Self.maxShows).map { show in
      var show = show
      show.finders = Array(show.finders.suffix(Self.maxFindersPerShow)).map { one in
        var one = one
        one.last = Array(one.last.suffix(Self.answerWindow))
        return one
      }
      return show
    }
  }
}

// MARK: The file

extension FinderGuard {
  /// The guard in `text`, made for `appBuild`. Text that is missing, too big, damaged or of an
  /// unknown version reads as an empty guard. Text from another build keeps the listener's
  /// answers but starts the marks and traps again: the new build may have fixed the crash.
  public static func read(_ text: String?, appBuild: String) -> FinderGuard {
    let build = name(appBuild)
    guard let text, text.utf8.count <= maxFileBytes,
      var file = try? JSONDecoder().decode(FinderGuard.self, from: Data(text.utf8)),
      file.version == currentVersion
    else { return FinderGuard(appBuild: build) }
    if file.appBuild != build {
      file.appBuild = build
      file.marks = []
      file.traps = [:]
      file.trapped = []
    }
    file.clamp()
    return file
  }

  /// The guard saved at `url`. A missing, unreadable or too big file reads as an empty guard.
  public static func load(from url: URL, appBuild: String) -> FinderGuard {
    guard let handle = try? FileHandle(forReadingFrom: url) else {
      return FinderGuard(appBuild: name(appBuild))
    }
    defer { try? handle.close() }
    // One byte more than the limit is enough to know the file is too big, whatever its size.
    let data = (try? handle.read(upToCount: maxFileBytes + 1)) ?? Data()
    return read(String(data: data, encoding: .utf8), appBuild: appBuild)
  }

  /// The guard as the text of its file: one line of JSON with sorted keys.
  public var text: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(self) else { return "" }
    return String(decoding: data, as: UTF8.self)
  }

  /// Writes the file whole in one step (a half-written file is never seen), making its folder.
  public func save(to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url, options: .atomic)
  }
}
