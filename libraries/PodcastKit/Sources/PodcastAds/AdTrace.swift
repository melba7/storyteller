// LOFI-FORK: how one ad came about, for `podcast-ads --edges` (see FORK.md).
import Foundation
import PodcastTranscripts

extension NumberedLine {
  init(number: Int, line: TranscriptLine) {
    self.init(number: number, start: line.start, end: line.end, text: line.text)
  }
}

/// The lines around one edge of an ad: those before it and those after it.
public struct EdgeContext: Equatable, Sendable {
  /// How many lines are shown before an edge and after it.
  public static let linesBefore = 2
  public static let linesAfter = 3

  public var before: [NumberedLine]
  public var after: [NumberedLine]

  /// The `before` lines that start before `time` (the nearest ones) and the `after` lines that
  /// start at or after it.
  init(at time: Double, lines: [TranscriptLine]) {
    let split = lines.firstIndex { $0.start >= time } ?? lines.count
    func numbered(_ range: Range<Int>) -> [NumberedLine] {
      range.map { NumberedLine(number: $0 + 1, line: lines[$0]) }
    }
    before = numbered(max(0, split - Self.linesBefore)..<split)
    after = numbered(split..<min(lines.count, split + Self.linesAfter))
  }
}

/// One ad of the clean-up with what produced it. `AdCleanup.run` returns the `ad`s of these.
public struct AdTrace: Equatable, Sendable {
  public var ad: FoundAd
  /// The model's first line and last line (counted from 1). For ads joined from several answers,
  /// the first line of the earliest and the last line of the one that ends latest.
  public var firstLine: Int
  public var lastLine: Int
  /// The lines taken off the end of the model's answer because the show was back.
  public var trimmed: [NumberedLine]
  /// The lines after the model's last line that were carried into the ad.
  public var carried: [NumberedLine]
  /// How many answers were joined into this ad.
  public var answers: Int
  public var aroundStart: EdgeContext
  public var aroundEnd: EdgeContext
}
