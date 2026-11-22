// LOFI-FORK: cuts MP3 frames out of a download as its bytes arrive (see FORK.md).
import Foundation

/// Cuts MP3 frames out of bytes that arrive in pieces, in order from the start of a file. It
/// follows the rules of `MP3Frames.parse`, so any split of a file's bytes gives the frames that
/// `parse` gives for the whole file, except that a last frame that is cut short is never returned.
public struct MP3FrameReader: Sendable {
  private var buffer: [UInt8] = []  // the bytes after the last frame that was cut
  private var base = 0  // where in the file `buffer[0]` is
  private var time = 0.0
  private var synced = false  // the last step ended exactly on a frame
  private var tagLeft = 0  // bytes of the ID3 tag still to be skipped
  private var started = false  // whether the start of the file has been looked at

  public init() {}

  /// How many bytes are held back until the next call.
  var pending: Int { buffer.count }

  /// The frames that are whole now. Their `offset` counts from the start of the file and their
  /// `start` from the first frame.
  public mutating func feed(_ bytes: [UInt8]) -> [MP3Frame] {
    buffer += bytes
    if !started {
      // A file starts with an ID3 tag only when its first ten bytes say so.
      if buffer.count < 10, "ID3".utf8.starts(with: buffer.prefix(3)) { return [] }
      started = true
      tagLeft = MP3Frames.tagSize(buffer)
    }
    if tagLeft > 0 {
      let skipped = min(tagLeft, buffer.count)
      buffer.removeFirst(skipped)
      base += skipped
      tagLeft -= skipped
    }
    guard tagLeft == 0 else { return [] }
    var frames: [MP3Frame] = []
    var at = 0
    while at + 4 <= buffer.count {
      guard let head = MP3Frames.header(buffer, at) else {
        at += 1
        synced = false
        continue
      }
      // A whole frame is needed, and unless the last step ended on a frame, the next header too.
      guard at + head.length <= buffer.count else { break }
      if !synced {
        guard at + head.length + 4 <= buffer.count else { break }
        guard MP3Frames.header(buffer, at + head.length)?.sampleRate == head.sampleRate else {
          at += 1
          continue
        }
      }
      var frame = MP3Frames.makeFrame(buffer, at: at, head: head, start: time)
      frame.offset += base
      frames.append(frame)
      time += head.duration
      at += head.length
      synced = true
    }
    buffer.removeFirst(at)
    base += at
    return frames
  }
}
