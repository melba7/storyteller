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

  /// The block for the rows that were streamed. `waiting` is how many of the `of` replayed episodes
  /// waited for Apple's model in the head scan (those of shows whose Apple level is skip); with
  /// none, the line says the replay did not ask it.
  static func lines(
    _ rows: [(name: String, stream: StreamNumbers)], waiting: (episodes: Int, of: Int) = (0, 0)
  ) -> [String] {
    guard !rows.isEmpty else { return [] }
    let minutes = Int(AdBar.earlySeconds / 60)
    // With --speech the standard pace has the speech speed the phone measured.
    let measured = rows.first?.stream.speech
    let pace = measured.map { StreamPace.measured(speech: $0) } ?? .standard
    var out = [
      "Stream replay: every episode is played from the start as a stream, by a listener who taps play and never touches the phone, with the player's own skip rules. "
        + (measured == nil
          ? "The speeds below are assumptions, not measurements."
          : "The speeds below are assumptions, apart from the speech speed of the measured pace."),
      "  " + pace.summary,
      "  " + StreamPace.slow.summary,
      "  The head scan waits for Apple's model only on a show whose Apple level is skip in show-settings.json (ask when the file says nothing), as the phone does, and then at the steps that ask it, in every row (an assumption: a phone with Apple Intelligence on). Here it waits in \(waiting.episodes) of \(waiting.of) episodes; in the others it neither asks nor waits for the model. The model's answers count only in the Apple row, and only the ones that skip.",
      "  \"ready\" here means the same player with everything known at the start: the finished file of an episode that was read to its end before it is played.",
    ]
    for row in rows {
      out.append("Row \"\(row.name)\" as a stream (\(pace.name) pace): " + barLine(row.stream.standard))
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
    if let measured {
      out.append(
        "The speech speed of the measured pace, \(String(format: "%g", measured)) s of audio per second, was measured on the phone (teach_pace.py reads its diary). The other speeds and the slow pace are assumptions, and the first \(minutes) minutes depend on them.")
    } else {
      out.append(
        "These speech speeds are assumptions: the phone's real speed is not measured yet, and the first \(minutes) minutes depend on it.")
    }
    return out
  }
}
