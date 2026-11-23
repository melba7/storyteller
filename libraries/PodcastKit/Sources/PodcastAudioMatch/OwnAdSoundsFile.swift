// LOFI-FORK: reads the frames of the ad stretches of a downloaded file, and nothing else (see FORK.md).
import Foundation

public enum OwnAdSoundsFile {
  /// How many bytes are read at a time, so a long episode is never in memory at once.
  public static let defaultChunkSize = AdSoundFile.defaultChunkSize
  /// The most frames kept: about 26 minutes of audio, far more than the ads of an episode.
  public static let mostFrames = 60_000
  /// The most bytes one read asks for, whatever the caller says.
  static let mostChunkSize = 1 << 24

  /// The frames of the MP3 file at `url` that lie inside the stretches, `(start, end)` in
  /// seconds, in the order they play. The file is read in pieces and only these frames are kept,
  /// so a three hour episode costs as much memory as the ads in it. Reading stops after the last
  /// stretch. A stretch that is not a time, ends before it begins or lasts more than 600 seconds
  /// is left out (one that begins before 0 begins at 0). A short stretch is kept, because Undo
  /// needs the frames of a skip of two seconds, though `learn` takes only stretches of 8 seconds
  /// or more. When `mostFrames` is reached inside a stretch, that stretch is left out whole, so a
  /// print is never made of a part of an ad. Nothing when the file is missing, cannot be read or
  /// is not MP3.
  public static func frames(
    in url: URL, stretches: [(start: Double, end: Double)], chunkSize: Int = defaultChunkSize
  ) -> [MP3Frame] {
    pass(in: url, stretches: stretches, chunkSize: chunkSize).frames
  }

  /// What a read kept and how it went, for the tests.
  struct Pass {
    var frames: [MP3Frame] = []
    var chunks = 0
    var bytes = 0
    /// The most bytes the frame reader held back between two pieces.
    var peakPending = 0
  }

  static func pass(
    in url: URL, stretches: [(start: Double, end: Double)], chunkSize: Int,
    mostFrames: Int = OwnAdSoundsFile.mostFrames
  ) -> Pass {
    var result = Pass()
    var keeper = StretchKeeper(stretches, mostFrames: mostFrames)
    guard !keeper.done, chunkSize > 0, let handle = try? FileHandle(forReadingFrom: url) else {
      return result
    }
    defer { try? handle.close() }
    var reader = MP3FrameReader()
    // A folder opens but cannot be read: that ends the loop at once, like the end of a file.
    while !keeper.done, let chunk = try? handle.read(upToCount: min(chunkSize, mostChunkSize)),
      !chunk.isEmpty
    {
      result.chunks += 1
      result.bytes += chunk.count
      result.frames += keeper.keep(reader.feed([UInt8](chunk)))
      result.peakPending = max(result.peakPending, reader.pending)
    }
    keeper.finish(&result.frames)
    return result
  }
}

/// Chooses the frames that lie inside some stretches, from frames that arrive in order of time.
struct StretchKeeper: Sendable {
  private var stretches: [(start: Double, end: Double)] = []  // in order, none touching another
  private var at = 0  // the stretch the frames are in or before
  private var keptBeforeStretch = 0  // how many frames were kept before the stretch `at`
  private let mostFrames: Int
  private(set) var kept = 0
  /// Whether the limit was reached inside a stretch: the rest of it is not kept.
  private(set) var truncated = false

  init(_ stretches: [(start: Double, end: Double)], mostFrames: Int = OwnAdSoundsFile.mostFrames) {
    self.mostFrames = max(mostFrames, 0)
    let usable = stretches.compactMap { stretch -> (start: Double, end: Double)? in
      guard stretch.start.isFinite, stretch.end.isFinite else { return nil }
      let start = max(stretch.start, 0)
      let length = stretch.end - start
      guard length > 0, length <= AdSoundBuilder.maxSeconds else { return nil }
      return (start, stretch.end)
    }.sorted { $0.start < $1.start }
    for stretch in usable {
      if let last = self.stretches.last, stretch.start <= last.end {
        self.stretches[self.stretches.count - 1].end = max(last.end, stretch.end)
      } else {
        self.stretches.append(stretch)
      }
    }
  }

  /// Whether nothing more can be kept: the frames are past the last stretch, or the limit was
  /// reached inside a stretch.
  var done: Bool { at >= stretches.count || truncated }

  /// The frames of this piece that lie inside a stretch, which are those that overlap it.
  mutating func keep(_ frames: [MP3Frame]) -> [MP3Frame] {
    var result: [MP3Frame] = []
    for frame in frames {
      while at < stretches.count, stretches[at].end <= frame.start {
        at += 1
        keptBeforeStretch = kept
      }
      guard !done else { break }
      if frame.start + frame.duration > stretches[at].start {
        guard kept < mostFrames else {
          truncated = true
          break
        }
        result.append(frame)
        kept += 1
      }
    }
    return result
  }

  /// Call it once after the last piece, with all the frames that `keep` gave. When the limit was
  /// reached inside a stretch, the frames of that stretch are taken off the end: a print made of a
  /// part of an ad would match only that part of it.
  mutating func finish(_ frames: inout [MP3Frame]) {
    guard truncated else { return }
    frames.removeLast(min(kept - keptBeforeStretch, frames.count))
    kept = keptBeforeStretch
  }
}
