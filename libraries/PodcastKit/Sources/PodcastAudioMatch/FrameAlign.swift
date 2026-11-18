// LOFI-FORK: lines up two downloads of one episode by frame hashes (see FORK.md).
import Foundation

/// A stretch of one copy that has no equal in the other: frames `a` of the first copy where
/// frames `b` of the second stand. One side can be empty (an ad that only one copy has).
public struct FrameDifference: Equatable, Sendable {
  public var a: Range<Int>
  public var b: Range<Int>
  public init(a: Range<Int>, b: Range<Int>) {
    self.a = a
    self.b = b
  }
}

public struct FrameAlignment: Equatable, Sendable {
  /// Where the copies differ and then join again, in order. A difference that never joins
  /// again is not here, because the end of a download is not a join.
  public var differing: [FrameDifference]
  /// How many frames are equal and in the same order in both copies.
  public var matched: Int
  /// The frames after the last join that matched nothing (a copy that ends while still
  /// different, or a cut-off download).
  public var unmatchedTailA: Int
  public var unmatchedTailB: Int
}

public enum FrameAlign {
  /// The copies join again only when this many frames in a row are equal, so a stray equal
  /// frame (silence, say) does not count.
  public static let anchor = 8
  /// How far past a difference to look for the join, in frames (about 26 ms each): ten minutes.
  public static let reach = 23_000

  public static func align(_ a: [UInt64], _ b: [UInt64]) -> FrameAlignment {
    var differing: [FrameDifference] = []
    var matched = 0
    var i = 0
    var j = 0
    let grams = gramIndex(b)
    while i < a.count, j < b.count {
      if a[i] == b[j] {
        i += 1
        j += 1
        matched += 1
        continue
      }
      guard let join = nextJoin(a, b, grams, i, j) else { break }
      differing.append(FrameDifference(a: i..<join.i, b: j..<join.j))
      i = join.i
      j = join.j
    }
    return FrameAlignment(
      differing: differing, matched: matched, unmatchedTailA: a.count - i,
      unmatchedTailB: b.count - j)
  }

  private static func key(_ list: [UInt64], _ at: Int) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for k in at..<at + anchor {
      h = (h ^ list[k]) &* 0x0000_0100_0000_01B3
      h ^= h >> 29
    }
    return h
  }

  /// Where each run of `anchor` frames starts in `b`.
  private static func gramIndex(_ b: [UInt64]) -> [UInt64: [Int]] {
    var index: [UInt64: [Int]] = [:]
    guard b.count >= anchor else { return index }
    for at in 0...(b.count - anchor) { index[key(b, at), default: []].append(at) }
    return index
  }

  /// The nearest pair of places, after (i, j), where both copies have the same run of
  /// `anchor` frames: the one that skips the fewest frames in all.
  private static func nextJoin(
    _ a: [UInt64], _ b: [UInt64], _ grams: [UInt64: [Int]], _ i: Int, _ j: Int
  ) -> (i: Int, j: Int)? {
    guard a.count >= anchor else { return nil }
    var best: (i: Int, j: Int)?
    var bestCost = Int.max
    var at = i
    while at <= a.count - anchor, at - i <= reach, at - i < bestCost {
      if let places = grams[key(a, at)] {
        for place in places where place >= j {
          if a[at..<at + anchor].elementsEqual(b[place..<place + anchor]) {
            let cost = (at - i) + (place - j)
            if cost < bestCost {
              bestCost = cost
              best = (at, place)
            }
          }
          break
        }
      }
      at += 1
    }
    return best
  }
}
