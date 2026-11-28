// LOFI-FORK: keeps a new ad finder from hurting playback (see FORK.md and the round plan,
// section 8). Foundation only, with no clock of its own (every call that needs the time is given
// it) and no shared state. `load(from:appBuild:)` and `save(to:now:)` are the only disk access;
// everything else works on the value in memory.
import Foundation

// WHY IT EXISTS. Swift cannot catch a trap. So before a new finder runs the guard writes a mark
// to disk, and clears it when the finder returns. A mark found at the next launch means the
// app died inside that finder: it is off for that episode, and after a second such crash in the
// same app build it is off everywhere until the next build.
//
// HOW THE PHONE'S WIRING MUST USE IT (every point matters):
//  1. Load the file and call `recover()` ONCE per launch, under the one lock, and `save` after
//     it. Never call `recover()` after a `begin` in the same launch: that turns a live mark
//     into a trap.
//  2. Keep ONE guard instance behind ONE lock. It is a value type: two copies saving out of
//     order bring back a cleared mark or lose a live one. Every change (begin, end, an answer,
//     recover) is made on that instance and saved before the lock is let go.
//  3. `begin`, then `save`. If the save throws, do not run the finder.
//  4. When the finder returns or throws, in a `defer`: `end`, then `save`.
//  5. Swift Task cancellation does not happen when the app is suspended, when background time
//     runs out or when the app is killed. So run a new finder only while background time is
//     held, and in EVERY expiration handler call `end` for each live mark and `save`, stop the
//     finder, and only then give the time back.
//  6. An iOS kill with a mark on disk looks exactly like a trap. Two of them in one build switch
//     that finder off everywhere until the next build.
//
// ANSWERS. `undone`, `denied` and `confirmed` record what the listener did with a finder's
// skip or question on a show. The rule looks at the last five ANSWERS of that finder on that
// show (not the last five skips), and only at answers from the last 30 days: older ones are
// ignored when the mode is decided and are not written to the file.
//
// THE API (the file is Application Support/Podcasts/finder-guard.json):
//
//   FinderGuard.fileName                                   "finder-guard.json"
//   FinderGuard(appBuild: String)                          an empty guard for this build
//   FinderGuard.read(_ text: String?, appBuild:) -> FinderGuard    damaged text reads as empty
//   FinderGuard.load(from url: URL, appBuild:) -> FinderGuard      a missing file reads as empty
//   func text(now: Date) -> String                         the file's text, old answers left out
//   func save(to url: URL, now: Date) throws               atomic; makes the folder
//
//   mutating func recover() -> [Trap]                      once per launch, before any begin
//   mutating func begin(finder:episode:)                   then save BEFORE the finder runs
//   mutating func end(finder:episode:)                     when the finder returns or throws
//   mutating func undone(finder:show:now:)                 the listener undid a skip it made
//   mutating func denied(finder:show:now:)                 the listener said "not an ad" to it
//   mutating func confirmed(finder:show:now:)              the listener said "yes" to it
//   func mode(finder:show:episode:now:) -> FinderMode      .skip, .ask or .off
//
// Finder names are plain strings ("own-sound", "repeat-sound", "repeat-words", "meaning",
// "joints").

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
  /// An answer older than this (in seconds) is ignored and not written. One dated further
  /// ahead than this (a clock that was wrong) is ignored too.
  static let answerLife: Double = 30 * 24 * 3600

  struct Mark: Codable, Sendable, Equatable {
    var finder: String
    var episode: String
  }

  enum Answer: String, Codable, Sendable, Equatable { case undone, denied, confirmed }

  /// One answer and when it was given (seconds since 1970).
  struct Given: Codable, Sendable, Equatable {
    var answer: Answer
    var at: Int
  }

  struct FinderAnswers: Codable, Sendable, Equatable {
    var finder: String
    var last: [Given]
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
      // A count read from a file that cannot be right is brought into range first, so adding
      // one cannot overflow.
      traps[finder] = min(max(0, traps[finder] ?? 0), Self.trapLimit - 1) + 1
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
  public mutating func undone(finder: String, show: String, now: Date) {
    record(.undone, finder, show, now)
  }

  /// The listener answered "not an ad" to a stretch this finder asked about on this show.
  public mutating func denied(finder: String, show: String, now: Date) {
    record(.denied, finder, show, now)
  }

  /// The listener answered "yes" to a stretch this finder asked about on this show. Without
  /// good answers the last five could never move on from two bad ones.
  public mutating func confirmed(finder: String, show: String, now: Date) {
    record(.confirmed, finder, show, now)
  }

  private mutating func record(_ answer: Answer, _ finder: String, _ show: String, _ now: Date) {
    let finder = Self.name(finder)
    let show = Self.name(show)
    // The Mac's prepared ads are not a finder the listener's answers can switch off.
    guard !finder.isEmpty, !show.isEmpty, finder != PreparedAds.source else { return }
    prune(now: now)
    var entry = shows.first { $0.show == show } ?? ShowAnswers(show: show, finders: [])
    var one = entry.finders.first { $0.finder == finder } ?? FinderAnswers(finder: finder, last: [])
    shows.removeAll { $0.show == show }
    entry.finders.removeAll { $0.finder == finder }
    one.last.append(Given(answer: answer, at: Self.seconds(now)))
    entry.finders.append(one)
    shows.append(entry)
    clamp()
  }

  /// Whether an answer still counts at `now`: given within the last 30 days (or, for a clock
  /// that was wrong, not more than 30 days ahead).
  private static func counts(_ given: Given, at now: Int) -> Bool {
    abs(Double(now) - Double(given.at)) <= answerLife
  }

  /// A date as whole seconds. A date that is not a number counts as 0 and a huge one is cut, so
  /// nothing here can trap.
  static func seconds(_ date: Date) -> Int {
    let time = date.timeIntervalSince1970
    guard time.isFinite else { return 0 }
    return Int(max(-1e11, min(1e11, time)))
  }

  /// Drops the answers that no longer count at `now`, and the finders and shows left with none.
  mutating func prune(now: Date) {
    let moment = Self.seconds(now)
    shows = shows.compactMap { show in
      var show = show
      show.finders = show.finders.compactMap { one in
        var one = one
        one.last = one.last.filter { Self.counts($0, at: moment) }
        return one.last.isEmpty ? nil : one
      }
      return show.finders.isEmpty ? nil : show
    }
  }

  // MARK: The decision

  /// What `finder` may do on `episode` of `show`. A name that is empty or unknown is not held
  /// back. Off everywhere (two traps) or off for the episode (a trap) comes first; then two
  /// denied answers in the last five turn it off for the show, and two undone skips make it ask.
  /// Only answers from the last 30 days before `now` count.
  public func mode(finder: String, show: String, episode: String, now: Date) -> FinderMode {
    let finder = Self.name(finder)
    guard !finder.isEmpty else { return .skip }
    if isOffEverywhere(finder) { return .off }
    let episode = Self.name(episode)
    if !episode.isEmpty, trapped.contains(Mark(finder: finder, episode: episode)) { return .off }
    let shown = shows.first { $0.show == Self.name(show) }
    let moment = Self.seconds(now)
    let last = (shown?.finders.first { $0.finder == finder }?.last ?? [])
      .filter { Self.counts($0, at: moment) }.suffix(Self.answerWindow).map(\.answer)
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
