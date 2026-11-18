// LOFI-FORK: finds stretches that are the same bytes in two different episodes (see FORK.md).
//
// A host that stitches an ad into an episode may copy the ad's MP3 frames as they are, so the same
// spot in two episodes would be the same bytes and could be recognised without any transcript.
// This only measures whether that happens: it finds the equal stretches and says what the bytes
// look like at each edge (the reset of the bit reservoir, a change of encoding). Foundation only.
import Foundation

public struct SharedRun: Equatable, Sendable {
  /// The frames of the first file and of the second file that hold the same bytes.
  public var a: Range<Int>
  public var b: Range<Int>

  public init(a: Range<Int>, b: Range<Int>) {
    self.a = a
    self.b = b
  }
}

/// What the bytes say at one edge of a run, in one file.
public struct EdgeEvidence: Equatable, Sendable {
  /// How many frames from the edge the nearest reservoir reset is (negative: before it), or nil.
  public var reset: Int?
  /// The change of encoding near the edge, in words, or nil.
  public var seam: String?

  public var any: Bool { reset != nil || seam != nil }
}

public enum SharedRuns {
  /// A run is at least this many frames (115 frames is 3 s).
  public static let defaultMinFrames = 115
  /// A run holds at least this many different frames, so digital silence is not a run.
  public static let minDistinct = 20
  /// A frame that occurs more often than this in the second file starts no search (silence, say),
  /// which keeps the search quick. It can still be inside a run.
  static let seedLimit = 16
  /// A reset or a seam counts as being at an edge when it is this many frames or fewer from it.
  public static let edgeReach = 2

  /// The runs of frames that are the same bytes in both files, in the order of the first file. The
  /// two files need not hold them in the same order, because the same spot can sit anywhere. A
  /// run goes on as far as the frames stay equal.
  public static func find(
    _ a: MP3Parse, _ b: MP3Parse, minFrames: Int = SharedRuns.defaultMinFrames
  ) -> [SharedRun] {
    find(a.frames.map(\.hash), b.frames.map(\.hash), minFrames: minFrames)
  }

  static func find(_ a: [UInt64], _ b: [UInt64], minFrames: Int) -> [SharedRun] {
    guard !a.isEmpty, !b.isEmpty else { return [] }
    var places: [UInt64: [Int]] = [:]
    for (index, hash) in b.enumerated() { places[hash, default: []].append(index) }
    var runs: [SharedRun] = []
    var covered: [Int: Int] = [:]  // for each shift (i - j), where in `a` the last run on it ended
    for i in a.indices {
      guard let spots = places[a[i]], spots.count <= seedLimit else { continue }
      for j in spots {
        if let end = covered[i - j], i < end { continue }
        var start = i
        var otherStart = j
        while start > 0, otherStart > 0, a[start - 1] == b[otherStart - 1] {
          start -= 1
          otherStart -= 1
        }
        var end = i + 1
        var otherEnd = j + 1
        while end < a.count, otherEnd < b.count, a[end] == b[otherEnd] {
          end += 1
          otherEnd += 1
        }
        covered[i - j] = end
        guard end - start >= minFrames, Set(a[start..<end]).count >= minDistinct else { continue }
        runs.append(SharedRun(a: start..<end, b: otherStart..<otherEnd))
      }
    }
    return runs.sorted { ($0.a.lowerBound, $0.b.lowerBound) < ($1.a.lowerBound, $1.b.lowerBound) }
  }

  /// What the bytes of `parse` say at an edge that sits at frame `frame` (the first frame of a run
  /// for its start, the first frame after it for its end). `report` is `SeekDrift.report(parse)`.
  public static func evidence(
    at frame: Int, in parse: MP3Parse, report: SeekDriftReport
  ) -> EdgeEvidence {
    let reset = report.reservoirResets.map { $0 - frame }.filter { abs($0) <= edgeReach }
      .min { abs($0) < abs($1) }
    let seam = report.seams.first {
      abs(firstFrame(from: $0.time, parse.frames) - frame) <= edgeReach
    }
    return EdgeEvidence(reset: reset, seam: seam?.reason)
  }

  /// The number of the first frame that starts at `time` or later.
  private static func firstFrame(from time: Double, _ frames: [MP3Frame]) -> Int {
    var low = 0
    var high = frames.count
    while low < high {
      let middle = (low + high) / 2
      if frames[middle].start < time - 1e-9 { low = middle + 1 } else { high = middle }
    }
    return low
  }
}
