// LOFI-FORK: which shows' print files to delete so the phone keeps within its limits (see FORK.md).
import Foundation

/// The limits on all the print files together. The phone lists its print folder (a file for each
/// show, with its size and the day it was last used), asks which shows to drop and deletes their
/// files. The files are a cache: a show whose file is gone is scanned again from its next episode.
public enum PrintShelf {
  public static let maxShows = 60
  /// About 12 MB: 60 shows with three episodes of an hour each.
  public static let maxBytes = 12_000_000

  public struct Entry: Sendable, Equatable {
    public var show: String
    public var bytes: Int
    /// When the show's file was last written or used, in seconds since 1970.
    public var touched: Double

    public init(show: String, bytes: Int, touched: Double) {
      self.show = show
      self.bytes = bytes
      self.touched = touched
    }
  }

  /// The shows to drop, the least recently touched first. The most recently touched shows are kept
  /// while there are at most `maxShows` of them and they take at most `maxBytes`; the first show
  /// that does not fit and every older one go. A touched time that is not a number counts as the
  /// oldest, a size below 0 as 0.
  public static func evictions(_ entries: [Entry]) -> [String] {
    let ordered = entries.sorted {
      let (a, b) = (age($0), age($1))
      return a != b ? a > b : $0.show < $1.show
    }
    var kept = 0
    var bytes = 0
    var cut = false
    var gone: [String] = []
    for entry in ordered {
      let size = max(entry.bytes, 0)
      if !cut, kept < maxShows, size <= maxBytes - bytes {
        kept += 1
        bytes += size
      } else {
        cut = true
        gone.append(entry.show)
      }
    }
    return gone.reversed()
  }

  private static func age(_ entry: Entry) -> Double {
    entry.touched.isFinite ? entry.touched : -.greatestFiniteMagnitude
  }
}
