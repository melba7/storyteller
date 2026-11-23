import Foundation

@testable import PodcastAds
@testable import PodcastTranscripts

/// Made-up speech for the repeated-words tests. Every word is a tag and a number ("old17"), so a
/// run of five words never appears twice unless a test puts the same words in two places.
enum Speech {
  /// Seconds one word lasts.
  static let step = 0.5
  /// Words in one line, so a line lasts five seconds.
  static let perLine = 10

  /// The moment the word at `index` starts, when the episode is made with `step`.
  static func time(ofWord index: Int, step: Double = Speech.step) -> Double { Double(index) * step }

  /// `count` words of plain talk that belong to one tag.
  static func talk(_ count: Int, tag: String) -> [String] { (0..<count).map { "\(tag)\($0)" } }

  /// A standing passage of `count` words ("plug0 plug1 ..."), with the words at the `changed`
  /// positions swapped for other words, as a host who reads it a little differently each time.
  static func plug(_ count: Int, tag: String = "plug", changed: [Int] = []) -> [String] {
    (0..<count).map { changed.contains($0) ? "other\($0)" : "\(tag)\($0)" }
  }

  /// An episode of `total` words of talk with each passage put over the words from its position.
  static func episode(
    tag: String, total: Int, plugs: [(at: Int, words: [String])] = []
  ) -> [String] {
    var words = talk(total, tag: tag)
    for plug in plugs {
      for (offset, word) in plug.words.enumerated() where plug.at + offset < words.count {
        words[plug.at + offset] = word
      }
    }
    return words
  }

  /// The words as transcript lines of `perLine` words, one right after the other.
  static func lines(
    _ words: [String], perLine: Int = Speech.perLine, step: Double = Speech.step
  ) -> [TranscriptLine] {
    var result: [TranscriptLine] = []
    var from = 0
    while from < words.count {
      let to = min(words.count, from + perLine)
      result.append(
        TranscriptLine(
          start: Double(from) * step, end: Double(to) * step,
          text: words[from..<to].joined(separator: " ")))
      from = to
    }
    return result
  }

  /// The length of the episode in seconds.
  static func seconds(_ words: [String], step: Double = Speech.step) -> Double {
    Double(words.count) * step
  }
}

/// A fixed generator, so a test that needs "random" bytes gets the same ones every time.
struct FixedBytes {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func data(count: Int) -> Data {
    var bytes = [UInt8]()
    bytes.reserveCapacity(count)
    for _ in 0..<count {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      bytes.append(UInt8(truncatingIfNeeded: state >> 33))
    }
    return Data(bytes)
  }
}
