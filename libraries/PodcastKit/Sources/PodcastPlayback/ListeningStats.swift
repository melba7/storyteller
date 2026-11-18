// LOFI-FORK: the podcast player's listening stats (see FORK.md). Plain values, no AVFoundation,
// so they test on Linux. The player adds seconds as it plays, and the app saves them in
// `Podcasts/stats.json` and shows them in Profile. Days are the phone's local days.
import Foundation

/// What the ad counters count: a skip the player made, one the listener undid (it was no ad), and
/// one the listener found too far (they went back into the ad).
public enum AdCount: Sendable {
  case skipped, undone, tooFar
}

/// The five ways listening takes less time than the audio is long.
public enum StatsCategory: String, CaseIterable, Sendable {
  case speed, skipping, trim, ads, chapters
}

public struct ListeningStats: Codable, Sendable, Equatable {
  /// The per-day map keeps today and the 89 days before it.
  public static let keptDays = 90

  /// Wall-clock seconds a podcast was actually playing.
  public private(set) var listened = 0.0
  /// Audio heard minus the time it took, because of the speed.
  public private(set) var savedBySpeed = 0.0
  /// Intros and outros that a show's settings skipped.
  public private(set) var savedBySkipping = 0.0
  public private(set) var savedByTrim = 0.0
  /// Seconds of ads the player skipped, minus the skips that were undone.
  public private(set) var savedByAds = 0.0
  public private(set) var savedByChapters = 0.0
  /// How many ads the player skipped, and how many of those skips the listener undid or found
  /// too far. They say how well ad skipping goes.
  public private(set) var adSkips = 0
  public private(set) var adUndone = 0
  public private(set) var adTooFar = 0
  /// Seconds listened per local day, keyed "yyyy-MM-dd".
  public private(set) var days: [String: Double] = [:]

  public init() {}

  // MARK: Reading

  public func saved(_ category: StatsCategory) -> Double {
    switch category {
    case .speed: return savedBySpeed
    case .skipping: return savedBySkipping
    case .trim: return savedByTrim
    case .ads: return savedByAds
    case .chapters: return savedByChapters
    }
  }

  public var totalSaved: Double { StatsCategory.allCases.reduce(0) { $0 + saved($1) } }

  // MARK: Adding

  /// A number worth counting: finite and more than zero.
  private static func usable(_ seconds: Double) -> Bool { seconds.isFinite && seconds > 0 }

  public mutating func addListened(_ seconds: Double, at date: Date, calendar: Calendar = .current) {
    guard Self.usable(seconds) else { return }
    listened += seconds
    days[Self.dayKey(date, calendar: calendar), default: 0] += seconds
    prune(today: date, calendar: calendar)
  }

  public mutating func addSaved(_ category: StatsCategory, _ seconds: Double) {
    guard Self.usable(seconds) else { return }
    set(category, saved(category) + seconds)
  }

  public mutating func countAd(_ what: AdCount) {
    switch what {
    case .skipped: adSkips += 1
    case .undone: adUndone += 1
    case .tooFar: adTooFar += 1
    }
  }

  /// Takes a saving back (an ad skip that was undone). It never goes below zero.
  public mutating func removeSaved(_ category: StatsCategory, _ seconds: Double) {
    guard Self.usable(seconds) else { return }
    set(category, max(0, saved(category) - seconds))
  }

  private mutating func set(_ category: StatsCategory, _ value: Double) {
    switch category {
    case .speed: savedBySpeed = value
    case .skipping: savedBySkipping = value
    case .trim: savedByTrim = value
    case .ads: savedByAds = value
    case .chapters: savedByChapters = value
    }
  }

  /// Adds another set of stats to this one.
  public mutating func merge(
    _ other: ListeningStats, today: Date = Date(), calendar: Calendar = .current
  ) {
    listened += other.listened
    for category in StatsCategory.allCases { addSaved(category, other.saved(category)) }
    adSkips += other.adSkips
    adUndone += other.adUndone
    adTooFar += other.adTooFar
    for (day, seconds) in other.days { days[day, default: 0] += seconds }
    prune(today: today, calendar: calendar)
  }

  // MARK: Days

  /// "2026-11-17" for the day `date` falls on in `calendar`.
  public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    func pad(_ value: Int?, _ width: Int) -> String {
      let text = String(value ?? 0)
      return String(repeating: "0", count: max(0, width - text.count)) + text
    }
    return "\(pad(parts.year, 4))-\(pad(parts.month, 2))-\(pad(parts.day, 2))"
  }

  /// Whether `text` is a real-looking "yyyy-MM-dd" day.
  static func isDayKey(_ text: String) -> Bool {
    let parts = text.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
      parts.allSatisfy({ $0.allSatisfy(\.isASCII) }),
      Int(parts[0]) != nil, let month = Int(parts[1]), let day = Int(parts[2])
    else { return false }
    return (1...12).contains(month) && (1...31).contains(day)
  }

  /// Forgets the days before the last `keptDays`.
  public mutating func prune(today: Date, calendar: Calendar = .current) {
    guard let first = calendar.date(byAdding: .day, value: -(Self.keptDays - 1), to: today)
    else { return }
    let oldest = Self.dayKey(first, calendar: calendar)
    days = days.filter { $0.key >= oldest }
  }

  // MARK: Saving

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    return try encoder.encode(self)
  }

  /// Stats from saved JSON. Anything unreadable is no stats, and a number that is not a good
  /// one (or a day that is not a day) is left out.
  public static func decode(_ data: Data) -> ListeningStats {
    (try? JSONDecoder().decode(ListeningStats.self, from: data)) ?? ListeningStats()
  }

  private enum Keys: String, CodingKey {
    case listened, savedBySpeed, savedBySkipping, savedByTrim, savedByAds, savedByChapters, days
    case adSkips, adUndone, adTooFar
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    func number(_ key: Keys) -> Double {
      let value = (try? c.decodeIfPresent(Double.self, forKey: key)) ?? 0
      return Self.usable(value) ? value : 0
    }
    listened = number(.listened)
    savedBySpeed = number(.savedBySpeed)
    savedBySkipping = number(.savedBySkipping)
    savedByTrim = number(.savedByTrim)
    savedByAds = number(.savedByAds)
    savedByChapters = number(.savedByChapters)
    // A count is a whole number of zero or more; anything else is dropped.
    func count(_ key: Keys) -> Int { max(0, (try? c.decodeIfPresent(Int.self, forKey: key)) ?? 0) }
    adSkips = count(.adSkips)
    adUndone = count(.adUndone)
    adTooFar = count(.adTooFar)
    let saved = (try? c.decodeIfPresent([String: Double].self, forKey: .days)) ?? [:]
    days = saved.filter { Self.isDayKey($0.key) && Self.usable($0.value) }
  }

  // MARK: Intros

  /// The seconds an intro moved the start of an episode by, which is what it saved.
  public static func introSkipped(
    savedPosition: Double, duration: Double?, played: Bool, intro: Double
  ) -> Double {
    let resume = ResumeRule.start(savedPosition: savedPosition, duration: duration, played: played)
    let start = ShowRules.start(
      savedPosition: savedPosition, duration: duration, played: played, intro: intro)
    return max(0, start - resume)
  }
}

/// `stats.json`: the stats, kept next to the other files the player reads with no JavaScript.
public enum ListeningStatsFile {
  /// The stats saved in `file`. A missing or unreadable file means none.
  public static func load(from file: URL) -> ListeningStats {
    guard let data = try? Data(contentsOf: file) else { return ListeningStats() }
    return ListeningStats.decode(data)
  }

  public static func save(_ stats: ListeningStats, to file: URL) throws {
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try stats.encoded().write(to: file, options: .atomic)
  }
}

/// Turns the player's ticks into the time listened and the time saved by speed. A tick counts
/// only while the player is really playing and the last tick was just before it.
public struct ListenClock: Sendable, Equatable {
  /// A longer gap between two ticks (the app was suspended, a seek, a stall) is not counted.
  public static let longestGap = 1.5
  /// The fastest speed the player has, so a wild rate can't count more than that.
  private static let fastest = 4.0

  private var last: Double?

  public init() {}

  /// What this tick adds, in seconds. `now` is a steady clock such as the system uptime.
  public mutating func tick(at now: Double, playing: Bool, rate: Double) -> (
    listened: Double, bySpeed: Double
  ) {
    guard playing, now.isFinite else {
      last = nil
      return (0, 0)
    }
    defer { last = now }
    guard let last, now > last, now - last <= Self.longestGap else { return (0, 0) }
    let elapsed = now - last
    guard rate.isFinite else { return (elapsed, 0) }
    return (elapsed, max(0, elapsed * (min(rate, Self.fastest) - 1)))
  }
}
