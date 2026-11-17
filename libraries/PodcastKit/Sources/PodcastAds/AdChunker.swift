// LOFI-FORK: cuts a transcript into pieces for an ad detector (see FORK.md).
import Foundation
import PodcastTranscripts

/// Numbering lines and cutting them into pieces that fit a detector's budget.
public enum AdChunker {
  /// Pieces overlap by this many seconds, so an ad that crosses a cut is seen whole at least
  /// once.
  public static let overlap = 120.0
  /// About this many characters make a token.
  public static let charactersPerToken = 4.0

  /// The lines counted from 1.
  public static func number(_ lines: [TranscriptLine]) -> [NumberedLine] {
    lines.enumerated().map {
      NumberedLine(number: $0.offset + 1, start: $0.element.start, end: $0.element.end, text: $0.element.text)
    }
  }

  /// The estimate for one line as it is sent ("[12] text" and a line break).
  public static func tokens(of line: NumberedLine) -> Int {
    Int((Double(line.prompt.count + 1) / charactersPerToken).rounded(.up))
  }

  /// The pieces, each within `tokenBudget` (a single line over it gets a piece of its own),
  /// each starting about `overlap` seconds before the last one ended and always reaching at
  /// least one line past it.
  public static func pieces(
    of lines: [NumberedLine], tokenBudget: Int, overlap: Double = overlap
  ) -> [TranscriptPiece] {
    guard !lines.isEmpty else { return [] }
    let cost = lines.map(tokens(of:))
    var pieces: [TranscriptPiece] = []
    var start = 0
    while true {
      var end = start
      var total = cost[start]
      while end + 1 < lines.count, total + cost[end + 1] <= tokenBudget {
        end += 1
        total += cost[end]
      }
      pieces.append(TranscriptPiece(lines: Array(lines[start...end])))
      if end == lines.count - 1 { return pieces }

      let from = lines[end].end - max(0, overlap)
      var next = lines.firstIndex { $0.start >= from } ?? end + 1
      next = min(max(next, start + 1), end + 1)
      // The next piece has to reach the line after this one, so keep trimming the overlap
      // until the lines up to it fit.
      while next <= end, cost[next...(end + 1)].reduce(0, +) > tokenBudget { next += 1 }
      start = next
    }
  }

  /// A piece cut in two halves by line count, or nil when it is one line.
  public static func split(_ piece: TranscriptPiece) -> (TranscriptPiece, TranscriptPiece)? {
    guard piece.lines.count > 1 else { return nil }
    let middle = piece.lines.count / 2
    return (
      TranscriptPiece(lines: Array(piece.lines[..<middle])),
      TranscriptPiece(lines: Array(piece.lines[middle...]))
    )
  }
}
