// LOFI-FORK: the fitter behind `podcast-teach fit` (see FORK.md). Foundation only.
import Foundation

/// A set-up problem of the fitter, in plain words.
public struct AdWordFitError: Error, Equatable {
  public var message: String
}

/// Fits the word model's weights on the Mac. Python is too slow for a proper solver, so the
/// trainer (`teach_train.py`) writes its examples to a file and calls `podcast-teach fit`.
///
/// It minimises exactly the sum over the examples of `classWeight[y] * -log p(y)`, plus the sum
/// of all squared weights divided by `2 * c`. `p` is the softmax of the bias plus the weights of
/// the line's kept buckets. The five bias numbers are not penalised. The class weight is 1 for
/// class 0 and `min(classCap, count of class 0 / count of that class)` for the others (`classCap`
/// for a class with no example). A bucket that occurs in fewer than `minCount` lines is ignored.
public enum AdWordFit {
  public static let classCount = 5
  /// The most buckets a file may name; more would need far more memory than a Mac has to spare.
  public static let maxBuckets = 16_777_216

  public struct Settings: Equatable, Sendable {
    public var c = 0.1
    public var minCount = 3
    public var classCap = 5.0
    public var iterations = 300
    public init() {}
  }

  /// The training lines: a class and the distinct bucket numbers of each, kept in flat arrays.
  public struct Examples: Equatable, Sendable {
    public var buckets: Int
    public var labels: [UInt8] = []
    /// Where each line's buckets start in `items`; one more entry than there are lines.
    public var starts: [Int] = [0]
    public var items: [Int32] = []
    public var count: Int { labels.count }
  }

  public struct Result: Equatable, Sendable {
    public var bias: [Double]
    /// The kept buckets in ascending order, and five weights for each in `weights`.
    public var buckets: [Int32]
    public var weights: [Double]
    public var iterations: Int
    public var objective: Double
  }

  // MARK: Reading the examples

  /// Reads the examples file: a first line `buckets <N> classes 5`, then one line for each
  /// training line with its class (0 to 4) and its distinct bucket numbers, all separated by
  /// spaces. A line may have no buckets.
  public static func parse(_ data: Data) -> Swift.Result<Examples, AdWordFitError> {
    func fail(_ text: String) -> Swift.Result<Examples, AdWordFitError> { .failure(AdWordFitError(message: text)) }
    return data.withUnsafeBytes { raw -> Swift.Result<Examples, AdWordFitError> in
      let bytes = raw.bindMemory(to: UInt8.self)
      let end = bytes.count
      var at = 0
      while at < end, bytes[at] != 10 { at += 1 }
      let header = String(decoding: bytes[0..<at], as: UTF8.self).split(separator: " ").map(String.init)
      guard header.count == 4, header[0] == "buckets", header[2] == "classes", header[3] == "5",
        let size = Int(header[1]), (1...Int(Int32.max)).contains(size)
      else { return fail("The first line of the examples file must be \"buckets <N> classes 5\".") }
      guard size <= maxBuckets else {
        return fail("The examples file names \(size) buckets; the most the fitter takes is \(maxBuckets).")
      }
      var found = Examples(buckets: size)
      var number = 1
      at += 1
      while at < end {
        number += 1
        var values = 0
        var seen = Set<Int32>()
        var empty = true
        while at < end, bytes[at] != 10 {
          let byte = bytes[at]
          if byte == 32 || byte == 9 || byte == 13 {
            at += 1
            continue
          }
          guard byte >= 48, byte <= 57 else { return fail("Line \(number) of the examples file holds something that is not a number.") }
          var value = 0
          while at < end, bytes[at] >= 48, bytes[at] <= 57 {
            value = value &* 10 &+ Int(bytes[at] - 48)
            guard value <= Int(Int32.max) else { return fail("Line \(number) of the examples file has a number that is too big.") }
            at += 1
          }
          empty = false
          if values == 0 {
            guard value < classCount else { return fail("Line \(number) of the examples file has the class \(value); classes are 0 to 4.") }
            found.labels.append(UInt8(value))
          } else {
            guard value < size else { return fail("Line \(number) of the examples file has the bucket \(value), which is not below \(size).") }
            guard seen.insert(Int32(value)).inserted else { return fail("Line \(number) of the examples file lists the bucket \(value) twice.") }
            found.items.append(Int32(value))
          }
          values += 1
        }
        at += 1
        if empty {
          if at >= end { break }  // the empty end after the last newline
          return fail("Line \(number) of the examples file is empty.")
        }
        found.starts.append(found.items.count)
      }
      guard found.count > 0 else { return fail("The examples file has no examples.") }
      return .success(found)
    }
  }

  /// How much each class's loss counts.
  static func classWeights(_ labels: [UInt8], cap: Double) -> [Double] {
    var counts = [Int](repeating: 0, count: classCount)
    for label in labels { counts[Int(label)] += 1 }
    return (0..<classCount).map { c in
      if c == 0 { return 1.0 }
      return counts[c] > 0 && counts[0] > 0 ? min(cap, Double(counts[0]) / Double(counts[c])) : cap
    }
  }
}
