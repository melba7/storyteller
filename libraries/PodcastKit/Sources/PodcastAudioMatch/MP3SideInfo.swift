// LOFI-FORK: reads the bit reservoir pointer of an MP3 frame (see FORK.md).
//
// A Layer III frame does not have to hold all of its own audio data: the first 9 bits (MPEG-1) or
// 8 bits (MPEG-2 and 2.5) of its side information say how many bytes back, in the frames before it,
// its data begins. That is the bit reservoir. A pointer of 0 means the frame needs nothing from
// the frames before it. An encoder that starts a file on its own starts with an empty reservoir,
// so in a file that was joined from pieces a frame with pointer 0 after a long stretch of frames
// that reach back may be where a piece begins. Foundation only.
import Foundation

public enum MP3SideInfo {
  /// The pointer, from the first bytes of a frame (the header, the checksum if there is one, then
  /// the side information). Nil when the bytes are not a Layer III frame or are cut short.
  public static func mainDataBegin(_ frame: Data) -> Int? {
    mainDataBegin(Array(frame.prefix(8)), at: 0)
  }

  /// The same for the frame that starts at `at` in `bytes`.
  static func mainDataBegin(_ bytes: [UInt8], at: Int) -> Int? {
    guard at >= 0, at + 4 <= bytes.count, bytes[at] == 0xFF, bytes[at + 1] & 0xE0 == 0xE0
    else { return nil }
    let versionBits = Int(bytes[at + 1] >> 3) & 3  // 0: 2.5, 1: reserved, 2: MPEG-2, 3: MPEG-1
    let layerBits = Int(bytes[at + 1] >> 1) & 3  // 1: Layer III
    guard versionBits != 1, layerBits == 1 else { return nil }
    let sideInfo = at + 4 + (bytes[at + 1] & 1 == 0 ? 2 : 0)  // two bytes of checksum may come first
    if versionBits == 3 {
      guard sideInfo + 2 <= bytes.count else { return nil }
      return Int(bytes[sideInfo]) << 1 | Int(bytes[sideInfo + 1] >> 7)
    }
    guard sideInfo + 1 <= bytes.count else { return nil }
    return Int(bytes[sideInfo])
  }
}
