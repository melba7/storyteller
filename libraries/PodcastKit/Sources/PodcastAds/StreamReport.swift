// LOFI-FORK: the stream replay's block of the scorecard text (see FORK.md and StreamScore.swift).
// Foundation only.
import Foundation

enum StreamReport {
  /// "101 of 219 breaks pass (46.1%); first 3 minutes 43 of 58, later 58 of 161; ..."
  static func barLine(_ bar: BarTotals) -> String {
    let minutes = Int(AdBar.earlySeconds / 60)
    return String(
      format:
        "%d of %d breaks pass (%.1f%%); first %d minutes %d of %d, later %d of %d; skips with no ad %d (%.1f per hour)",
      bar.passed, bar.breaks, bar.rate * 100, minutes, bar.earlyPassed, bar.earlyBreaks,
      bar.passed - bar.earlyPassed, bar.breaks - bar.earlyBreaks, bar.noAdSkips, bar.noAdPerHour)
  }

  /// The block for the rows that were streamed.
  static func lines(_ rows: [(name: String, stream: StreamNumbers)]) -> [String] {
    guard !rows.isEmpty else { return [] }
    let minutes = Int(AdBar.earlySeconds / 60)
    var out = [
      "Stream replay: every episode is played from the start as a stream, by a listener who taps play and never touches the phone, with the player's own skip rules. The speeds below are assumptions, not measurements.",
      "  " + StreamPace.standard.summary,
      "  " + StreamPace.slow.summary,
      "  The head scan waits for Apple's model at the steps that ask it, in every row, as on a phone with Apple Intelligence on (an assumption); the model's answers count only in the Apple row.",
      "  \"ready\" here means the same player with everything known at the start.",
    ]
    for row in rows {
      out.append("Row \"\(row.name)\" as a stream (standard pace): " + barLine(row.stream.standard))
      if let ready = row.stream.ready {
        out.append("  Ready (everything known at the start, the same player): " + barLine(ready))
      }
      out.append("  At the slow pace: " + barLine(row.stream.slow))
      for speed in row.stream.speeds ?? [] {
        out.append(
          String(
            format: "  Speech at %g times real time (other values standard): first %d minutes %d of %d (%d of %d in all)",
            speed.speech, minutes, speed.bar.earlyPassed, speed.bar.earlyBreaks, speed.bar.passed,
            speed.bar.breaks))
      }
    }
    out.append(
      "These speech speeds are assumptions: the phone's real speed is not measured yet, and the first \(minutes) minutes depend on it.")
    return out
  }
}
