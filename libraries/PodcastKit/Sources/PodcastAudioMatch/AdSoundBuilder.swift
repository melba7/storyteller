// LOFI-FORK: makes the library of ad sounds from the ads marked in the teaching episodes (see FORK.md).
import Foundation

/// A stretch of an episode that was marked as an ad, in seconds.
public struct MarkedStretch: Sendable, Equatable {
  public var start: Double
  public var end: Double
  public var sort: String
  public var who: String

  public init(start: Double, end: Double, sort: String, who: String) {
    self.start = start
    self.end = end
    self.sort = sort
    self.who = who
  }
}

public struct AdSoundBuilder: Sendable {
  public static let minSeconds = 8.0
  /// Seconds left off each end of a marked stretch, whose edges are only as exact as transcript lines.
  public static let margin = 1.0
  static let maxSeconds = 600.0

  private var sounds: [AdSound] = []
  private var episodes: [Set<String>] = []  // for each sound, the episodes it was seen in
  private var scanner: AdSoundScanner?  // over the sounds so far; made when needed, then added to
  /// How far the frame counts of two stretches of one sound may differ: a few anchors.
  static let frameTolerance = 4 * AdSoundLibrary.step

  public init() {}

  /// Adds one episode: its frames and its marked stretches. A stretch that is a sound already
  /// added counts that sound as seen once more; otherwise it becomes a new sound.
  public mutating func add(episode: String, frames: [MP3Frame], marked: [MarkedStretch]) {
    for stretch in marked where AdSoundLibrary.sorts.contains(stretch.sort) {
      let from = firstFrame(startingAt: stretch.start + Self.margin - 1e-9, in: frames)
      var to = from
      while to < frames.count, frames[to].start + frames[to].duration <= stretch.end - Self.margin + 1e-9 {
        to += 1
      }
      let slice = Array(frames[from..<to])
      let seconds = slice.reduce(0) { $0 + $1.duration }
      guard seconds >= Self.minSeconds, seconds <= Self.maxSeconds else { continue }
      if let index = knownSound(slice, seconds: seconds) {
        if episodes[index].insert(episode).inserted { sounds[index].seen += 1 }
        continue
      }
      let sound = AdSound(
        sort: stretch.sort, who: stretch.who, frames: slice.count, seconds: seconds, seen: 1,
        anchors: stride(from: 0, to: slice.count, by: AdSoundLibrary.step).map {
          UInt32(truncatingIfNeeded: slice[$0].hash)
        })
      sounds.append(sound)
      episodes.append([episode])
      scanner?.add(sound)
    }
  }

  /// The number of the first frame that starts at `time` or later.
  private func firstFrame(startingAt time: Double, in frames: [MP3Frame]) -> Int {
    var low = 0
    var high = frames.count
    while low < high {
      let middle = (low + high) / 2
      if frames[middle].start < time { low = middle + 1 } else { high = middle }
    }
    return low
  }

  /// The sound already added that is this stretch again, if there is one: it covers at least
  /// half of the frames, and has nearly as many frames as the stretch (a 30 second cut of a
  /// 60 second sound is another sound).
  private mutating func knownSound(_ slice: [MP3Frame], seconds: Double) -> Int? {
    guard !sounds.isEmpty, let first = slice.first else { return nil }
    if scanner == nil { scanner = AdSoundScanner(library: AdSoundLibrary(sounds: sounds)) }
    var scan = scanner!
    // The times count from the stretch's own start, so a sound that began earlier starts at 0.
    let hits =
      scan.feed(slice.map { var frame = $0; frame.start -= first.start; return frame })
      + scan.finish()
    let covered = hits.filter {
      abs(sounds[$0.sound].frames - slice.count) <= Self.frameTolerance
    }.map { (sound: $0.sound, seconds: min($0.end, seconds) - max($0.start, 0)) }
    guard let best = covered.max(by: { $0.seconds < $1.seconds }), best.seconds * 2 >= seconds
    else { return nil }
    return best.sound
  }

  /// The library, the most seen sounds first, cut to fit `maxBytes` when written. The default is
  /// what the Mac publishes (`AdSoundLibrary.publishBytes`), less than the phone accepts.
  public func library(maxBytes: Int = AdSoundLibrary.publishBytes) -> AdSoundLibrary {
    let ordered = sounds.enumerated().sorted { ($0.element.seen, $1.offset) > ($1.element.seen, $0.offset) }
      .map(\.element)
    func fits(_ count: Int) -> Bool {
      ((try? AdSoundLibrary(sounds: Array(ordered.prefix(count))).data().count) ?? Int.max) <= maxBytes
    }
    var low = 0  // this many sounds always fit (none, at the worst)
    var high = ordered.count
    while low < high {
      let middle = (low + high + 1) / 2
      if fits(middle) { low = middle } else { high = middle - 1 }
    }
    return AdSoundLibrary(sounds: Array(ordered.prefix(low)))
  }
}
