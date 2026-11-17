import XCTest

@testable import PodcastChapters

/// Builds ID3 tags byte by byte, the way a podcast tool would write them.
struct TagBuilder {
  var version: UInt8 = 4
  var tagFlags: UInt8 = 0

  func syncsafe(_ value: Int) -> [UInt8] {
    [UInt8((value >> 21) & 0x7F), UInt8((value >> 14) & 0x7F), UInt8((value >> 7) & 0x7F), UInt8(value & 0x7F)]
  }

  func be32(_ value: UInt32) -> [UInt8] {
    [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
  }

  func frame(_ id: String, _ data: [UInt8], flags: UInt16 = 0) -> [UInt8] {
    let size = version == 4 ? syncsafe(data.count) : be32(UInt32(data.count))
    var out: [UInt8] = Array(id.utf8)
    out += size
    out += [UInt8(flags >> 8), UInt8(flags & 0xFF)]
    return out + data
  }

  func text(_ value: String, encoding: UInt8 = 3) -> [UInt8] {
    if encoding == 1 {
      var out: [UInt8] = [1, 0xFF, 0xFE]
      for unit in value.utf16 { out += [UInt8(unit & 0xFF), UInt8(unit >> 8)] }
      return out + [0, 0]
    }
    var out: [UInt8] = [encoding]
    out += Array(value.utf8)
    return out + [0]
  }

  func chap(_ id: String, start: UInt32, end: UInt32, subframes: [[UInt8]]) -> [UInt8] {
    var data: [UInt8] = Array(id.utf8)
    data.append(0)
    for value in [start, end, 0xFFFF_FFFF, 0xFFFF_FFFF] { data += be32(value) }
    for sub in subframes { data += sub }
    return frame("CHAP", data)
  }

  func tag(_ frames: [[UInt8]], padding: Int = 0) -> Data {
    var body: [UInt8] = []
    for frame in frames { body += frame }
    body += [UInt8](repeating: 0, count: padding)
    var out: [UInt8] = Array("ID3".utf8)
    out += [version, 0, tagFlags]
    out += syncsafe(body.count)
    return Data(out + body)
  }
}

final class ID3ChaptersTests: XCTestCase {
  func testReadsV24Chapters() {
    let b = TagBuilder()
    let data = b.tag(
      [
        b.frame("TIT2", b.text("Episode")),
        b.chap("c1", start: 0, end: 60_000, subframes: [b.frame("TIT2", b.text("Intro"))]),
        b.chap("c2", start: 60_000, end: 0xFFFF_FFFF, subframes: [b.frame("TIT2", b.text("Café ☕"))]),
      ], padding: 20)
    let chapters = ID3Chapters.read(data)
    XCTAssertEqual(chapters.map(\.title), ["Intro", "Café ☕"])
    XCTAssertEqual(chapters[0].end, 60)
    XCTAssertNil(chapters[1].end)
    XCTAssertEqual(chapters[1].start, 60)
  }

  func testReadsV23WithPlainFrameSizesAndUTF16() {
    var b = TagBuilder()
    b.version = 3
    let data = b.tag([
      b.chap("a", start: 1000, end: 5000, subframes: [b.frame("TIT2", b.text("Wörld", encoding: 1))])
    ])
    let chapters = ID3Chapters.read(data)
    XCTAssertEqual(chapters.map(\.title), ["Wörld"])
    // A size that only fits as a plain number (300 bytes) is not a sync-safe one.
    let long = String(repeating: "x", count: 300)
    let big = ID3Chapters.read(b.tag([b.chap("a", start: 0, end: 1, subframes: [b.frame("TIT2", b.text(long))])]))
    XCTAssertEqual(big.first?.title, long)
  }

  func testChapterPictureAndLink() {
    let b = TagBuilder()
    var picture: [UInt8] = [0]
    picture += Array("image/jpeg".utf8)
    picture += [0, 3]
    picture += Array("cover".utf8)
    picture += [0, 0xFF, 0xD8, 0xFF, 0xE0]
    var link: [UInt8] = [0]
    link += Array("site".utf8)
    link.append(0)
    link += Array("https://x.test/c1".utf8)
    let chapters = ID3Chapters.read(
      b.tag([
        b.chap("c", start: 0, end: 10, subframes: [
          b.frame("TIT2", b.text("One")), b.frame("APIC", picture), b.frame("WXXX", link),
        ])
      ]))
    XCTAssertEqual(chapters.first?.imageData, Data([0xFF, 0xD8, 0xFF, 0xE0]))
    XCTAssertEqual(chapters.first?.url, "https://x.test/c1")
  }

  func testTheTagsContentsListLimitsTheChapters() {
    let b = TagBuilder()
    var ctoc = [UInt8]("toc".utf8)
    ctoc += [0, 0x03, 1]
    ctoc += [UInt8]("c2".utf8) + [0]
    let chapters = ID3Chapters.read(
      b.tag([
        b.chap("c1", start: 0, end: 5, subframes: [b.frame("TIT2", b.text("Sub"))]),
        b.chap("c2", start: 5, end: 9, subframes: [b.frame("TIT2", b.text("Top"))]),
        b.frame("CTOC", ctoc),
      ]))
    XCTAssertEqual(chapters.map(\.title), ["Top"])
  }

  func testAContentsListNamingNothingWeHaveIsIgnored() {
    let b = TagBuilder()
    var ctoc = [UInt8]("toc".utf8)
    ctoc += [0, 0x03, 1]
    ctoc += [UInt8]("nested".utf8) + [0]
    let chapters = ID3Chapters.read(
      b.tag([b.chap("c1", start: 0, end: 5, subframes: []), b.frame("CTOC", ctoc)]))
    XCTAssertEqual(chapters.map(\.title), ["Chapter 1"])
  }

  func testUnsynchronisedV23TagIsDecoded() {
    var b = TagBuilder()
    b.version = 3
    b.tagFlags = 0x80
    // Start 0xFF 0xE0 ms = 65504 ms contains FF; as written, an extra 00 follows each FF.
    let plain = b.chap("c", start: 0x0000_FFE0, end: 0x0001_0000, subframes: [b.frame("TIT2", b.text("U"))])
    var written: [UInt8] = []
    for byte in plain { written.append(byte); if byte == 0xFF { written.append(0) } }
    var header: [UInt8] = Array("ID3".utf8)
    header += [3, 0, 0x80]
    header += b.syncsafe(written.count)
    let data = Data(header + written)
    let chapters = ID3Chapters.read(data)
    XCTAssertEqual(chapters.first?.start, 65.504)
    XCTAssertEqual(chapters.first?.title, "U")
  }

  func testUnsynchronisedV24FrameIsDecoded() {
    let b = TagBuilder()
    let plain = b.chap("c", start: 0x0000_FFE0, end: 0x0001_0000, subframes: [])
    // The CHAP frame's own data, unsynchronised, with the frame's unsync flag.
    var data: [UInt8] = []
    for byte in plain.dropFirst(10) { data.append(byte); if byte == 0xFF { data.append(0) } }
    let tag = b.tag([b.frame("CHAP", data, flags: 0x0002)])
    XCTAssertEqual(ID3Chapters.read(tag).first?.start, 65.504)
  }

  func testBadInputGivesNoChaptersAndNeverCrashes() {
    let b = TagBuilder()
    let good = [UInt8](b.tag([b.chap("c", start: 0, end: 10, subframes: [b.frame("TIT2", b.text("Hi"))])]))
    XCTAssertTrue(ID3Chapters.read(Data()).isEmpty)
    XCTAssertTrue(ID3Chapters.read(Data("not a tag at all".utf8)).isEmpty)
    // Every cut-off of a good tag, and every single byte damaged, must be survived.
    for length in 0..<good.count { _ = ID3Chapters.read(Data(good.prefix(length))) }
    for index in 0..<good.count {
      var damaged = good
      damaged[index] = 0xFF
      _ = ID3Chapters.read(Data(damaged))
    }
    XCTAssertEqual(ID3Chapters.read(Data(good)).count, 1)
  }

  func testTagLengthFromTheHeader() {
    let b = TagBuilder()
    let data = b.tag([b.frame("TIT2", b.text("Hello"))], padding: 5)
    XCTAssertEqual(ID3Chapters.tagLength(header: data.prefix(10)), data.count)
    XCTAssertNil(ID3Chapters.tagLength(header: Data("RIFF....WAVE".utf8)))
    XCTAssertNil(ID3Chapters.tagLength(header: Data("ID3".utf8)))
  }
}
