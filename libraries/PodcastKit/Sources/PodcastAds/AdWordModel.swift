// LOFI-FORK: the small word model that scores transcript lines for ads (see FORK.md). Foundation only.
import Foundation

/// A tiny linear model that says, for each transcript line, how likely it is to be a sponsor
/// read, a network promo, a host ask or an intro or credits stretch, or none of these. It
/// looks at the words of the line, its neighbours and the time in the episode, and needs no
/// Apple model and no network.
///
/// The Mac trains it on transcripts whose ads were marked (`libraries/PodcastKit/Tools/mac/teach_train.py`)
/// and saves `ad-model.json`. The phone loads that file here. The Python and the Swift code must
/// compute exactly the same numbers, so the rules for tokens, features, hashing, scoring and
/// spans below are a contract: change one side only together with the other.
public struct AdWordModel: Sendable, Equatable {
  /// Where the Mac puts the trained file.
  public static let fileName = "ad-model.json"
  /// The classes, in the order of the weights in the file.
  public static let classes = ["none", "sponsor", "network_promo", "host_ask", "intro_credits"]

  /// The three cut-offs for turning smoothed probabilities into spans.
  struct Thresholds: Sendable, Equatable {
    var start = 0.6
    var stay = 0.4
    var sure = 0.85
  }

  let buckets: Int
  let thresholds: Thresholds
  /// Five weights per bucket. A bucket that is missing counts as all zeros.
  let weights: [Int: [Double]]

  /// What the file holds. Anything else in it (such as `trained`) is ignored.
  private struct FileContents: Decodable {
    var version: Int
    var buckets: Int
    var classes: [String]
    var weights: [String: [Double]]
    var thresholds: [String: Double]?
  }

  /// Reads a model file. Returns nil when the file cannot be trusted.
  public init?(data: Data) {
    guard let file = try? JSONDecoder().decode(FileContents.self, from: data),
      file.version == 1, (1024...4_194_304).contains(file.buckets),
      file.classes == Self.classes, !file.weights.isEmpty  // no weights would call every line an ad
    else { return nil }

    var cutoffs = Thresholds()
    for (name, value) in file.thresholds ?? [:] {
      guard value.isFinite, (0.0...1.0).contains(value) else { return nil }
      switch name {
      case "start": cutoffs.start = value
      case "stay": cutoffs.stay = value
      case "sure": cutoffs.sure = value
      default: break
      }
    }
    // A start below 0.5 would open a span on a line the model thinks is more likely plain talk.
    guard cutoffs.start >= 0.5, cutoffs.stay <= cutoffs.start else { return nil }

    var table: [Int: [Double]] = [:]
    table.reserveCapacity(file.weights.count)
    for (key, row) in file.weights {
      guard !key.isEmpty, key.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
        let index = Int(key), index < file.buckets,
        row.count == Self.classes.count, row.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 })
      else { return nil }
      table[index] = row
    }
    // A line with no known word has only the bias. A file whose bias does not call that line
    // plain talk (a missing bias row, say) would call every ordinary line an ad.
    let bias = table[Self.bucket("#bias", buckets: file.buckets)] ?? [Double](repeating: 0, count: Self.classes.count)
    guard Self.plainProbability(bias) >= 0.5 else { return nil }
    self.buckets = file.buckets
    self.thresholds = cutoffs
    self.weights = table
  }

  /// The probability of "none" for these five scores.
  private static func plainProbability(_ scores: [Double]) -> Double {
    let top = scores.max() ?? 0
    let exps = scores.map { exp($0 - top) }
    return exps[0] / exps.reduce(0, +)
  }

  /// Loads the model at `url`, or nil when there is no file or it cannot be trusted.
  public static func load(from url: URL) -> AdWordModel? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return AdWordModel(data: data)
  }

  // MARK: Words and hashing

  /// The words of a text: lower-case ASCII letters, digits and apostrophes (a curly apostrophe
  /// counts as a plain one). Anything else ends a word. Apostrophes at the ends of a word are
  /// cut off, and a word of only digits becomes "0".
  public static func tokens(_ text: String) -> [String] {
    var result: [String] = []
    var current: [UInt8] = []
    func finish() {
      defer { current.removeAll(keepingCapacity: true) }
      guard !current.isEmpty else { return }
      var word = current[...]
      while word.first == 39 { word = word.dropFirst() }
      while word.last == 39 { word = word.dropLast() }
      guard !word.isEmpty else { return }
      if word.allSatisfy({ $0 >= 48 && $0 <= 57 }) {
        result.append("0")
      } else {
        result.append(String(decoding: word, as: UTF8.self))
      }
    }
    for scalar in text.unicodeScalars {
      var value = scalar.value
      if value == 0x2019 { value = 39 }
      if value >= 65 && value <= 90 { value += 32 }
      if (value >= 97 && value <= 122) || (value >= 48 && value <= 57) || value == 39 {
        current.append(UInt8(value))
      } else {
        finish()
      }
    }
    finish()
    return result
  }

  /// The bucket of a feature: FNV-1a over its UTF-8 bytes, modulo `buckets`.
  public static func bucket(_ feature: String, buckets: Int) -> Int {
    var hash: UInt32 = 2_166_136_261
    for byte in feature.utf8 {
      hash ^= UInt32(byte)
      hash = hash &* 16_777_619
    }
    return Int(hash) % buckets
  }

  // MARK: Scoring

  /// The features of line `i` as buckets, each once and in ascending order.
  private func activeBuckets(_ i: Int, words: [[String]], lines: [NumberedLine], duration: Double?) -> [Int] {
    var features: Set<String> = ["#bias"]
    let own = words[i]
    for word in own { features.insert("u:" + word) }
    if own.count > 1 {
      for k in 1..<own.count { features.insert("b:" + own[k - 1] + " " + own[k]) }
    }
    for j in max(0, i - 2)..<i { for word in words[j] { features.insert("p:" + word) } }
    if i + 1 < lines.count {
      for j in (i + 1)...min(lines.count - 1, i + 2) {
        for word in words[j] { features.insert("n:" + word) }
      }
    }
    let start = lines[i].start
    if start < 120 {
      features.insert("#t0")
    } else if start < 300 {
      features.insert("#t1")
    }
    if let duration, duration - start < 120 { features.insert("#end") }
    return Set(features.map { Self.bucket($0, buckets: buckets) }).sorted()
  }

  /// One row of five probabilities per line, in the order of `classes`.
  public func probabilities(lines: [NumberedLine], duration: Double?) -> [[Double]] {
    let words = lines.map { Self.tokens($0.text) }
    return lines.indices.map { i in
      var scores = [Double](repeating: 0, count: Self.classes.count)
      for bucket in activeBuckets(i, words: words, lines: lines, duration: duration) {
        guard let row = weights[bucket] else { continue }
        for c in scores.indices { scores[c] += row[c] }
      }
      let top = scores.max() ?? 0
      let exps = scores.map { exp($0 - top) }
      let total = exps.reduce(0, +)
      return exps.map { $0 / total }
    }
  }
}
