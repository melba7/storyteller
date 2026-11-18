// LOFI-FORK: the text `podcast-ads --edges` prints about an episode's ad edges (see FORK.md).
//
// It says, for each ad, what the model said and what each step did to the ends (the "show is
// back" trim, the carried-on lines, the landing), shows the lines around each edge, and says what
// the transcript's word times look like (do they show pauses?). Foundation only, so the tests
// run on Linux.
import Foundation
import PodcastTranscripts

/// What the transcript's words and lines look like.
public struct TextStats: Equatable, Sendable {
  public var lines: Int
  public var words: Int
  /// The share of neighbouring words with at least `AdRules.pause` seconds between them.
  public var gapShare: Double
  /// The share of neighbouring words where one ends exactly where the next starts.
  public var touchingShare: Double
  public var wordsPerLine: Double
  public var secondsPerLine: Double
}

public enum AdEdgeReport {
  public static func stats(of transcript: Transcript) -> TextStats {
    let gaps = zip(transcript.words, transcript.words.dropFirst()).map { $1.start - $0.end }
    func share(_ test: (Double) -> Bool) -> Double {
      gaps.isEmpty ? 0 : Double(gaps.filter(test).count) / Double(gaps.count)
    }
    let lines = Double(max(1, transcript.lines.count))
    return TextStats(
      lines: transcript.lines.count, words: transcript.words.count,
      gapShare: share { $0 >= AdRules.pause }, touchingShare: share { abs($0) < 0.001 },
      wordsPerLine: Double(transcript.words.count) / lines,
      secondsPerLine: transcript.lines.reduce(0) { $0 + ($1.end - $1.start) } / lines)
  }

  public static func lines(for stats: TextStats) -> [String] {
    guard stats.words > 1 else { return ["The transcript has too few words to say anything."] }
    let reading =
      stats.touchingShare >= 0.9
      ? "Each word ends where the next starts, so the word times hide the pauses."
      : "The word times show the pauses."
    return [
      "Transcript: \(stats.lines) lines, \(stats.words) words.",
      "Neighbouring words with a gap of \(AdRules.pause) s or more: \(percent(stats.gapShare)).",
      "Neighbouring words where one ends exactly where the next starts: "
        + "\(percent(stats.touchingShare)). \(reading)",
      String(
        format: "A line has %.1f words and lasts %.1f s on average.", stats.wordsPerLine,
        stats.secondsPerLine),
    ]
  }

  private static func percent(_ share: Double) -> String { String(format: "%.1f %%", share * 100) }

  /// "00:01:19.8": hours, minutes, seconds and tenths, rounded to the nearest tenth.
  public static func clock(_ seconds: Double) -> String {
    let tenths = Int((max(0, seconds) * 10).rounded())
    return String(
      format: "%02d:%02d:%02d.%d", tenths / 36000, tenths / 600 % 60, tenths / 10 % 60, tenths % 10)
  }

  private static func signed(_ seconds: Double) -> String { String(format: "%+.1f s", seconds) }

  private static func listed(_ lines: [NumberedLine]) -> String {
    lines.isEmpty ? "none" : lines.map { "[\($0.number)] \"\($0.text)\"" }.joined(separator: ", ")
  }

  /// The trace of one ad as lines of text. `number` counts the ads from 1.
  public static func lines(for trace: AdTrace, number: Int, transcript: Transcript) -> [String] {
    let ad = trace.ad
    let lines = transcript.lines
    let kind = ad.kind == .ad ? "ad" : "own plug"
    let who = ad.advertiser.isEmpty ? "" : ", \(ad.advertiser)"
    var text = [
      "Ad \(number): \(clock(ad.start)) to \(clock(ad.end)) (\(Int(ad.duration.rounded())) s), "
        + "\(kind), \(ad.confidence.rawValue)\(who)"
    ]
    guard lines.indices.contains(trace.firstLine - 1), lines.indices.contains(trace.lastLine - 1)
    else { return text }
    let first = lines[trace.firstLine - 1]
    let last = lines[trace.lastLine - 1]
    let joined = trace.answers > 1 ? ", joined from \(trace.answers) answers" : ""
    text.append(
      "  The model said lines \(trace.firstLine) to \(trace.lastLine) "
        + "(\(clock(first.start)) to \(clock(last.end)))\(joined).")
    text.append("  Trimmed off the end, the show being back: \(listed(trace.trimmed)).")
    text.append("  Carried onto the end: \(listed(trace.carried)).")
    // The last line the ad has once the trim and the carry are done.
    let finalLine = trace.lastLine - trace.trimmed.count + trace.carried.count
    let stepEnd = lines.indices.contains(finalLine - 1) ? lines[finalLine - 1].end : last.end
    text.append(
      "  The end moved \(signed(stepEnd - last.end)) by trimming or carrying and "
        + "\(signed(ad.end - stepEnd)) by landing.")
    text.append("  The start moved \(signed(ad.start - first.start)) by landing.")
    text.append("  Around the start:")
    text += context(trace.aroundStart, edge: "start \(clock(ad.start))")
    text.append("  Around the end:")
    text += context(trace.aroundEnd, edge: "end \(clock(ad.end))")
    return text
  }

  private static func context(_ around: EdgeContext, edge: String) -> [String] {
    func row(_ line: NumberedLine) -> String {
      "    [\(line.number)] \(clock(line.start)) to \(clock(line.end))  \(line.text)"
    }
    return around.before.map(row) + ["    ---- \(edge) ----"] + around.after.map(row)
  }

  /// The comparison with hand-marked ads as lines of text.
  public static func lines(for comparison: TruthComparison) -> [String] {
    func range(_ start: Double, _ end: Double) -> String { "\(clock(start)) to \(clock(end))" }
    func words(_ name: String, _ error: Double, late: String, early: String) -> String {
      guard abs(error) >= 0.05 else { return "\(name) exact" }
      return String(format: "\(name) %.1f s ", abs(error)) + (error > 0 ? late : early)
    }
    var text = ["Against the ads marked by hand:"]
    for match in comparison.matches {
      let startWords = words(
        "start", match.startError, late: "late (that much of the ad is heard)",
        early: "early (some of the show is skipped)")
      let endWords = words(
        "end", match.endError, late: "late (some of the show is skipped)",
        early: "early (that much of the ad is heard)")
      text.append("  \(range(match.truth.start, match.truth.end)): \(startWords), \(endWords)")
    }
    text.append(
      String(
        format: "  End overshoot (the skip lands after the real end): mean %.1f s, worst %.1f s.",
        comparison.meanOvershoot, comparison.worstOvershoot))
    let missed = comparison.missed.map { " [\(range($0.start, $0.end))]" }.joined()
    let wrong = comparison.falseAds.map { " [\(range($0.start, $0.end))]" }.joined()
    text.append("  Missed ads: \(comparison.missed.count)\(missed)")
    text.append("  False ads: \(comparison.falseAds.count)\(wrong)")
    return text
  }
}
