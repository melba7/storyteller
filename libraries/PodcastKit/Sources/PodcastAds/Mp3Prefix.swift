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

  /// The cut of `data`, which is the first bytes of a file: past an ID3 tag, up to the end of the
  /// last frame that is whole. Nil when no whole frame is there.
  public static func cut(_ data: Data) -> Cut? {
    var at = 0
    if data.count >= 10, data[0] == 0x49, data[1] == 0x44, data[2] == 0x33 {  // "ID3"
      let size = (0..<4).reduce(0) { $0 << 7 | Int(data[6 + $1] & 0x7F) }
      at = 10 + size + (data[5] & 0x10 != 0 ? 10 : 0)
      guard at <= data.count else { return nil }
    }
    // Junk between the tag and the first frame is stepped over, for a little way.
    let searchEnd = min(data.count, at + 65_536)
    while at < searchEnd, frame(in: data, at: at) == nil { at += 1 }
    var frames = 0
    var seconds = 0.0
    while let next = frame(in: data, at: at), at + next.length <= data.count {
      at += next.length
      frames += 1
      seconds += next.seconds
    }
    return frames > 0 ? Cut(bytes: at, frames: frames, seconds: seconds) : nil
  }
}
