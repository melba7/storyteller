// LOFI-FORK: the plain number work of the meaning model (see FORK.md). Foundation only.
import Foundation

/// What the meaning model does to a line's vector before it looks at it.
public enum MeaningVectors {
  /// The vector scaled to length 1. Nil when it is empty, has a number that is not finite, or
  /// has no length to scale by (all zeros, or so small or so large that the length is lost).
  public static func unit(_ vector: [Double]) -> [Double]? {
    guard !vector.isEmpty else { return nil }
    var sum = 0.0
    for number in vector {
      guard number.isFinite else { return nil }
      sum += number * number
    }
    let length = sum.squareRoot()
    guard length.isFinite, length > 0 else { return nil }
    return vector.map { $0 / length }
  }

  /// The straight-line distance between two vectors of one size. Infinite when the sizes differ.
  public static func distance(_ a: [Double], _ b: [Double]) -> Double {
    guard a.count == b.count else { return .infinity }
    var sum = 0.0
    for (x, y) in zip(a, b) { sum += (x - y) * (x - y) }
    return sum.squareRoot()
  }
}

/// Float32 numbers as bytes, least significant byte first, so a file reads the same on every
/// machine. Used for the weights in `ad-meaning.json` and for the Mac's cache of line vectors.
enum Float32Bytes {
  static func encode(_ values: [Float]) -> Data {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(values.count * 4)
    for value in values {
      let bits = value.bitPattern
      for shift in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8(truncatingIfNeeded: bits >> UInt32(shift))) }
    }
    return Data(bytes)
  }

  /// The numbers in `data`, or nil when its length is not a whole number of them.
  static func decode(_ data: Data) -> [Float]? {
    guard data.count % 4 == 0 else { return nil }
    let bytes = [UInt8](data)
    var values: [Float] = []
    values.reserveCapacity(bytes.count / 4)
    var at = 0
    while at < bytes.count {
      let bits =
        UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16
        | UInt32(bytes[at + 3]) << 24
      values.append(Float(bitPattern: bits))
      at += 4
    }
    return values
  }
}
