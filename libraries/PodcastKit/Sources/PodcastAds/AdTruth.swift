// LOFI-FORK: compares the ads found in an episode with ads marked by hand (see FORK.md).
//
// Used by `podcast-ads --edges --truth <file>`. The file has one ad on each line, as two times:
// "12:30 13:45" (minutes and seconds; "1:02:03" and "12:30.5" work too). Blank lines and lines
// that start with "#" are left out. Foundation only.
import Foundation

public struct TruthAd: Equatable, Sendable {
  public var start: Double
  public var end: Double

  public init(start: Double, end: Double) {
    self.start = start
    self.end = end
  }
}

public enum AdTruthError: Error, Equatable, CustomStringConvertible {
  case badLine(number: Int, text: String)

  public var description: String {
    switch self {
    case .badLine(let number, let text):
      return "Line \(number) of the marked ads is not two times such as 12:30 13:45: \(text)"
    }
  }
}

/// A found ad and the marked ad it overlaps most.
public struct TruthMatch: Equatable, Sendable {
  public var truth: TruthAd
  public var found: FoundAd
  /// Seconds the found start is after the marked start (negative: before it).
  public var startError: Double
  /// Seconds the found end is after the marked end (negative: before it).
  public var endError: Double
}

public struct TruthComparison: Equatable, Sendable {
  public var matches: [TruthMatch]
  /// Marked ads that no found ad overlaps.
  public var missed: [TruthAd]
  /// Found ads that overlap no marked ad.
  public var falseAds: [FoundAd]

  /// How far past the real end the skip lands (zero when it lands before it), as a mean and as
  /// the worst, over the matched ads.
  public var meanOvershoot: Double {
    matches.isEmpty ? 0 : matches.map { max(0, $0.endError) }.reduce(0, +) / Double(matches.count)
  }
  public var worstOvershoot: Double { matches.map { max(0, $0.endError) }.max() ?? 0 }
}

public enum AdTruth {
  /// The marked ads in a file's text. Throws on a line that is not two times, the second after
  /// the first.
  public static func parse(_ text: String) throws -> [TruthAd] {
    var ads: [TruthAd] = []
    let rows = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    for (index, row) in rows.enumerated() {
      let line = row.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty, !line.hasPrefix("#") else { continue }
      let times = line.split(whereSeparator: \.isWhitespace)
        .filter { !["-", "–", "to"].contains($0) }
      guard times.count == 2, let start = seconds(String(times[0])),
        let end = seconds(String(times[1])), end > start
      else { throw AdTruthError.badLine(number: index + 1, text: line) }
      ads.append(TruthAd(start: start, end: end))
    }
    return ads
  }

  /// Seconds in "12:30", "1:02:03" or "12:30.5". Nil for anything else.
  public static func seconds(_ text: String) -> Double? {
    let parts = text.split(separator: ":", omittingEmptySubsequences: false)
    guard (2...3).contains(parts.count) else { return nil }
    var total = 0.0
    for (index, part) in parts.enumerated() {
      let isLast = index == parts.count - 1
      guard !part.isEmpty, part.allSatisfy({ $0.isNumber || (isLast && $0 == ".") }),
        let value = Double(part)
      else { return nil }
      // Only the first part (hours, or minutes without hours) may be 60 or more.
      if index > 0, value >= 60 { return nil }
      total = total * 60 + value
    }
    return total
  }

  public static func compare(found: [FoundAd], truth: [TruthAd]) -> TruthComparison {
    func overlap(_ ad: FoundAd, _ marked: TruthAd) -> Double {
      max(0, min(ad.end, marked.end) - max(ad.start, marked.start))
    }
    var matches: [TruthMatch] = []
    var missed: [TruthAd] = []
    for marked in truth {
      let touching = found.filter { overlap($0, marked) > 0 }
      guard let best = touching.max(by: { overlap($0, marked) < overlap($1, marked) }) else {
        missed.append(marked)
        continue
      }
      matches.append(
        TruthMatch(
          truth: marked, found: best, startError: best.start - marked.start,
          endError: best.end - marked.end))
    }
    let falseAds = found.filter { ad in !truth.contains { overlap(ad, $0) > 0 } }
    return TruthComparison(matches: matches, missed: missed, falseAds: falseAds)
  }
}
