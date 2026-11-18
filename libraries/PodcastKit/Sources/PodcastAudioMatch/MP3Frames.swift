// LOFI-FORK: cuts MP3 bytes into frames without decoding them (see FORK.md).
import Foundation

public struct MP3Frame: Equatable, Sendable {
  /// Where the frame starts in the bytes, and how long it is.
  public var offset: Int
  public var length: Int
  /// Seconds from the first frame after the ID3 tag.
  public var start: Double
  public var duration: Double
  /// A hash of the frame's bytes. Equal bytes, equal hash.
  public var hash: UInt64
  /// What the frame's header says: bits per second, samples per second and 1 (mono) or 2 channels.
  public var bitrate: Int
  public var sampleRate: Int
  public var channels: Int
  /// Whether the frame holds an Xing or Info tag. The first frame of a file made by an encoder
  /// has one; a tag in a later frame is where two files were joined.
  public var hasInfoTag: Bool
  /// The bit reservoir pointer in the frame's side information (nil when it cannot be read).
  public var mainDataBegin: Int?
}

public struct MP3Parse: Equatable, Sendable {
  public var frames: [MP3Frame]
  /// The size of the ID3 tag at the start (0 when there is none).
  public var tagBytes: Int
  /// Bytes that were not part of any frame after the tag (junk between frames).
  public var skippedBytes: Int
  /// Bits per second of the first frame, 0 with no frames.
  public var bitrate: Int

  public var seconds: Double { frames.last.map { $0.start + $0.duration } ?? 0 }
}

public enum MP3Frames {
  private static let bitrates1 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
  private static let bitrates2 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]
  private static let rates = [44100, 48000, 32000]

  private struct Header {
    var length: Int
    var duration: Double
    var bitrate: Int
    var sampleRate: Int
    var version: Int  // 1 for MPEG-1, 2 for MPEG-2 and 2.5
    var channels: Int
    var crc: Bool  // two bytes of checksum follow the header
  }

  /// The frame header at `at`, or nil when the four bytes there are not a Layer III header.
  private static func header(_ bytes: [UInt8], _ at: Int) -> Header? {
    guard at >= 0, at + 4 <= bytes.count, bytes[at] == 0xFF, bytes[at + 1] & 0xE0 == 0xE0
    else { return nil }
    let versionBits = Int(bytes[at + 1] >> 3) & 3  // 0: 2.5, 1: reserved, 2: MPEG-2, 3: MPEG-1
    let layerBits = Int(bytes[at + 1] >> 1) & 3  // 1: Layer III
    let bitrateIndex = Int(bytes[at + 2] >> 4)
    let rateIndex = Int(bytes[at + 2] >> 2) & 3
    guard versionBits != 1, layerBits == 1, bitrateIndex > 0, bitrateIndex < 15, rateIndex < 3
    else { return nil }
    let mpeg1 = versionBits == 3
    let bitrate = (mpeg1 ? bitrates1 : bitrates2)[bitrateIndex] * 1000
    let divisor = versionBits == 3 ? 1 : (versionBits == 2 ? 2 : 4)
    let sampleRate = rates[rateIndex] / divisor
    let padding = Int(bytes[at + 2] >> 1) & 1
    let samples = mpeg1 ? 1152 : 576
    let length = (mpeg1 ? 144 : 72) * bitrate / sampleRate + padding
    guard length > 4 else { return nil }
    return Header(
      length: length, duration: Double(samples) / Double(sampleRate), bitrate: bitrate,
      sampleRate: sampleRate, version: mpeg1 ? 1 : 2, channels: bytes[at + 3] >> 6 == 3 ? 1 : 2,
      crc: bytes[at + 1] & 1 == 0)
  }

  /// Whether the frame at `at` holds an Xing or Info tag: those four letters come right after the
  /// header, the checksum (if there is one) and the side information.
  private static func hasInfoTag(_ bytes: [UInt8], _ at: Int, _ head: Header) -> Bool {
    let sideInfo = head.version == 1 ? (head.channels == 1 ? 17 : 32) : (head.channels == 1 ? 9 : 17)
    let tag = at + 4 + (head.crc ? 2 : 0) + sideInfo
    guard tag + 4 <= at + head.length else { return false }
    let name = bytes[tag..<tag + 4]
    return name.elementsEqual("Xing".utf8) || name.elementsEqual("Info".utf8)
  }

  /// The size of an ID3v2 tag at the start, with its header and footer, or 0.
  static func tagSize(_ bytes: [UInt8]) -> Int {
    guard bytes.count >= 10, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33,
      bytes[6..<10].allSatisfy({ $0 & 0x80 == 0 })
    else { return 0 }
    let size = bytes[6..<10].reduce(0) { $0 << 7 | Int($1) }
    return 10 + size + (bytes[5] & 0x10 != 0 ? 10 : 0)
  }

  private static func hash(_ bytes: [UInt8], _ range: Range<Int>) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for k in range { h = (h ^ UInt64(bytes[k])) &* 0x0000_0100_0000_01B3 }
    return h
  }

  /// The frames in `bytes`. A header after junk counts only when the next frame's header
  /// follows it, so junk that looks like a header is passed over. A last
  /// frame that is cut short is left out. Never crashes on damaged bytes.
  public static func parse(_ bytes: [UInt8]) -> MP3Parse {
    let tag = tagSize(bytes)
    var result = MP3Parse(frames: [], tagBytes: min(tag, bytes.count), skippedBytes: 0, bitrate: 0)
    var at = tag
    var time = 0.0
    var synced = false  // the last step ended exactly on a frame
    while at + 4 <= bytes.count {
      // A header counts when the bytes end right after it, or the next header follows it, or
      // the frame before it ended right here (so a stream that is in step stays in step).
      guard let head = header(bytes, at), at + head.length <= bytes.count,
        synced || at + head.length == bytes.count
          || header(bytes, at + head.length)?.sampleRate == head.sampleRate
      else {
        at += 1
        synced = false
        if !result.frames.isEmpty { result.skippedBytes += 1 }
        continue
      }
      if result.frames.isEmpty { result.bitrate = head.bitrate }
      result.frames.append(
        MP3Frame(
          offset: at, length: head.length, start: time, duration: head.duration,
          hash: hash(bytes, at..<at + head.length), bitrate: head.bitrate,
          sampleRate: head.sampleRate, channels: head.channels,
          hasInfoTag: hasInfoTag(bytes, at, head),
          mainDataBegin: MP3SideInfo.mainDataBegin(bytes, at: at)))
      time += head.duration
      at += head.length
      synced = true
    }
    return result
  }
}
