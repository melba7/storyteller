// LOFI-FORK: the time of each word of a transcript, kept in a side file (see FORK.md). Foundation only.
import Foundation

/// Where each word of a transcript starts and ends, and each line (the first word's start and the
/// last word's end), in seconds to a thousandth. The Mac keeps it as `transcripts/<id>.words.json`
/// next to the plain transcript `transcripts/<id>.txt`, which holds only where each line starts, so
/// everything that reads the plain one keeps working. The words themselves are not kept here.
public struct WordTimes: Codable, Sendable, Equatable {
  public static let currentVersion = 1

  public var version: Int
  public var duration: Double
  /// `[start, end]` for each line, in order.
  public var lines: [[Double]]
  /// `[start, end]` for each word, in order.
  public var words: [[Double]]

  public init(_ transcript: Transcript) {
    version = Self.currentVersion
    duration = transcript.duration
    lines = transcript.lines.map { [Self.round($0.start), Self.round($0.end)] }
    words = transcript.words.map { [Self.round($0.start), Self.round($0.end)] }
  }

  private static func round(_ seconds: Double) -> Double { (seconds * 1000).rounded() / 1000 }

  /// Saves the file through a part file, so it is never half written.
  public func write(to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(self).write(to: url, options: .atomic)
  }
}
