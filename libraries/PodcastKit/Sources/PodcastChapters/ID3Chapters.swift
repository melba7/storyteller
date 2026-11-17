// LOFI-FORK: reads the chapters of an MP3 file from its ID3v2 tag (see FORK.md).
//
// Written from the ID3v2.3 and v2.4 specs and the "ID3v2 Chapter Frame Addendum" (CHAP and
// CTOC frames). Pure Swift on bytes, so it tests on Linux. Bad or cut-off input gives fewer
// chapters, never a crash.
import Foundation

public enum ID3Chapters {
  /// The bytes to read from the start of a file to get the whole tag: the header's 10 bytes
  /// plus the size it states. Nil when the data is not the start of an ID3v2.3 or v2.4 tag.
  public static func tagLength(header: Data) -> Int? {
    let bytes = [UInt8](header.prefix(10))
    guard bytes.count == 10, ID3Bytes.isTag(bytes), let size = ID3Bytes.syncsafe(bytes, 6)
    else { return nil }
    return 10 + size
  }

  /// The chapters of the tag at the start of `data` (the tag may be cut off).
  public static func read(_ data: Data) -> [Chapter] {
    let bytes = [UInt8](data.prefix(32 * 1024 * 1024))
    guard bytes.count >= 10, ID3Bytes.isTag(bytes), let size = ID3Bytes.syncsafe(bytes, 6)
    else { return [] }
    let version = Int(bytes[3])
    let flags = bytes[5]
    var body = Array(bytes[10..<min(bytes.count, 10 + size)])
    let tagUnsync = flags & 0x80 != 0
    // v2.3 unsynchronises the whole tag; v2.4 does it frame by frame.
    if tagUnsync && version == 3 { body = ID3Bytes.undoUnsynchronisation(body) }
    if flags & 0x40 != 0 {  // an extended header: skip it
      let length =
        version == 4 ? ID3Bytes.syncsafe(body, 0) : ID3Bytes.be32(body, 0).map { $0 + 4 }
      guard let length, length <= body.count else { return [] }
      body = Array(body[length...])
    }
    var found: [(id: String, chapter: Chapter)] = []
    var topLevel: [String] = []
    for frame in ID3Bytes.frames(in: body, version: version, allUnsync: tagUnsync && version == 4)
    {
      if frame.id == "CHAP", let entry = chapter(frame.data, version: version, tagUnsync: tagUnsync && version == 4) {
        found.append(entry)
      } else if frame.id == "CTOC", let list = topLevelEntries(frame.data) {
        topLevel += list
      }
    }
    // A table of contents names the chapters to show; one that names none we have is ignored.
    let listed = found.filter { topLevel.contains($0.id) }
    return ChapterList.tidy((listed.isEmpty ? found : listed).map(\.chapter))
  }

  // MARK: Frames

  /// A CHAP frame: element id, start and end in milliseconds, 8 bytes of offsets, then frames.
  private static func chapter(
    _ data: [UInt8], version: Int, tagUnsync: Bool
  ) -> (id: String, chapter: Chapter)? {
    guard let (id, next) = ID3Bytes.latin1String(data, from: 0), data.count >= next + 16,
      let start = ID3Bytes.be32(data, next), let end = ID3Bytes.be32(data, next + 4)
    else { return nil }
    var chapter = Chapter(
      start: Double(start) / 1000, end: end == 0xFFFF_FFFF ? nil : Double(end) / 1000, title: "")
    let rest = Array(data[(next + 16)...])
    for frame in ID3Bytes.frames(in: rest, version: version, allUnsync: tagUnsync) {
      switch frame.id {
      case "TIT2": chapter.title = ID3Bytes.text(frame.data) ?? chapter.title
      case "APIC": chapter.imageData = picture(frame.data) ?? chapter.imageData
      case "WXXX": chapter.url = link(frame.data) ?? chapter.url
      default: break
      }
    }
    return (id, chapter)
  }

  /// A CTOC frame: element id, flags, entry count, then the entries' ids. Only the top level
  /// table of contents is wanted.
  private static func topLevelEntries(_ data: [UInt8]) -> [String]? {
    guard let (_, next) = ID3Bytes.latin1String(data, from: 0), data.count >= next + 2
    else { return nil }
    guard data[next] & 0x02 != 0 else { return nil }
    var ids: [String] = []
    var place = next + 2
    for _ in 0..<Int(data[next + 1]) {
      guard let (id, after) = ID3Bytes.latin1String(data, from: place) else { break }
      ids.append(id)
      place = after
    }
    return ids
  }

  /// An APIC frame: encoding, MIME type (text, ends with 0), picture type, description, bytes.
  private static func picture(_ data: [UInt8]) -> Data? {
    guard let encoding = data.first, let (_, afterMime) = ID3Bytes.latin1String(data, from: 1),
      data.count > afterMime + 1,
      let (_, afterDescription) = ID3Bytes.terminated(data, from: afterMime + 1, encoding: encoding),
      afterDescription < data.count
    else { return nil }
    return Data(data[afterDescription...])
  }

  /// A WXXX frame: encoding, description, then the address in Latin-1.
  private static func link(_ data: [UInt8]) -> String? {
    guard let encoding = data.first,
      let (_, after) = ID3Bytes.terminated(data, from: 1, encoding: encoding), after < data.count
    else { return nil }
    let text = String(decoding: data[after...].prefix { $0 != 0 }, as: UTF8.self)
    return text.isEmpty ? nil : text
  }
}
