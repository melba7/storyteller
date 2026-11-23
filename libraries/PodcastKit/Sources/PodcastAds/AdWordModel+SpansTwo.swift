// LOFI-FORK: the decoder of word model files of version 2 (see FORK.md). Foundation only.
import Foundation

extension AdWordModel {
  /// A stretch of lines found by one pass, by array index.
  private struct Piece {
    var first: Int
    var last: Int
    var cls: Int
    var score: Double
  }

  /// The decoder for version 2 files, by the contract with the Mac trainer (`teach_spans.py`).
  /// Two passes over the same rules as `decode`, with these differences:
  /// - The ad pass scores a line by `p[sponsor] + p[network_promo] + p[host_ask]`, so credits do
  ///   not count as an ad, and it widens the start of each span backwards while the line before
  ///   has an unsmoothed score of at least `stay` and is not inside or before the previous kept
  ///   span. The 8 second and 0.9 rule is judged on the widened span.
  /// - The credits pass scores a line by `p[intro_credits]` with no widening, and it never
  ///   includes a line that lies inside a span of the ad pass: the span is cut there and each
  ///   part is judged by the 8 second and 0.9 rule on its own.
  /// The spans of both passes come back in order of their first line.
  static func decodeTwo(rows: [[Double]], lines: [NumberedLine], thresholds: Thresholds) -> [Span] {
    guard rows.count == lines.count, rows.allSatisfy({ $0.count == classes.count }) else { return [] }
    let ads = pass(
      chance: rows.map { $0[1] + $0[2] + $0[3] }, rows: rows, lines: lines, thresholds: thresholds,
      among: 1...3, widen: true, blocked: nil)
    var inside = [Bool](repeating: false, count: rows.count)
    for piece in ads { for k in piece.first...piece.last { inside[k] = true } }
    let credits = pass(
      chance: rows.map { $0[4] }, rows: rows, lines: lines, thresholds: thresholds,
      among: 4...4, widen: false, blocked: inside)
    return (ads + credits).sorted { $0.first < $1.first }.map { piece in
      let length = lines[piece.last].end - lines[piece.first].start
      return Span(
        firstLine: lines[piece.first].number, lastLine: lines[piece.last].number,
        sort: classes[piece.cls], score: piece.score,
        sure: piece.score >= thresholds.sure && length >= 15)
    }
  }

  /// One pass: `chance` is each line's own score, `among` the classes a line may take (the first
  /// one wins a tie), and `blocked` the lines no span may include.
  private static func pass(
    chance p: [Double], rows: [[Double]], lines: [NumberedLine], thresholds: Thresholds,
    among: ClosedRange<Int>, widen: Bool, blocked: [Bool]?
  ) -> [Piece] {
    let n = p.count
    var s = [Double](repeating: 0, count: n)
    for i in 0..<n {
      let before: Double = i > 0 ? p[i - 1] : p[i]
      let after: Double = i + 1 < n ? p[i + 1] : p[i]
      s[i] = before / 4 + p[i] / 2 + after / 4
    }
    func top(_ row: [Double]) -> Int {
      var best = among.lowerBound
      for c in among where row[c] > row[best] { best = c }
      return best
    }
    func mean(_ from: Int, _ to: Int) -> Double { s[from...to].reduce(0, +) / Double(to - from + 1) }

    var found: [Piece] = []
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
      var a = i
      if widen {
        while a > 0, p[a - 1] >= thresholds.stay, a - 1 > (found.last?.last ?? -1) { a -= 1 }
      }
      var sorts: [Int] = []
      for k in a...j {
        sorts.append(k > a && s[k] < thresholds.stay ? sorts[sorts.count - 1] : top(rows[k]))
      }
      // The parts of the span that no blocked line interrupts (all of it when nothing is blocked).
      var from = a
      while from <= j {
        if blocked?[from] == true {
          from += 1
          continue
        }
        var upTo = from
        while upTo < j, blocked?[upTo + 1] != true { upTo += 1 }
        if lines[upTo].end - lines[from].start >= 8 || mean(from, upTo) >= 0.9 {
          var start = from
          while start <= upTo {
            var stop = start
            while stop < upTo, sorts[stop + 1 - a] == sorts[start - a] { stop += 1 }
            found.append(Piece(first: start, last: stop, cls: sorts[start - a], score: mean(start, stop)))
            start = stop + 1
          }
        }
        from = upTo + 1
      }
      i = j + 1
    }
    return found
  }
}
