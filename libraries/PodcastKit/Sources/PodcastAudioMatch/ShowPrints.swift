// LOFI-FORK: the prints of one show's newest episodes, and the file they are kept in (see FORK.md).
import Foundation

/// The prints of the newest `maxEpisodes` episodes of one show, newest first. The phone keeps one
/// file for each show under Library/Caches, which iOS may clear: a missing file is an empty value.
public struct ShowPrints: Sendable, Equatable {
  public static let currentVersion = 1
  public static let maxEpisodes = 3
  /// The most bytes a file holds, and the most the phone reads: three prints at their largest
  /// (400 KB each) and their ids.
  public static let maxBytes = 1_500_000
  private static let magic = Array("EPRT".utf8)

  /// Newest date first.
  public private(set) var prints: [EpisodePrint] = []

  public init() {}

  /// A show of these prints, in the order they would be added: only the newest are kept.
  public init(prints: [EpisodePrint]) {
    self = prints.reduce(ShowPrints()) { $0.adding($1) }
  }

  /// This show with `print` added, and only the newest `maxEpisodes` kept. A print of an episode
  /// that is there already replaces it; one that is older than all that are kept is not kept; one
  /// with no id, no anchors or too many (`EpisodePrint.storable`) is left out. A print whose date
  /// is the same as one already there goes before it, so among equal dates the one added last
  /// is first, and the one added first is the first to go.
  public func adding(_ print: EpisodePrint) -> ShowPrints {
    guard print.storable else { return self }
    var all = prints.filter { $0.episode != print.episode }
    all.insert(print, at: all.firstIndex { $0.date <= print.date } ?? all.count)
    var shown = ShowPrints()
    shown.prints = Array(all.prefix(Self.maxEpisodes))
    return shown
  }

  /// The prints to scan the episode `episode` against: all but its own.
  public func prints(excluding episode: String) -> [EpisodePrint] {
    prints.filter { $0.episode != episode }
  }

  // MARK: the file

  // The file is binary, little endian: "EPRT", the version and the number of episodes (4 bytes each);
  // then for each episode its id (2 bytes of length and the UTF-8), date and seconds (8 bytes each,
  // as Double), frames and number of anchors (4 bytes each) and the anchors (4 bytes each); then a
  // checksum of everything before it (4 bytes).

  public func data() -> Data {
    var bytes = Self.magic
    bytes.put(UInt32(Self.currentVersion))
    bytes.put(UInt32(prints.count))
    for print in prints {
      let id = Array(print.episode.utf8)
      bytes.put(UInt16(id.count))
      bytes += id
      bytes.put(print.date.bitPattern)
      bytes.put(print.seconds.bitPattern)
      bytes.put(UInt32(print.frames))
      bytes.put(UInt32(print.anchors.count))
      for anchor in print.anchors { bytes.put(anchor) }
    }
    bytes.put(Self.checksum(bytes))
    return Data(bytes)
  }

  /// Reads a file. A file that is damaged, cut, of another version or too large reads as empty,
  /// all of it: prints that can be made again are not worth trusting half of.
  public init(data: Data) {
    self.init()
    guard data.count <= Self.maxBytes, data.count >= Self.magic.count + 12 else { return }
    let bytes = [UInt8](data)
    let body = Array(bytes.dropLast(4))
    var reader = ByteReader(bytes: body)
    guard bytes.suffix(4).elementsEqual(Self.checksumBytes(body)),
      reader.take(4) == Self.magic, reader.number(UInt32.self) == UInt32(Self.currentVersion),
      let count = reader.number(UInt32.self), count <= UInt32(Self.maxEpisodes)
    else { return }
    var read: [EpisodePrint] = []
    for _ in 0..<count {
      guard let print = Self.readPrint(from: &reader), print.storable,
        !read.contains(where: { $0.episode == print.episode })
      else { return }
      read.append(print)
    }
    guard reader.atEnd else { return }
    // The file lists the newest first and a later print wins a tie, so add them oldest first.
    self = ShowPrints(prints: read.reversed())
  }

  private static func readPrint(from reader: inout ByteReader) -> EpisodePrint? {
    guard let idLength = reader.number(UInt16.self), idLength > 0, idLength <= EpisodePrint.maxIdBytes,
      let id = reader.take(Int(idLength)).flatMap({ String(bytes: $0, encoding: .utf8) }),
      let date = reader.number(UInt64.self).map(Double.init(bitPattern:)), date.isFinite,
      let seconds = reader.number(UInt64.self).map(Double.init(bitPattern:)), seconds.isFinite,
      seconds >= 0, let frames = reader.number(UInt32.self),
      let count = reader.number(UInt32.self), count <= UInt32(EpisodePrint.maxAnchors),
      reader.left >= 4 * Int(count)
    else { return nil }
    var anchors: [UInt32] = []
    anchors.reserveCapacity(Int(count))
    for _ in 0..<count {
      guard let anchor = reader.number(UInt32.self) else { return nil }
      anchors.append(anchor)
    }
    return EpisodePrint(
      episode: id, date: date, frames: Int(frames), seconds: seconds, anchors: anchors)
  }

  /// A 32-bit FNV-1a checksum: any change of one byte changes it.
  static func checksum(_ bytes: [UInt8]) -> UInt32 {
    bytes.reduce(2_166_136_261 as UInt32) { ($0 ^ UInt32($1)) &* 16_777_619 }
  }

  private static func checksumBytes(_ bytes: [UInt8]) -> [UInt8] {
    var out: [UInt8] = []
    out.put(checksum(bytes))
    return out
  }
}

/// Reads numbers and bytes from an array without ever reading past its end.
private struct ByteReader {
  let bytes: [UInt8]
  var at = 0

  var left: Int { bytes.count - at }
  var atEnd: Bool { at == bytes.count }

  mutating func take(_ count: Int) -> [UInt8]? {
    guard count >= 0, count <= left else { return nil }
    defer { at += count }
    return Array(bytes[at..<at + count])
  }

  mutating func number<T: FixedWidthInteger>(_ type: T.Type) -> T? {
    guard let taken = take(MemoryLayout<T>.size) else { return nil }
    return taken.enumerated().reduce(0 as T) { $0 | T(truncatingIfNeeded: $1.element) << (8 * $1.offset) }
  }
}

extension Array where Element == UInt8 {
  /// Appends `number` as little endian bytes.
  fileprivate mutating func put<T: FixedWidthInteger>(_ number: T) {
    for place in 0..<MemoryLayout<T>.size { append(UInt8(truncatingIfNeeded: number >> (8 * place))) }
  }
}
