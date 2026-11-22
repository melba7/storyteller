// LOFI-FORK: the scorecard in plain words, and the history of scorecards (see FORK.md). Foundation
// only.
import Foundation

/// The totals of one scorecard run, as kept in `scorecard.json`.
public struct ScorecardRun: Codable, Sendable, Equatable {
  /// When it ran, in milliseconds since 1970.
  public var at: Int64
  public var title: String
  public var total: ScoreTotals

  public init(at: Int64, title: String, total: ScoreTotals) {
    self.at = at
    self.title = title
    self.total = total
  }
}

/// `scorecard.json`: the runs so far, newest last.
public struct ScorecardHistory: Codable, Sendable, Equatable {
  public static let currentVersion = 1
  public static let fileName = "scorecard.json"
  public static let mostRuns = 50

  public var version: Int
  public var runs: [ScorecardRun]

  public init(runs: [ScorecardRun] = []) {
    version = Self.currentVersion
    self.runs = runs
  }

  /// What was saved at `url`, or an empty history when there is no file or it is damaged.
  public static func load(from url: URL) -> ScorecardHistory {
    guard let data = try? Data(contentsOf: url),
      let saved = try? JSONDecoder().decode(ScorecardHistory.self, from: data),
      saved.version == currentVersion
    else { return ScorecardHistory() }
    return saved
  }

  /// Adds a run, keeping the newest 50.
  public mutating func append(_ run: ScorecardRun) {
    runs.append(run)
    if runs.count > Self.mostRuns { runs.removeFirst(runs.count - Self.mostRuns) }
  }

  public func save(to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    try encoder.encode(self).write(to: url, options: .atomic)
  }
}

public enum AdScoreReport {
  static let mostShows = 25

  /// The scorecard in plain English. `layers` are the caught shares (0 to 1) of the detectors
  /// that each add one layer; `previous` is the run before this one.
  public static func text(
    _ card: Scorecard, title: String, layers: [(name: String, caughtShare: Double)],
    previous: ScorecardRun?
  ) -> String {
    let total = card.total
    var out = [title, ""]
    if total.ads == 0 {
      out.append("No marked ads in these episodes.")
    } else {
      out.append("Ads caught: \(total.caught) of \(total.ads) (\(percent(total.caught, total.ads))).")
    }
    out.append("Ad time still heard: \(time(total.heardSeconds)).")
    out.append(
      "Show time cut by mistake: \(time(total.cutSeconds)) (\(share(total.cutSeconds, total.showSeconds)) of the show), in \(count(total.wrongSkips, "wrong skip")).")
    out.append("")
    let names = [
      ("sponsor", "Sponsor ads"), ("network_promo", "Network and house promos"),
      ("host_ask", "Host asks"),
      ("intro_credits", "Intros and credits (not skipped unless you turn that on)"),
    ]
    for (sort, label) in names {
      let own = total.bySort[sort] ?? SortScore()
      if own.ads == 0 {
        out.append("\(label): none marked.")
      } else {
        out.append(
          "\(label): caught \(own.caught) of \(own.ads) (\(percent(own.caught, own.ads))), \(time(own.heardSeconds)) still heard.")
      }
    }
    if total.openingAds == 0 {
      out.append("Openings: no episode opens with an ad.")
    } else {
      out.append(
        "Openings: \(count(total.openingAds, "ad")) in the first 30 seconds; the first look finds \(total.openingKnown) of them (\(percent(total.openingKnown, total.openingAds))).")
    }
    if !layers.isEmpty {
      var parts: [String] = []
      var last: Int?
      for layer in layers {
        let now = Int((layer.caughtShare * 100).rounded())
        var gain = ""
        if let last { gain = " (\(now >= last ? "+" : "")\(now - last) points)" }
        parts.append("\(layer.name) \(now)%\(gain)")
        last = now
      }
      out.append("What each layer adds: " + parts.joined(separator: ", ") + ".")
    }
    if let before = previous?.total {
      out.append(
        "Since the last scorecard: ads caught \(percent(total.caught, total.ads)) (was \(percent(before.caught, before.ads))), ad time heard \(time(total.heardSeconds)) (was \(time(before.heardSeconds))), show time cut \(time(total.cutSeconds)) (was \(time(before.cutSeconds))).")
    }
    out.append("")
    out.append(contentsOf: table(card.shows))
    return out.joined(separator: "\n")
  }

  private static func table(_ shows: [ShowScore]) -> [String] {
    guard !shows.isEmpty else { return [] }
    var rows = ["The shows, worst first (most ad time still heard):"]
    for show in shows.prefix(mostShows) {
      let name = String((show.show.isEmpty ? show.feed : show.show).prefix(32))
      let total = show.total
      rows.append(
        "  " + name.padding(toLength: 32, withPad: " ", startingAt: 0)
          + "  caught \(total.caught) of \(total.ads), heard \(time(total.heardSeconds)), cut \(time(total.cutSeconds))")
    }
    if shows.count > mostShows { rows.append("  and \(shows.count - mostShows) more shows.") }
    return rows
  }

  private static func count(_ number: Int, _ noun: String) -> String {
    "\(number) \(noun)\(number == 1 ? "" : "s")"
  }

  /// A whole percent, or "no ads" when there is nothing to divide.
  private static func percent(_ part: Int, _ whole: Int) -> String {
    whole == 0 ? "no ads" : "\(Int((Double(part) / Double(whole) * 100).rounded()))%"
  }

  /// A share with one decimal place; 0% when there is no show at all.
  private static func share(_ part: Double, _ whole: Double) -> String {
    guard whole > 0 else { return "0%" }
    return String(format: "%.1f%%", part / whole * 100)
  }

  /// "3 min 05 s" or "42 s".
  static func time(_ seconds: Double) -> String {
    let whole = Int(seconds.rounded())
    return whole < 60 ? "\(whole) s" : "\(whole / 60) min \(String(format: "%02d", whole % 60)) s"
  }
}
