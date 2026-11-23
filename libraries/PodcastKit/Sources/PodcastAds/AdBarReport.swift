// LOFI-FORK: the bar's block of the scorecard text, in plain English (see FORK.md and AdBar.swift).
// Foundation only.
import Foundation

enum AdBarReport {
  /// The block that follows the scorecard: one line for each row that has a bar, then why breaks
  /// fail in the last row and how the first three minutes did. Empty when no row has a bar.
  static func lines(_ rows: [ScorecardRow]) -> [String] {
    let scored = rows.compactMap { row in row.bar.map { (name: row.name, bar: $0) } }
    guard let last = scored.last else { return [] }
    let heard = Int(AdBar.heardSeconds), cut = Int(AdBar.cutSeconds)
    var out = [
      "The bar: an ad break passes when it is skipped with no tap, at most \(heard) s of it is heard, and the skip starts and lands within \(cut) s of it."
    ]
    let width = max(24, scored.map(\.name.count).max() ?? 0)
    out.append(
      "  " + "Row".padding(toLength: width, withPad: " ", startingAt: 0)
        + "  Breaks  Pass   Rate   Skips with no ad (per hour)")
    for (name, bar) in scored {
      out.append(
        "  " + name.padding(toLength: width, withPad: " ", startingAt: 0)
          + String(format: "  %6d %5d %6.1f%%   %d (%.1f)", bar.breaks, bar.passed, bar.rate * 100,
            bar.noAdSkips, bar.noAdPerHour))
    }
    let failing = BarCause.allCases.map { ($0, last.bar.count($0)) }.filter { $0.1 > 0 }
      .sorted { $0.1 > $1.1 }
    if failing.isEmpty {
      out.append("Why breaks fail in the last row: no break fails.")
    } else {
      out.append(
        "Why breaks fail in the last row: "
          + failing.map { "\($0.0.label) \($0.1)" }.joined(separator: ", ") + ".")
    }
    let bar = last.bar
    out.append(
      "First \(Int(AdBar.earlySeconds / 60)) minutes: \(bar.earlyPassed) of \(bar.earlyBreaks) pass. Later: \(bar.passed - bar.earlyPassed) of \(bar.breaks - bar.earlyBreaks) pass."
    )
    return out
  }
}
