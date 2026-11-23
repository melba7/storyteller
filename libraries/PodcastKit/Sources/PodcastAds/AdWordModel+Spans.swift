// LOFI-FORK: turns the word model's line scores into ad spans (see FORK.md). Foundation only.
import Foundation

extension AdWordModel {
  /// A run of lines the model takes for one ad.
  public struct Span: Sendable, Equatable {
    /// The numbers of the first and last line (not array indexes).
    public var firstLine: Int
    public var lastLine: Int
    /// The class with the most probability over the span, never "none".
    public var sort: String
    /// The mean of the smoothed ad probability over the lines.
    public var score: Double
    /// Whether the score and the length are high enough to skip without asking.
    public var sure: Bool
  }

  /// Decodes the line scores into spans, by the contract with the Mac trainer: smooth the
  /// ad probability over neighbouring lines (a quarter of each neighbour, half of the line),
  /// open a span where it reaches `start`, keep it open while it stays at `stay` (bridging one
  /// weak line), drop the whole span when it is shorter than 8 seconds and scores below 0.9,
  /// and cut what is left into pieces where the top class other than "none" changes from one
  /// line to the next (a bridged line takes the class of the line before it). Each piece has
  /// its own sort, mean score and "sure" (score at `sure` and 15 seconds long).
  public func spans(lines: [NumberedLine], duration: Double?) -> [Span] {
    Self.decode(
      rows: probabilities(lines: lines, duration: duration), lines: lines, thresholds: thresholds)
  }

  /// The three cut-offs of a model file's `thresholds`, or nil when one is not a number from 0 to
  /// 1, or the file would open a span on a line more likely plain talk (start under 0.5), or
  /// would close one before it opens (stay above start). A cut-off the file leaves out keeps its
  /// default. The word model checks the same things when it reads its file.
  static func thresholds(from named: [String: Double]?) -> Thresholds? {
    var cutoffs = Thresholds()
    for (name, value) in named ?? [:] {
      guard value.isFinite, (0.0...1.0).contains(value) else { return nil }
      switch name {
      case "start": cutoffs.start = value
      case "stay": cutoffs.stay = value
      case "sure": cutoffs.sure = value
      default: break
      }
    }
    guard cutoffs.start >= 0.5, cutoffs.stay <= cutoffs.start else { return nil }
    return cutoffs
  }

  /// The decoder on its own, so the word model and the meaning model share it: `rows` holds one
  /// row of class probabilities for each of `lines` (five numbers, "none" first). Rows that do
  /// not match the lines in number or in size give no spans.
  static func decode(rows: [[Double]], lines: [NumberedLine], thresholds: Thresholds) -> [Span] {
    let n = rows.count
    guard n == lines.count, rows.allSatisfy({ $0.count == classes.count }) else { return [] }
    let p = rows.map { 1 - $0[0] }
    var s = [Double](repeating: 0, count: n)
    for i in 0..<n {
      let before: Double = i > 0 ? p[i - 1] : p[i]
      let after: Double = i + 1 < n ? p[i + 1] : p[i]
      s[i] = before / 4 + p[i] / 2 + after / 4
    }

    var found: [Span] = []
    var i = 0
    while i < n {
      guard s[i] >= thresholds.start else {
        i += 1
        continue
      }
      var j = i
      while true {
        if j + 1 < n, s[j + 1] >= thresholds.stay {
          j += 1
        } else if j + 2 < n, s[j + 2] >= thresholds.stay {
          j += 2
        } else {
          break
        }
      }
      // Each line's class is its own top class other than "none" (the first one wins a tie). A
      // line bridged because it was weak takes the class of the line before it.
      var sorts: [Int] = []
      for k in i...j {
        if k > i, s[k] < thresholds.stay {
          sorts.append(sorts[sorts.count - 1])
        } else {
          sorts.append(topClass(rows[k]))
        }
      }
      // The span as a whole must be long or strong enough; then it is cut into one piece for
      // each run of one class, and every piece has its own sort, score and "sure".
      let wholeScore = s[i...j].reduce(0, +) / Double(j - i + 1)
      if lines[j].end - lines[i].start >= 8 || wholeScore >= 0.9 {
        var from = i
        while from <= j {
          var to = from
          while to < j, sorts[to + 1 - i] == sorts[from - i] { to += 1 }
          let score = s[from...to].reduce(0, +) / Double(to - from + 1)
          let length = lines[to].end - lines[from].start
          found.append(
            Span(
              firstLine: lines[from].number, lastLine: lines[to].number,
              sort: Self.classes[sorts[from - i]], score: score,
              sure: score >= thresholds.sure && length >= 15))
          from = to + 1
        }
      }
      i = j + 1
    }
    return found
  }

  /// The index of the class other than "none" with the highest probability on a line.
  private static func topClass(_ row: [Double]) -> Int {
    var best = 1
    for c in 2..<Self.classes.count where row[c] > row[best] { best = c }
    return best
  }
}
