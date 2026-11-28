import XCTest

@testable import PodcastAudioMatch

/// The map's file, its writer from an MP3 file, and following a stream that arrives in pieces.
final class EpisodeMapTests: XCTestCase {
  private let frame = 1152.0 / 44100.0
  private let sha = String(repeating: "b", count: 64)

  /// The Mac's copy: 800 frames of show, an ad of 300 frames, 1200 frames of show.
  private var macBytes: [UInt8] {
    Fake.id3(size: 200) + Marked.frames(0..<800) + Marked.frames(5000..<5300)
      + Marked.frames(800..<2000)
  }

  /// The phone's copy: another tag, the same show, an ad of 500 frames of its own in the place of
  /// the Mac's, and the same show again.
  private var phoneBytes: [UInt8] {
    Fake.id3(size: 900) + Marked.frames(0..<800) + Marked.frames(7000..<7500)
      + Marked.frames(800..<2000)
  }

  private var map: EpisodeMap {
    EpisodeMap.make(
      mp3: macBytes, feed: "https://show.test/rss", guid: "g1", sha256: sha,
      marks: [EpisodeMapMark(start: 800 * frame, end: 1100 * frame, kind: "ad")])!
  }

  func testTheWriterKeepsOneByteForEachFrameAndTheCopysFacts() {
    let made = map
    XCTAssertEqual(made.frames.count, 2300)
    XCTAssertEqual(made.frameSeconds, frame, accuracy: 1e-9)
    XCTAssertEqual(made.duration, 2300 * frame, accuracy: 1e-6)
    XCTAssertEqual(made.sha256, sha)
    XCTAssertEqual(made.guid, "g1")
    XCTAssertEqual(made.marks.count, 1)
  }

  func testBytesWithNoFramesMakeNoMap() {
    XCTAssertNil(
      EpisodeMap.make(
        mp3: [UInt8](repeating: 3, count: 5000), feed: "", guid: "", sha256: sha, marks: []))
  }

  func testFramesOfTwoLengthsInTimeMakeNoMap() {
    let mixed = Synth.frames(50, kbps: 128) + Synth.frames(50, kbps: 128, rate: 48000)
    XCTAssertFalse(MP3Frames.parse(mixed).frames.isEmpty)
    XCTAssertNil(EpisodeMap.make(mp3: mixed, feed: "", guid: "", sha256: sha, marks: []))
  }

  func testAMarkThatIsNoStretchIsLeftOutByTheWriter() {
    let made = EpisodeMap.make(
      mp3: macBytes, feed: "", guid: "", sha256: sha,
      marks: [
        EpisodeMapMark(start: 5, end: 5, kind: "ad"), EpisodeMapMark(start: .nan, end: 9, kind: "ad"),
        EpisodeMapMark(start: 1, end: 2, kind: "promo"),
      ])
    XCTAssertEqual(made?.marks, [EpisodeMapMark(start: 1, end: 2, kind: "promo")])
  }

  func testTheFileReadsBackAsItWasWritten() throws {
    let data = try XCTUnwrap(map.encoded())
    XCTAssertEqual(EpisodeMap(data: data), map)
    let text = try XCTUnwrap(String(data: data, encoding: .utf8))
    XCTAssertTrue(text.contains(#""version":1"#))
    XCTAssertTrue(text.contains(#""frames":""#))  // base64 text, not a list of numbers
  }

  func testADamagedFileAnotherVersionOrNoFramesIsNoMap() throws {
    XCTAssertNil(EpisodeMap(data: Data("not json".utf8)))
    var other = map
    other.version = 2
    XCTAssertNil(EpisodeMap(data: try XCTUnwrap(other.encoded())))
    var empty = map
    empty.frames = Data()
    XCTAssertNil(EpisodeMap(data: try XCTUnwrap(empty.encoded())))
    var still = map
    still.frameSeconds = 0
    XCTAssertNil(EpisodeMap(data: try XCTUnwrap(still.encoded())))
    XCTAssertNil(EpisodeMap(data: Data(count: EpisodeMap.maxBytes + 1)))
  }

  func testAnHourOfAudioIsAMapOfAbout185KB() throws {
    let frames = Int(3600 / frame)
    let hour = EpisodeMap(
      feed: "https://show.test/rss", guid: "g1", sha256: sha, duration: 3600, frameSeconds: frame,
      frames: Data((0..<frames).map { UInt8(truncatingIfNeeded: $0 &* 131) }),
      marks: (0..<8).map {
        EpisodeMapMark(start: Double($0) * 400, end: Double($0) * 400 + 60, kind: "ad")
      })
    let size = try XCTUnwrap(hour.encoded()).count
    XCTAssertGreaterThan(size, 180_000)
    XCTAssertLessThan(size, 190_000)
  }

  // MARK: A stream that arrives in pieces

  func testAStreamInPiecesGivesWhatTheWholeFileGives() {
    let bytes = phoneBytes
    var whole = EpisodeMapFollower(map: map)
    whole.feed(bytes)
    let expected = whole.carry(complete: true)
    XCTAssertTrue(expected.lined)
    XCTAssertEqual(expected.unmatched.count, 1)
    XCTAssertEqual(expected.unmatched[0].start, 800 * frame, accuracy: 1e-6)
    XCTAssertEqual(expected.unmatched[0].end, 1300 * frame, accuracy: 1e-6)
    XCTAssertTrue(expected.marks.isEmpty)  // the Mac's ad is not in this copy
    for size in [1000, 4096, 65_536] {
      var pieces = EpisodeMapFollower(map: map)
      var at = 0
      while at < bytes.count {
        pieces.feed(Array(bytes[at..<min(at + size, bytes.count)]))
        at += size
      }
      XCTAssertEqual(pieces.bytesFed, bytes.count)
      XCTAssertEqual(pieces.carry(complete: true), expected, "pieces of \(size)")
    }
  }

  func testTheAdIsKnownOnceMatchedAudioAfterItHasArrived() {
    let bytes = phoneBytes
    let audio = MP3Frames.parse(bytes).tagBytes
    var follower = EpisodeMapFollower(map: map)
    // The tag and the first 1000 frames: the show, then 200 frames of the phone's ad.
    follower.feed(Array(bytes[0..<audio + 1000 * 417]))
    var carry = follower.carry()
    XCTAssertTrue(carry.lined)
    XCTAssertTrue(carry.unmatched.isEmpty)  // nothing matched follows the ad yet
    // 3 seconds of the show after the ad (and a little more) are enough.
    follower.feed(Array(bytes[follower.bytesFed..<audio + 1450 * 417]))
    carry = follower.carry()
    XCTAssertEqual(carry.unmatched.count, 1)
    XCTAssertEqual(carry.unmatched[0].end, 1300 * frame, accuracy: 1e-6)
  }

  func testAStreamOfTheSameCopyCarriesTheMarkAsItArrives() {
    let audio = MP3Frames.parse(macBytes).tagBytes
    var follower = EpisodeMapFollower(map: map)
    follower.feed(Array(macBytes.prefix(audio + 1500 * 417)))
    let carry = follower.carry()
    XCTAssertEqual(carry.marks.count, 1)
    XCTAssertEqual(carry.marks[0].start, 800 * frame, accuracy: 1e-6)
    XCTAssertEqual(carry.marks[0].end, 1100 * frame, accuracy: 1e-6)
  }
}
