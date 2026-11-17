// LOFI-FORK: the byte-level parts of the ID3v2 reader (see FORK.md).
import Foundation

enum ID3Bytes {
  struct Frame {
    var id: String
    var data: [UInt8]
  }

  static func isTag(_ bytes: [UInt8]) -> Bool {
    bytes.count >= 10 && bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33
      && (bytes[3] == 3 || bytes[3] == 4) && bytes[4] != 0xFF
  }

  /// Four bytes of 7 bits each (the high bit must be 0), or nil.
  static func syncsafe(_ bytes: [UInt8], _ at: Int) -> Int? {
    guard at >= 0, bytes.count >= at + 4 else { return nil }
    var value = 0
    for byte in bytes[at..<at + 4] {
      if byte & 0x80 != 0 { return nil }
      value = value << 7 | Int(byte)
    }
    return value
  }

  static func be32(_ bytes: [UInt8], _ at: Int) -> Int? {
    guard at >= 0, bytes.count >= at + 4 else { return nil }
    return bytes[at..<at + 4].reduce(0) { $0 << 8 | Int($1) }
  }

  /// Turns every FF 00 back into FF.
  static func undoUnsynchronisation(_ bytes: [UInt8]) -> [UInt8] {
    var out: [UInt8] = []
    out.reserveCapacity(bytes.count)
    var index = 0
    while index < bytes.count {
      out.append(bytes[index])
      if bytes[index] == 0xFF, index + 1 < bytes.count, bytes[index + 1] == 0 { index += 1 }
      index += 1
    }
    return out
  }

  /// The frames in a block of bytes, until padding or damage. Frames that are compressed or
  /// encrypted are left out. `allUnsync` is v2.4's tag-wide flag.
  static func frames(in bytes: [UInt8], version: Int, allUnsync: Bool) -> [Frame] {
    var frames: [Frame] = []
    var place = 0
    while place + 10 <= bytes.count, bytes[place] != 0 {
      let idBytes = bytes[place..<place + 4]
      guard idBytes.allSatisfy({ ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x30 && $0 <= 0x39) })
      else { break }
      let id = String(decoding: idBytes, as: UTF8.self)
      guard let size = version == 4 ? syncsafe(bytes, place + 4) : be32(bytes, place + 4),
        place + 10 + size <= bytes.count
      else { break }
      let flags = (UInt16(bytes[place + 8]) << 8) | UInt16(bytes[place + 9])
      var data = Array(bytes[place + 10..<place + 10 + size])
      place += 10 + size
      var unsync = allUnsync
      if version == 4 {
        if flags & 0x000C != 0 { continue }  // compressed or encrypted
        if flags & 0x0002 != 0 { unsync = true }
        if flags & 0x0001 != 0 {  // a data length indicator in front
          guard data.count >= 4 else { continue }
          data.removeFirst(4)
        }
      } else if flags & 0x00C0 != 0 {
        continue
      }
      if unsync && version == 4 { data = undoUnsynchronisation(data) }
      frames.append(Frame(id: id, data: data))
    }
    return frames
  }

  /// Latin-1 text up to a 0 byte, and where the next field starts. Without a 0 the rest is the text.
  static func latin1String(_ bytes: [UInt8], from start: Int) -> (String, Int)? {
    guard start >= 0, start <= bytes.count else { return nil }
    let end = bytes[start...].firstIndex(of: 0) ?? bytes.count
    return (String(bytes[start..<end].map { Character(UnicodeScalar($0)) }), min(end + 1, bytes.count))
  }

  /// The end of a text field in the given encoding (0 Latin-1, 1 UTF-16 with BOM, 2 UTF-16BE,
  /// 3 UTF-8), and where the next field starts.
  static func terminated(_ bytes: [UInt8], from start: Int, encoding: UInt8) -> (Int, Int)? {
    guard start >= 0, start <= bytes.count else { return nil }
    if encoding == 1 || encoding == 2 {
      var index = start
      while index + 1 < bytes.count {
        if bytes[index] == 0 && bytes[index + 1] == 0 { return (index, index + 2) }
        index += 2
      }
      return nil
    }
    guard let end = bytes[start...].firstIndex(of: 0) else { return nil }
    return (end, end + 1)
  }

  /// The text of a text frame (an encoding byte, then the text). Nil when it is empty.
  static func text(_ data: [UInt8]) -> String? {
    guard let encoding = data.first, data.count > 1 else { return nil }
    var body = Array(data.dropFirst())
    // Cut at the terminator: only the first string of the frame is the title.
    if let (end, _) = terminated(body, from: 0, encoding: encoding) { body = Array(body[..<end]) }
    let text = decode(body, encoding: encoding).trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }

  static func decode(_ bytes: [UInt8], encoding: UInt8) -> String {
    switch encoding {
    case 1, 2:
      var body = bytes
      var bigEndian = encoding == 2
      if encoding == 1, body.count >= 2 {
        if body[0] == 0xFE, body[1] == 0xFF { bigEndian = true; body.removeFirst(2) }
        else if body[0] == 0xFF, body[1] == 0xFE { body.removeFirst(2) }
      }
      var units: [UInt16] = []
      var index = 0
      while index + 1 < body.count {
        let pair = (UInt16(body[index]), UInt16(body[index + 1]))
        units.append(bigEndian ? pair.0 << 8 | pair.1 : pair.1 << 8 | pair.0)
        index += 2
      }
      return String(decoding: units, as: UTF16.self)
    case 3: return String(decoding: bytes, as: UTF8.self)
    default: return String(bytes.map { Character(UnicodeScalar($0)) })
    }
  }
}
