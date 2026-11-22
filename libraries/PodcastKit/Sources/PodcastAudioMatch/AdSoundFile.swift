// LOFI-FORK: finds taught ad sounds in a downloaded file or in the first bytes of a stream (see FORK.md).
import Foundation

public enum AdSoundFile {
  /// How many bytes are read at a time, so a long episode is never in memory at once.
  public static let defaultChunkSize = 1 << 20

  /// The taught sounds in the MP3 file at `url`, in the order they play. Nothing when the file
  /// is missing, cannot be read, is not MP3 or the library is empty.
  public static func hits(
    in url: URL, library: AdSoundLibrary, chunkSize: Int = defaultChunkSize
  ) -> [AdSoundHit] {
    guard !library.sounds.isEmpty, chunkSize > 0,
      let handle = try? FileHandle(forReadingFrom: url)
    else { return [] }
    defer { try? handle.close() }
    var reader = MP3FrameReader()
    var scanner = AdSoundScanner(library: library)
    var found: [AdSoundHit] = []
    // A folder opens but cannot be read: that ends the loop at once, like the end of a file.
    while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
      found += scanner.feed(reader.feed([UInt8](chunk)))
    }
    return ordered(found)
  }

  /// The taught sounds in `data`, the first bytes of a stream or a whole file held in memory.
  public static func hits(
    in data: Data, library: AdSoundLibrary, chunkSize: Int = defaultChunkSize
  ) -> [AdSoundHit] {
    guard !library.sounds.isEmpty, chunkSize > 0 else { return [] }
    var reader = MP3FrameReader()
    var scanner = AdSoundScanner(library: library)
    var found: [AdSoundHit] = []
    var at = data.startIndex
    while at < data.endIndex {
      let end = data.index(at, offsetBy: chunkSize, limitedBy: data.endIndex) ?? data.endIndex
      found += scanner.feed(reader.feed([UInt8](data[at..<end])))
      at = end
    }
    return ordered(found)
  }

  private static func ordered(_ hits: [AdSoundHit]) -> [AdSoundHit] {
    hits.sorted { ($0.start, $0.sound) < ($1.start, $1.sound) }
  }
}
