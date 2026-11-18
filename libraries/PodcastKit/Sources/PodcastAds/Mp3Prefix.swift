// LOFI-FORK: where to cut the start of a growing MP3 file (see FORK.md).
//
// An episode that is still downloading has no end, and AVAudioFile cannot be trusted to open
// it. The start of it can be copied to a small file and cut after the last whole frame, so the
// copy is an MP3 file that ends cleanly. Layer III only (what podcasts use); anything else
// gives no cut and the normal path does the work later. Foundation only.
import Foundation

public enum Mp3Prefix {
  /// A cut: how many bytes to keep, and the audio they hold.
  public struct Cut: Equatable, Sendable {
    public var bytes: Int
    /// Where the audio starts: the size of the ID3 tag, or 0.
    public var audioStart: Int
    public var frames: Int
    public var seconds: Double
  }

  private static let rates1 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
  private static let rates2 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]
  private static let hertz1 = [44100, 48000, 32000]

  /// One frame's header at `at`: its length and the audio it holds, or nil when it is none.
  private static func frame(in data: Data, at: Int) -> (length: Int, seconds: Double)? {
    guard at + 4 <= data.count else { return nil }
    let (b1, b2) = (Int(data[at + 1]), Int(data[at + 2]))
    guard data[at] == 0xFF, b1 & 0xE0 == 0xE0 else { return nil }
    let version = (b1 >> 3) & 3  // 3 is MPEG 1, 2 is MPEG 2, 0 is MPEG 2.5, 1 is not used
    guard version != 1, (b1 >> 1) & 3 == 1 else { return nil }  // layer III only
    let rate = b2 >> 4
    let place = (b2 >> 2) & 3
    guard (1...14).contains(rate), place < 3 else { return nil }
    let first = version == 3
    let bitrate = (first ? rates1 : rates2)[rate] * 1000
    let hertz = hertz1[place] / (first ? 1 : (version == 2 ? 2 : 4))
    let length = (first ? 144 : 72) * bitrate / hertz + ((b2 >> 1) & 1)
    return (length, Double(first ? 1152 : 576) / Double(hertz))
  }

  /// What the first bytes of a file say.
  public enum Look: Equatable, Sendable {
    /// The bytes so far end too soon to tell (a tag not whole yet, or no whole frame yet). The
    /// tag's end is given when known, so the caller can wait for the audio after it.
    case needMore(audioStart: Int?)
    /// There is no MP3 audio here: no frame follows the tag within the search window.
    case notMp3
    case cut(Cut)
  }

  /// How far past the tag a first frame is looked for.
  public static let searchWindow = 65_536

  /// The byte where audio starts: 0 without an ID3 tag, the end of the tag with one, nil when
  /// the tag's own header is not whole yet.
  public static func audioStart(_ data: Data) -> Int? {
    guard data.count >= 3 else { return nil }
    guard data[0] == 0x49, data[1] == 0x44, data[2] == 0x33 else { return 0 }  // "ID3"
    guard data.count >= 10 else { return nil }
    let size = (0..<4).reduce(0) { $0 << 7 | Int(data[6 + $1] & 0x7F) }
    return 10 + size + (data[5] & 0x10 != 0 ? 10 : 0)
  }

  /// Looks at `data`, the first bytes of a file. The first frame must be followed at once by
  /// another valid header (a stray 0xFF 0xEx in a tag's padding is not a frame). With `complete`
  /// (these are all the bytes there will be) a last frame needs no frame after it.
  public static func look(_ data: Data, complete: Bool = false) -> Look {
    guard let start = audioStart(data) else { return .needMore(audioStart: nil) }
    guard start <= data.count else { return .needMore(audioStart: start) }
    var at = start
    let searchEnd = min(data.count, start + searchWindow)
    var found = false
    while at < searchEnd {
      if let first = frame(in: data, at: at) {
        let next = at + first.length
        if next + 4 <= data.count {
          if frame(in: data, at: next) != nil { found = true; break }
        } else if complete, next <= data.count {
          found = true
          break
        } else {
          return .needMore(audioStart: start)  // cannot be checked yet
        }
      }
      at += 1
    }
    guard found else {
      return data.count >= start + searchWindow ? .notMp3 : .needMore(audioStart: start)
    }
    var frames = 0
    var seconds = 0.0
    while let next = frame(in: data, at: at), at + next.length <= data.count {
      at += next.length
      frames += 1
      seconds += next.seconds
    }
    return .cut(Cut(bytes: at, audioStart: start, frames: frames, seconds: seconds))
  }

  /// The cut of `data`, or nil when there is none (yet).
  public static func cut(_ data: Data, complete: Bool = false) -> Cut? {
    if case .cut(let cut) = look(data, complete: complete) { return cut }
    return nil
  }
}
