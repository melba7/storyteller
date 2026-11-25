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

  /// The stretches of an episode that can become sounds, as the sound bank keeps them: for each
  /// marked stretch of a kept sort, the frames from the first that starts a margin into it to the
  /// last that ends a margin before its end, when they last from `minSeconds` to `maxSeconds`.
  /// Only the low 32 bits of each frame's hash are kept, which is all the matching reads, and its
  /// time as seconds from the first frame of the stretch.
  public static func slice(frames: [MP3Frame], marked: [MarkedStretch]) -> [BankedStretch] {
    marked.compactMap { stretch in
      guard AdSoundLibrary.sorts.contains(stretch.sort) else { return nil }
      let from = firstFrame(startingAt: stretch.start + margin - 1e-9, in: frames)
      var to = from
      while to < frames.count, frames[to].start + frames[to].duration <= stretch.end - margin + 1e-9 {
        to += 1
      }
      guard from < to else { return nil }
      let origin = frames[from].start
      let banked = BankedStretch(
        sort: stretch.sort, who: stretch.who,
        frames: frames[from..<to].map {
          BankedFrame(
            hash: UInt32(truncatingIfNeeded: $0.hash), start: Float($0.start - origin),
            duration: Float($0.duration))
        })
      return fits(banked) ? banked : nil
    }
  }

  /// Whether a stretch lasts long enough, and not too long, to be a sound.
  private static func fits(_ stretch: BankedStretch) -> Bool {
    (minSeconds...maxSeconds).contains(stretch.seconds)
  }

  /// Adds one episode: its frames and its marked stretches. A stretch that is a sound already
  /// added counts that sound as seen once more; otherwise it becomes a new sound.
  public mutating func add(episode: String, frames: [MP3Frame], marked: [MarkedStretch]) {
    add(episode: episode, stretches: Self.slice(frames: frames, marked: marked))
  }

  /// Adds one episode from its banked stretches, which is all it needs of the audio: this is
  /// the one path that learns, so the library is the same whether the stretches were cut from
  /// the audio just now or were read from the sound bank later.
  public mutating func add(episode: String, stretches: [BankedStretch]) {
    for stretch in stretches where AdSoundLibrary.sorts.contains(stretch.sort) && Self.fits(stretch) {
      // Only the hash and the times of these frames matter; the rest is left plain.
      let slice = stretch.frames.map {
        MP3Frame(
          offset: 0, length: 0, start: Double($0.start), duration: Double($0.duration),
          hash: UInt64($0.hash), bitrate: 0, sampleRate: 0, channels: 0, hasInfoTag: false,
          mainDataBegin: nil)
      }
      let seconds = stretch.seconds
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
  private static func firstFrame(startingAt time: Double, in frames: [MP3Frame]) -> Int {
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
