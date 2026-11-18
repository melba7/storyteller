// LOFI-FORK: marks ads from the differences between two downloads of one episode (see FORK.md).
//
// Two downloads of one episode from a host that stitches ads get different ads in the same show.
// FrameAlign finds the stretches where they differ and then agree again; each stretch of the first
// download is an ad (or other audio the host chose per listener), with times that are exact to a
// frame. The result is in the format of `--truth` (see AdTruth): one ad to a line, notes after "#".
import Foundation

public enum CopyTruth {
  /// A stretch that differs for less than this is a glitch, not an ad.
  public static let minSeconds = 1.0

  /// The lines of a truth file for the first download, `a`, in the order of the first file. The
  /// stretches that are left out, and why, are in notes (lines that start with "#").
  public static func lines(_ a: MP3Parse, _ b: MP3Parse) -> [String] {
    var lines = [
      "# Ads marked from the differences between two downloads of one episode.",
      "# The times are in the first download. A stretch is marked where it has audio that the",
      "# second download does not have. An ad that both downloads got is not marked, so a skip in",
      "# one counts as a false ad when this file is used with --edges --truth.",
    ]
    guard !a.frames.isEmpty, !b.frames.isEmpty else {
      return lines + ["# One of the files has no MP3 frames, so nothing is marked."]
    }
    let result = FrameAlign.align(a.frames.map(\.hash), b.frames.map(\.hash))
    guard result.matched > 0 else {
      return lines + [
        "# The two files have no frame in common, so they are not two downloads of one episode",
        "# (or the host makes a new file for every download). Nothing is marked.",
      ]
    }
    for difference in result.differing {
      guard !difference.a.isEmpty else {
        let next = difference.a.lowerBound
        let at = next < a.frames.count ? a.frames[next].start : a.seconds
        let length = oneDecimal(seconds(b, difference.b))
        lines.append("# Left out: at \(clock(at)) only the second download has audio (\(length) s).")
        continue
      }
      let start = a.frames[difference.a.lowerBound].start
      let last = a.frames[difference.a.upperBound - 1]
      let end = last.start + last.duration
      if end - start < minSeconds {
        lines.append("# Left out: \(clock(start)) to \(clock(end)) differs but is under 1 s long.")
      } else {
        lines.append("\(clock(start)) \(clock(end))")
      }
    }
    if result.unmatchedTailA > 0 {
      let tail = seconds(a, (a.frames.count - result.unmatchedTailA)..<a.frames.count)
      lines.append(
        "# Not marked: the last \(oneDecimal(tail)) s of the first download come after the last place where they agree and match nothing in the second. A download that was cut off looks the same, so they may or may not be an ad."
      )
    }
    return lines
  }

  private static func seconds(_ parse: MP3Parse, _ range: Range<Int>) -> Double {
    parse.frames[range].reduce(0) { $0 + $1.duration }
  }

  private static func oneDecimal(_ value: Double) -> String { String(format: "%.1f", value) }

  /// "12:34.500" or "1:02:03.500": minutes and seconds to the millisecond, with hours from one
  /// hour on. Rounded as whole milliseconds first, so it never shows 60 seconds.
  static func clock(_ seconds: Double) -> String {
    let ms = Int((max(0, seconds) * 1000).rounded())
    let hours = ms / 3_600_000
    let minutes = ms / 60_000 % 60
    let rest = ms % 60_000
    if hours > 0 {
      return String(format: "%d:%02d:%02d.%03d", hours, minutes, rest / 1000, rest % 1000)
    }
    return String(format: "%d:%02d.%03d", minutes, rest / 1000, rest % 1000)
  }
}
