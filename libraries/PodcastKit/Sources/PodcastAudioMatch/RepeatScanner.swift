// LOFI-FORK: finds the stretches of a new episode that an older episode already had (see FORK.md).
import Foundation

/// A stretch of the new file that follows an older print. Seconds in the new file, accurate to one
/// anchor step (0.21 s); it lies inside the real repeat, so a little of each edge may be missing.
public struct RepeatStretch: Sendable, Equatable {
  public var start: Double
  public var end: Double

  public init(start: Double, end: Double) {
    self.start = start
    self.end = end
  }
}

/// Matches the frames of a new episode against the prints of older episodes of the same show.
///
/// A print holds the hash of every eighth frame of an older file. Every frame of the new file is
/// looked up in one sorted index of those numbers (a binary search, so the work grows with the
/// length of the file and not with the number of older anchors). A frame that is an anchor of an
/// older print is a hit; the hits that follow the print form a run: each next hit is a later anchor
/// of the same print, at most `maxMissing` anchors on, at a place in the new file that keeps the
/// offset between old and new positions to within one anchor step. Anchors that are missing
/// inside a run (a few damaged frames) are allowed, but a run is a repeat only when `minShare` of
/// its anchors matched and it lasts `minSeconds`. State held while scanning: the runs that are
/// still going, which are few, and the stretches found so far.
public struct RepeatScanner: Sendable {
  /// The shortest stretch that is a repeat.
  public static let minSeconds = 8.0
  /// A stretch that starts in the first minute is left to the show's opening (the theme).
  public static let openingSeconds = 60.0
  /// Anchors that may be missing in a row inside a run.
  public static let maxMissing = 3
  /// The share of the anchors inside a run that must match.
  public static let minShare = 0.7
  /// Stretches that are less than this many seconds apart (also from two older episodes, or with a
  /// longer hole between them) are given as one.
  public static let mergeGap = 2.0
  /// An older print that matches more than this share of the new file is the same recording again
  /// (a second download), not something that repeats in the show: it gives nothing.
  public static let maxShare = 0.5
  /// The most older prints looked at together (a show keeps three).
  static let maxPrints = 16
  private static let sweepEvery = 64
  private static let staleFrames = (maxMissing + 2) * EpisodePrint.step

  /// A run of hits: the diagonal is the new frame number less the old frame number of the anchor.
  private struct Run: Sendable {
    var print: Int
    var diagonal: Int
    var firstAnchor: Int
    var lastAnchor: Int
    var hits: Int
    var lastFrame: Int  // the new file's frame of the latest hit
    var start: Double  // the start of the first hit's frame
    var end: Double  // the end of the latest hit's frame
  }

  private struct Key: Hashable, Sendable {
    var print: Int
    var bucket: Int  // the diagonal divided by the step, rounded down
  }

  private struct Found: Sendable {
    var print: Int
    var start: Double
    var end: Double
  }

  /// Every anchor of every older print, sorted: the anchor in the top 32 bits, the print in the
  /// next 8 and the anchor's place in the print in the lowest 24.
  private let index: [UInt64]
  private var runs: [Key: Run] = [:]
  private var found: [Found] = []
  private var count = 0  // frames fed so far
  private var seconds = 0.0  // the length of the audio fed so far

  /// `older` are the prints to look for, `episode` the id of the file that is scanned: a print with
  /// that id is left out (an episode never repeats itself).
  public init(older: [EpisodePrint], episode: String = "") {
    var entries: [UInt64] = []
    let usable = older.filter { episode.isEmpty || $0.episode != episode }.prefix(Self.maxPrints)
    for (slot, item) in usable.enumerated() {
      for (place, anchor) in item.anchors.prefix(EpisodePrint.maxAnchors).enumerated() {
        entries.append(UInt64(anchor) << 32 | UInt64(slot) << 24 | UInt64(place))
      }
    }
    entries.sort()
    index = entries
  }

  /// Feed the frames of the new file in order, in as many calls as you like. A frame whose times
  /// are not numbers is passed over (it still counts as a frame).
  public mutating func feed(_ frames: [MP3Frame]) {
    for frame in frames {
      let number = count
      count += 1
      if number % Self.sweepEvery == 0 { sweep(at: number) }
      let end = frame.start + frame.duration
      guard frame.start.isFinite, end.isFinite, frame.duration >= 0, !index.isEmpty else { continue }
      seconds = max(seconds, end)
      let anchor = UInt64(UInt32(truncatingIfNeeded: frame.hash))
      let first = firstPlace(from: anchor << 32)
      var stop = first
      while stop < index.count, index[stop] >> 32 == anchor, stop - first < 4 { stop += 1 }
      // A number in many places says little (a silent stretch), so it starts nothing.
      guard stop > first, stop - first <= 3 else { continue }
      for entry in index[first..<stop] {
        hit(
          print: Int(entry >> 24 & 0xFF), anchor: Int(entry & 0xFF_FFFF), frame: number,
          start: frame.start, end: end)
      }
    }
  }

  /// The stretches of the file fed so far, in order of time. Call it once after the last frames.
  /// The scanner is empty afterwards and may scan another file.
  public mutating func finish() -> [RepeatStretch] {
    for run in runs.values { close(run) }
    let all = found
    let total = seconds
    runs = [:]
    found = []
    count = 0
    seconds = 0
    var perPrint: [Int: Double] = [:]
    for item in all { perPrint[item.print, default: 0] += item.end - item.start }
    let kept = all.filter {
      $0.start >= Self.openingSeconds && perPrint[$0.print, default: 0] <= Self.maxShare * total
    }.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    var stretches: [RepeatStretch] = []
    for item in kept {
      if let last = stretches.last, item.start <= last.end + Self.mergeGap {
        stretches[stretches.count - 1].end = max(last.end, item.end)
      } else {
        stretches.append(RepeatStretch(start: item.start, end: item.end))
      }
    }
    return stretches
  }

  // MARK: runs

  /// The index of the first entry that is `key` or more.
  private func firstPlace(from key: UInt64) -> Int {
    var low = 0
    var high = index.count
    while low < high {
      let middle = (low + high) / 2
      if index[middle] < key { low = middle + 1 } else { high = middle }
    }
    return low
  }

  private static func bucket(_ diagonal: Int) -> Int {
    let step = EpisodePrint.step
    let whole = diagonal / step
    return diagonal % step < 0 ? whole - 1 : whole
  }

  /// One frame of the new file that is anchor `anchor` of the older print `slot`.
  private mutating func hit(print slot: Int, anchor: Int, frame: Int, start: Double, end: Double) {
    let step = EpisodePrint.step
    let diagonal = frame - step * anchor
    let bucket = Self.bucket(diagonal)
    for near in (bucket - 1)...(bucket + 1) {
      let key = Key(print: slot, bucket: near)
      guard var run = runs[key], abs(run.diagonal - diagonal) <= step else { continue }
      if anchor <= run.lastAnchor || frame <= run.lastFrame { return }  // the same place again
      guard anchor - run.lastAnchor <= Self.maxMissing + 1 else { continue }
      run.lastAnchor = anchor
      run.hits += 1
      run.lastFrame = frame
      run.end = max(run.end, end)
      runs[key] = run
      return
    }
    let key = Key(print: slot, bucket: bucket)
    if let old = runs[key] { close(old) }
    runs[key] = Run(
      print: slot, diagonal: diagonal, firstAnchor: anchor, lastAnchor: anchor, hits: 1,
      lastFrame: frame, start: start, end: end)
  }

  /// Ends the runs that no hit has joined for longer than one can still join them.
  private mutating func sweep(at frame: Int) {
    for (key, run) in runs where frame - run.lastFrame > Self.staleFrames {
      runs[key] = nil
      close(run)
    }
  }

  /// Keeps what a run found when it is a repeat.
  private mutating func close(_ run: Run) {
    let span = run.lastAnchor - run.firstAnchor + 1
    guard run.end - run.start >= Self.minSeconds, Double(run.hits) >= Self.minShare * Double(span)
    else { return }
    found.append(Found(print: run.print, start: run.start, end: run.end))
  }
}
