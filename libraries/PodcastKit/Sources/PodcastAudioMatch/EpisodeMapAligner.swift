// LOFI-FORK: lines a phone's copy of an episode up against the Mac's map of its own copy (see
// FORK.md, EpisodeMap.swift and docs/PLAN.md, milestones Z4 and Z19). Foundation only.
//
// HOW IT LINES UP. Every 16 frames in a row of the map are in an index. The phone's frames are
// walked from the first: where 16 in a row are in the index, the match is run out as far as the
// frames stay equal, backwards and forwards, and it counts as a run when it is 3 seconds long and
// not digital silence. Inside a run the phone's audio is the Mac's audio frame for frame, so a
// mark of the Mac is carried over by counting frames.
//
// THE RULES (measured on 160 twice-downloaded episodes, docs/PLAN.md Z4):
//   - A stretch of the phone's copy that matches nothing, is 8 seconds or longer and has matched
//     audio on both sides (or the episode's start before it) is an ad only the phone got.
//   - When the copies differ, a carried piece of a mark under 5 seconds is dropped: it is a sliver
//     at the border of a differing stretch, not an ad.
//   - When over 30 in 100 of the episode matches nothing, the copy is another edit of the episode
//     and there is no map: nothing is carried and nothing is called an ad.
import Foundation

/// A stretch of the phone's copy and the map that is the same audio.
public struct MapRun: Equatable, Sendable {
  /// The phone's frames.
  public var heard: Range<Int>
  /// The map's frame that the first of them is.
  public var map: Int
}

/// A mark of the Mac in the phone's seconds.
public struct CarriedMark: Equatable, Sendable {
  public var start: Double
  public var end: Double
  public var kind: String
  /// Where the mark starts in the Mac's copy, which tells which mark it is.
  public var from: Double
}

/// A stretch of the phone's copy, in its seconds.
public struct MapStretch: Equatable, Sendable {
  public var start: Double
  public var end: Double
}

/// What the map gives for the frames a phone has.
public struct MapCarry: Equatable, Sendable {
  /// Whether the copy lines up with the map. When it does not, the lists are empty.
  public var lined = false
  public var marks: [CarriedMark] = []
  /// The ads only the phone's copy has.
  public var unmatched: [MapStretch] = []
}

public struct EpisodeMapAligner: Sendable {
  /// A match starts from this many frames in a row.
  static let seed = 16
  /// A run is at least this many frames (3 seconds) and holds this many different bytes.
  static let minFrames = 115
  static let minDistinct = 20
  /// 16 frames in a row that are in the map more often than this start no match (silence, say).
  static let seedLimit = 16
  /// An unmatched stretch is an ad from this many seconds on.
  public static let minUnmatched = 8.0
  /// A carried piece of a mark shorter than this is dropped when the copies differ.
  public static let minPiece = 5.0
  /// Over this share of the episode unmatched, there is no map.
  public static let mostUnmatched = 0.3
  /// The phone's first frame is the episode's start when it starts before this many seconds.
  static let startSlack = 0.5

  public let map: EpisodeMap
  private let frames: [UInt8]
  /// Every 16 frames in a row of the map: their key and where they start, sorted by key.
  private let keys: [UInt64]
  private let places: [Int32]

  public init(map: EpisodeMap) {
    self.map = map
    frames = [UInt8](map.frames)
    var pairs: [(key: UInt64, at: Int32)] = []
    if frames.count >= Self.seed {
      pairs.reserveCapacity(frames.count - Self.seed + 1)
      for at in 0...(frames.count - Self.seed) {
        pairs.append((Self.key(frames, at), Int32(at)))
      }
    }
    pairs.sort { ($0.key, $0.at) < ($1.key, $1.at) }
    keys = pairs.map(\.key)
    places = pairs.map(\.at)
  }

  /// A number for the 16 bytes from `at`.
  private static func key(_ bytes: [UInt8], _ at: Int) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for index in at..<at + seed { hash = (hash ^ UInt64(bytes[index])) &* 0x0000_0100_0000_01B3 }
    return hash
  }

  /// Where in the map the 16 frames with this key start; none when they are there too often.
  private func starts(of key: UInt64) -> ArraySlice<Int32> {
    var low = 0
    var high = keys.count
    while low < high {
      let middle = (low + high) / 2
      if keys[middle] < key { low = middle + 1 } else { high = middle }
    }
    var end = low
    while end < keys.count, keys[end] == key, end - low <= Self.seedLimit { end += 1 }
    return end - low > Self.seedLimit ? [] : places[low..<end]
  }

  /// The runs of the phone's frames that are in the map, in the phone's order. They never overlap
  /// in the phone's frames.
  public func runs(_ heard: HeardFrames) -> [MapRun] {
    let mine = heard.hashes
    var found: [MapRun] = []
    var at = 0
    var floor = 0  // the phone's frame after the last run
    while at + Self.seed <= mine.count {
      var best: MapRun?
      for place in starts(of: Self.key(mine, at)) {
        var first = at
        var other = Int(place)
        guard mine[at..<at + Self.seed].elementsEqual(frames[other..<other + Self.seed])
        else { continue }
        while first > floor, other > 0, mine[first - 1] == frames[other - 1] {
          first -= 1
          other -= 1
        }
        var end = at + Self.seed
        var otherEnd = Int(place) + Self.seed
        while end < mine.count, otherEnd < frames.count, mine[end] == frames[otherEnd] {
          end += 1
          otherEnd += 1
        }
        if end - first > (best?.heard.count ?? 0) { best = MapRun(heard: first..<end, map: other) }
      }
      guard let run = best, run.heard.count >= Self.minFrames,
        Set(mine[run.heard]).count >= Self.minDistinct
      else {
        at += 1
        continue
      }
      found.append(run)
      at = run.heard.upperBound
      floor = at
    }
    return found
  }

  /// The Mac's marks in the phone's seconds and the ads only the phone has, for the frames the
  /// phone has so far. `complete` says the phone has its whole copy: then what follows the last
  /// run counts as unmatched too when the 30 in 100 rule is checked.
  public func carry(_ heard: HeardFrames, complete: Bool = false) -> MapCarry {
    let runs = runs(heard)
    guard let first = runs.first, let last = runs.last else { return MapCarry() }
    let atStart = (heard.starts.first ?? 0) < Self.startSlack
    // What matches nothing, on each side.
    var gaps: [Range<Int>] = []
    if first.heard.lowerBound > 0 { gaps.append(0..<first.heard.lowerBound) }
    for (before, after) in zip(runs, runs.dropFirst()) {
      gaps.append(before.heard.upperBound..<after.heard.lowerBound)
    }
    var lost = gaps.reduce(0.0) { $0 + heard.time($1.upperBound) - heard.time($1.lowerBound) }
    if complete { lost += heard.end - heard.time(last.heard.upperBound) }
    let covered = runs.reduce(0) { $0 + $1.heard.count }
    let from = atStart ? 0 : runs.map(\.map).min() ?? 0
    let to = complete ? frames.count : runs.map { $0.map + $0.heard.count }.max() ?? 0
    let missing = Double(max(0, to - from - covered)) * map.frameSeconds
    guard lost <= Self.mostUnmatched * max(map.duration, heard.end),
      missing <= Self.mostUnmatched * map.duration
    else { return MapCarry() }

    var carry = MapCarry(lined: true)
    carry.unmatched = gaps.enumerated().compactMap { index, gap in
      // The stretch before the first run is bounded only by the episode's start.
      if index == 0, first.heard.lowerBound > 0, !atStart { return nil }
      let stretch = MapStretch(start: heard.time(gap.lowerBound), end: heard.time(gap.upperBound))
      return stretch.end - stretch.start >= Self.minUnmatched ? stretch : nil
    }
    let differs =
      runs.count > 1 || first.heard.lowerBound > 0 || (atStart && first.map > 0)
      || (complete && (last.heard.upperBound < heard.count || to - from > covered))
    carry.marks = pieces(of: runs, in: heard).filter {
      !differs || $0.end - $0.start >= Self.minPiece
    }
    return carry
  }

  /// Each mark's pieces in the phone's seconds, by start. Pieces of one mark in runs that follow
  /// each other in the phone's copy and in the map are one piece when the mark reaches from the
  /// one run's last frame to the other's first: what the phone has between them then stands
  /// where the Mac's copy had only that mark's audio. Runs that follow each other only in the
  /// phone's copy (an ad that sits in another slot there) have the show between them.
  private func pieces(of runs: [MapRun], in heard: HeardFrames) -> [CarriedMark] {
    var found: [CarriedMark] = []
    for mark in map.marks {
      let low = Int((mark.start / map.frameSeconds).rounded())
      let high = Int((mark.end / map.frameSeconds).rounded())
      var lastRun: Int?
      var lastEnd = 0  // the map's frame where the last piece ended
      for (number, run) in runs.enumerated() {
        let begin = max(low, run.map)
        let end = min(high, run.map + run.heard.count)
        guard begin < end else { continue }
        let start = heard.time(run.heard.lowerBound + begin - run.map)
        let finish = heard.time(run.heard.lowerBound + end - run.map)
        if let lastRun, lastRun == number - 1, begin == run.map,
          lastEnd == runs[lastRun].map + runs[lastRun].heard.count, run.map >= lastEnd
        {
          found[found.count - 1].end = finish
        } else {
          found.append(CarriedMark(start: start, end: finish, kind: mark.kind, from: mark.start))
        }
        lastRun = number
        lastEnd = end
      }
    }
    return found.sorted { $0.start < $1.start }
  }
}

/// Follows a phone's copy as its bytes arrive, in order from the start of the file, and says what
/// the map gives for the audio so far.
public struct EpisodeMapFollower: Sendable {
  public let aligner: EpisodeMapAligner
  private var reader = MP3FrameReader()
  public private(set) var heard = HeardFrames()
  /// How many bytes of the file were fed.
  public private(set) var bytesFed = 0

  public init(map: EpisodeMap) { aligner = EpisodeMapAligner(map: map) }

  /// The next bytes of the file.
  public mutating func feed(_ bytes: [UInt8]) {
    bytesFed += bytes.count
    heard.add(reader.feed(bytes))
  }

  public func carry(complete: Bool = false) -> MapCarry { aligner.carry(heard, complete: complete) }
}
