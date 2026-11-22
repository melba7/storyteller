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
  /// ad probability over neighbouring lines, open a span where it reaches `start`, keep it
  /// open while it stays at `stay` (bridging one weak line), then drop short, weak spans.
  public func spans(lines: [NumberedLine], duration: Double?) -> [Span] {
    let rows = probabilities(lines: lines, duration: duration)
    let n = rows.count
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
      // The first of the non-"none" classes with the largest total wins a tie.
      var best = 1
      var bestSum = -Double.infinity
      for c in 1..<Self.classes.count {
        let sum = rows[i...j].reduce(0) { $0 + $1[c] }
        if sum > bestSum {
          bestSum = sum
          best = c
        }
      }
      let score = s[i...j].reduce(0, +) / Double(j - i + 1)
      let length = lines[j].end - lines[i].start
      if length >= 8 || score >= 0.9 {
        found.append(
          Span(
            firstLine: lines[i].number, lastLine: lines[j].number, sort: Self.classes[best],
            score: score, sure: score >= thresholds.sure && length >= 15))
      }
      i = j + 1
    }
    return found
  }
}
