// LOFI-FORK: a transcript's words with their times and the hashes of its five-word runs, for the
// repeated-words finder (see FORK.md). Foundation only.
import Foundation
import PodcastTranscripts

/// The normalised words of some transcript lines, the time each word starts and ends, and a
/// 32-bit hash of every run of five words. A line gives only its own start and end, so the words
/// of a line are spread evenly over it.
struct SpokenRuns {
  /// Words in a run.
  static let runLength = 5

  var texts: [String] = []
  var starts: [Double] = []
  var ends: [Double] = []
  /// `hashes[i]` is the hash of the words `i` to `i + 4`: four fewer than the words, and none for
  /// fewer than five words.
  var hashes: [UInt32] = []

  /// At most `RepeatedWords.mostWords` words are read, so the work never grows with a huge
  /// transcript. A line whose times are not numbers, or that ends before it starts, is skipped.
  init(lines: [TranscriptLine]) {
    for line in lines where texts.count < RepeatedWords.mostWords {
      let length = line.end - line.start
      guard line.start.isFinite, line.end.isFinite, length.isFinite, length >= 0 else { continue }
      let words = line.text.split(whereSeparator: \.isWhitespace).compactMap {
        KnownAds.normalise(String($0))
      }
      guard !words.isEmpty else { continue }
      let step = length / Double(words.count)
      for (k, word) in words.enumerated() where texts.count < RepeatedWords.mostWords {
        let start = line.start + Double(k) * step
        texts.append(word)
        starts.append(start)
        ends.append(start + step)
      }
    }
    guard texts.count >= Self.runLength else { return }
    hashes.reserveCapacity(texts.count - Self.runLength + 1)
    for first in 0...(texts.count - Self.runLength) {
      hashes.append(Self.hash(texts[first..<(first + Self.runLength)]))
    }
  }

  /// The middle of word `index`: the moment that says which stretch a word belongs to.
  func middle(of index: Int) -> Double { starts[index] / 2 + ends[index] / 2 }

  /// FNV-1a over the words joined by a space, 64 bits folded to 32. It is computed here rather
  /// than with `Hasher`, which is seeded differently on every launch, so a saved hash means the
  /// same words in the next launch.
  static func hash(_ words: ArraySlice<String>) -> UInt32 {
    let prime: UInt64 = 0x100_0000_01b3
    var value: UInt64 = 0xcbf2_9ce4_8422_2325
    for (k, word) in words.enumerated() {
      if k > 0 { value = (value ^ 0x20) &* prime }
      for byte in word.utf8 { value = (value ^ UInt64(byte)) &* prime }
    }
    return UInt32(truncatingIfNeeded: value ^ (value >> 32))
  }

  // MARK: Hashes as bytes

  /// The hashes as bytes, four to each, least significant byte first, so the bytes are the same
  /// on every device.
  static func pack<S: Sequence>(_ hashes: S) -> Data where S.Element == UInt32 {
    var bytes: [UInt8] = []
    for hash in hashes {
      bytes.append(UInt8(truncatingIfNeeded: hash))
      bytes.append(UInt8(truncatingIfNeeded: hash >> 8))
      bytes.append(UInt8(truncatingIfNeeded: hash >> 16))
      bytes.append(UInt8(truncatingIfNeeded: hash >> 24))
    }
    return Data(bytes)
  }

  /// The hashes in bytes made by `pack`. A left-over byte or two at the end are ignored.
  static func unpack(_ data: Data) -> [UInt32] {
    data.withUnsafeBytes { raw in
      (0..<(raw.count / 4)).map { at in
        let low = UInt32(raw[4 * at]) | UInt32(raw[4 * at + 1]) << 8
        let high = UInt32(raw[4 * at + 2]) << 16 | UInt32(raw[4 * at + 3]) << 24
        return low | high
      }
    }
  }
}
