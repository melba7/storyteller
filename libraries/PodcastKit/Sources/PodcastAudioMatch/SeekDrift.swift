// LOFI-FORK: how far off Apple's player can land when it seeks in an MP3 file (see FORK.md).
//
// AVFoundation does not read an MP3 file's frame table when a player item is made from its address.
// To seek to a time it jumps to the byte `time / duration × size`, which is right only when every
// frame is the same size (one steady bitrate). Marco Arment measured errors of over a minute on
// variable bitrate files (marco.org/2016/08). This reads the frames MP3Frames found, so the
// error can be worked out for any file. Foundation only.
import Foundation

public struct Seam: Equatable, Sendable {
  /// Seconds from the first frame.
  public var time: Double
  /// What changes there, in plain words.
  public var reason: String
}

public struct SeekDriftReport: Equatable, Sendable {
  /// How many frames there are at each bitrate (bits per second).
  public var framesPerBitrate: [Int: Int]
  /// Whether one bitrate holds for 99% of the frames, so a ratio guess is right.
  public var steady: Bool
  /// The largest gap, in seconds, between a time that is asked for and the time of the byte the
  /// ratio guess lands on.
  public var worstSeconds: Double
  /// Where the encoding changes for good: the header (bitrate, sample rate or channels) changes
  /// and holds for at least `SeekDrift.seamFrames` frames, or an Xing or Info tag sits in a
  /// frame after the first (two files joined). Often where an ad was spliced in.
  public var seams: [Seam]
  /// The frames (counted from 0 after the ID3 tag) whose bit reservoir pointer is 0 right after
  /// `SeekDrift.resetAfter` frames or more with a pointer above 0. A piece of audio that was
  /// encoded on its own starts that way, so this may mark where a spot was joined in.
  public var reservoirResets: [Int]
}

public enum SeekDrift {
  /// A change in the header is a seam only when the new header holds for this many frames.
  public static let seamFrames = 50
  /// A pointer of 0 is a reset only after this many frames in a row with a pointer above 0.
  public static let resetAfter = 50
  /// The share of frames that one bitrate must have for the file to count as steady.
  public static let steadyShare = 0.99

  public static func report(_ parse: MP3Parse) -> SeekDriftReport {
    let frames = parse.frames
    var perBitrate: [Int: Int] = [:]
    for frame in frames { perBitrate[frame.bitrate, default: 0] += 1 }
    let most = perBitrate.values.max() ?? 0
    return SeekDriftReport(
      framesPerBitrate: perBitrate,
      steady: !frames.isEmpty && Double(most) >= steadyShare * Double(frames.count),
      worstSeconds: worst(frames), seams: seams(frames),
      reservoirResets: reservoirResets(frames))
  }

  /// For each frame: the time asked for is the frame's start, the guess is the byte at the same
  /// share of the file, and the landing is the time of the audio at that byte.
  private static func worst(_ frames: [MP3Frame]) -> Double {
    guard let first = frames.first, let last = frames.last else { return 0 }
    let total = Double(last.offset + last.length - first.offset)
    let seconds = last.start + last.duration
    guard total > 0, seconds > 0 else { return 0 }
    var worst = 0.0
    var at = 0  // the frame the guess falls in; the guess only moves forward
    for frame in frames {
      let byte = frame.start / seconds * total
      while at + 1 < frames.count, Double(frames[at + 1].offset - first.offset) <= byte { at += 1 }
      let landed = frames[at]
      let inside = (byte - Double(landed.offset - first.offset)) / Double(landed.length)
      let time = landed.start + min(1, max(0, inside)) * landed.duration
      worst = max(worst, abs(time - frame.start))
    }
    return worst
  }

  private struct Header: Equatable {
    var bitrate: Int
    var sampleRate: Int
    var channels: Int

    init(_ frame: MP3Frame) {
      bitrate = frame.bitrate
      sampleRate = frame.sampleRate
      channels = frame.channels
    }

    var words: String { "\(bitrate / 1000) kbps, \(sampleRate) Hz, \(channels == 1 ? "mono" : "stereo")" }
  }

  private static func seams(_ frames: [MP3Frame]) -> [Seam] {
    var found: [Seam] = []
    var held: Header?  // the header of the last stretch that held for `seamFrames` frames
    var at = 0
    while at < frames.count {
      let header = Header(frames[at])
      var end = at + 1
      while end < frames.count, Header(frames[end]) == header { end += 1 }
      if end - at >= seamFrames {
        if let held, held != header {
          found.append(Seam(time: frames[at].start, reason: "\(held.words) becomes \(header.words)"))
        }
        held = header
      }
      at = end
    }
    for frame in frames.dropFirst() where frame.hasInfoTag {
      found.append(Seam(time: frame.start, reason: "an Xing or Info tag in the middle of the file"))
    }
    return found.sorted { $0.time < $1.time }
  }

  private static func reservoirResets(_ frames: [MP3Frame]) -> [Int] {
    var found: [Int] = []
    var reaching = 0  // frames in a row that reach back into the reservoir
    for (index, frame) in frames.enumerated() {
      guard let pointer = frame.mainDataBegin else {
        reaching = 0
        continue
      }
      if pointer > 0 {
        reaching += 1
        continue
      }
      if reaching >= resetAfter { found.append(index) }
      reaching = 0
    }
    return found
  }
}
