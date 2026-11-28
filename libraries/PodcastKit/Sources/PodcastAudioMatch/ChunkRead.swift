// LOFI-FORK: reading a file in chunks without keeping them (see FORK.md). Foundation only.
import Foundation

/// On Apple's systems a chunk read from a FileHandle is also held by the thread's autorelease
/// pool, which a command-line program never empties. A score that reads the audio of every
/// teaching episode (76 GB on the Mac, some files several times) then keeps all of it in memory
/// until macOS kills it. Each read here has a pool of its own, so a chunk is freed as soon as its
/// caller lets it go. On Linux there is no such pool and the read is a plain read.
public enum ChunkRead {
  /// The next chunk of at most `count` bytes, or nil at the end of the file, when it cannot be read
  /// (on Linux a folder opens but cannot be read) or when `count` is not positive.
  public static func next(_ handle: FileHandle, upTo count: Int) -> Data? {
    guard count > 0 else { return nil }
    let chunk = pooled { try? handle.read(upToCount: count) }
    guard let chunk, !chunk.isEmpty else { return nil }
    return chunk
  }

  /// How often the score says how far it got: every this many episodes.
  public static let progressEvery = 100

  /// Whether the score says how far it got after `episodes` episodes.
  public static func saysProgress(after episodes: Int) -> Bool {
    episodes > 0 && episodes % progressEvery == 0
  }

  /// The line the score prints while it reads the episodes' audio, so a run that macOS stops shows
  /// how far it got and how much memory it used.
  public static func progressLine(episodes: Int, peakBytes: Int) -> String {
    let gigabytes = Double(peakBytes) / 1_073_741_824
    let shown = gigabytes >= 1 ? String(format: "%.1f", gigabytes) : String(format: "%.2f", gigabytes)
    return "Read the audio of \(episodes) episodes. The most memory used so far is \(shown) GB."
  }

  private static func pooled<T>(_ body: () -> T) -> T {
    #if canImport(ObjectiveC)
      return autoreleasepool(invoking: body)
    #else
      return body()
    #endif
  }
}
