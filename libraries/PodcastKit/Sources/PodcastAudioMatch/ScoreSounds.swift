// LOFI-FORK: what the scorecard's sound rows need from a downloaded file, in plain seconds (see
// FORK.md). The rows themselves are `AdScoreLayer`s, which live where both this module and
// PodcastAds can be seen (podcast-teach); this file knows nothing of PodcastAds. Each function
// reads the file in pieces, so a long episode is never in memory at once. Foundation only.
import Foundation

/// A stretch of a file in seconds, with the sort of ad it holds.
public struct SoundSpan: Sendable, Equatable {
  public var start: Double
  public var end: Double
  public var sort: String

  public init(start: Double, end: Double, sort: String = "sponsor") {
    self.start = start
    self.end = end
    self.sort = sort
  }
}

public enum ScoreSounds {
  /// The largest piece read at a time, whatever the caller asks.
  private static let mostChunkSize = 1 << 24

  /// Hands the frames of the MP3 at `url` to `body`, piece by piece in order. False when the file
  /// cannot be opened. A file that is not MP3 gives no frames.
  @discardableResult
  static func readFrames(
    _ url: URL, chunkSize: Int = AdSoundFile.defaultChunkSize, _ body: ([MP3Frame]) -> Void
  ) -> Bool {
    guard chunkSize > 0, let handle = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? handle.close() }
    var reader = MP3FrameReader()
    // A folder opens but cannot be read: that ends the loop at once, like the end of a file.
    while let chunk = try? handle.read(upToCount: min(chunkSize, mostChunkSize)), !chunk.isEmpty {
      body(reader.feed([UInt8](chunk)))
    }
    return true
  }

  // MARK: The phone's own sounds

  /// The phone's own sounds of `show` that play in the file, the ones worth skipping
  /// (`OwnAdSounds.trusted`), in order of time. Nothing when there is no such sound or no file.
  public static func ownSounds(in url: URL, own: OwnAdSounds, show: String) -> [SoundSpan] {
    let library = own.library(for: show)
    guard !library.sounds.isEmpty else { return [] }
    return OwnAdSounds.trusted(AdSoundFile.hits(in: url, library: library)).compactMap { hit in
      guard hit.start.isFinite, hit.end.isFinite, hit.end > hit.start else { return nil }
      return SoundSpan(start: hit.start, end: hit.end, sort: hit.sort)
    }
  }

  /// Learns the stretches of the file that were skipped (`OwnAdSounds.learn`), reading only the
  /// frames inside them. `mac` is the Mac's library: what it holds is not learned again. Returns
  /// how many sounds were added.
  @discardableResult
  public static func learnOwn(
    _ own: inout OwnAdSounds, show: String, in url: URL, stretches: [MarkedStretch],
    mac: AdSoundLibrary = AdSoundLibrary(), now: Double
  ) -> Int {
    guard !stretches.isEmpty else { return 0 }
    let frames = OwnAdSoundsFile.frames(
      in: url, stretches: stretches.map { (start: $0.start, end: $0.end) })
    return own.learn(show: show, frames: frames, stretches: stretches, mac: mac, now: now)
  }

  // MARK: Repeats

  /// One pass over the file: the stretches an older episode of the show also had (`RepeatScanner`),
  /// and the print of this episode (`EpisodePrintBuilder`) for the episodes after it. `date`
  /// orders a show's prints, newest first. The print is nil when the file gave no frames. The
  /// stretches are ads of the sort "sponsor": the kind of a repeat is not known.
  public static func scanRepeats(
    in url: URL, older: [EpisodePrint], episode: String, date: Double
  ) -> (spans: [SoundSpan], print: EpisodePrint?) {
    var scanner = RepeatScanner(older: older, episode: episode)
    var builder = EpisodePrintBuilder()
    var frames = 0
    readFrames(url) { piece in
      frames += piece.count
      if !older.isEmpty { scanner.feed(piece) }
      builder.feed(piece)
    }
    guard frames > 0 else { return ([], nil) }
    let spans = older.isEmpty ? [] : scanner.finish().compactMap { stretch -> SoundSpan? in
      guard stretch.start.isFinite, stretch.end.isFinite, stretch.end > stretch.start else {
        return nil
      }
      return SoundSpan(start: stretch.start, end: stretch.end)
    }
    return (spans, builder.finish(episode: episode, date: date))
  }

  // MARK: Joints

  /// The joints of the file, found in one pass from byte 0 (`JointFinder`). Nil when the file
  /// cannot be opened; a file with no frames has no joints and is not usable.
  public static func joints(in url: URL) -> Joints? {
    var finder = JointFinder()
    guard readFrames(url, { finder.feed($0) }) else { return nil }
    return finder.joints
  }

  /// Moves the start and the end of each stretch onto the joints (`JointSnap.snap`), as the phone
  /// does for the ads of a file: in order of time, each start no earlier than where the stretch
  /// before ENDED after its own move, each end no later than where the stretch after STARTED as
  /// given. The answer is in the order the stretches came in. A stretch that is not a stretch of
  /// finite times is given back as it was and has no say about its neighbours.
  public static func snap(
    _ spans: [SoundSpan], joints: Joints, steadyToo: Bool
  ) -> [SoundSpan] {
    let order = spans.indices.filter {
      spans[$0].start.isFinite && spans[$0].end.isFinite && spans[$0].end > spans[$0].start
    }.sorted { spans[$0].start < spans[$1].start }
    var result = spans
    var previousEnd: Double?
    for (place, index) in order.enumerated() {
      let span = spans[index]
      let nextStart = place + 1 < order.count ? spans[order[place + 1]].start : nil
      let moved = JointSnap.snap(
        start: span.start, end: span.end, joints: joints, previousEnd: previousEnd,
        nextStart: nextStart, steadyToo: steadyToo)
      result[index].start = moved.start
      result[index].end = moved.end
      previousEnd = moved.end
    }
    return result
  }
}
