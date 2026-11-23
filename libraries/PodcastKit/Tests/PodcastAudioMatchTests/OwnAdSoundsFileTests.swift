import XCTest

@testable import PodcastAudioMatch

/// Reading the frames of the ad stretches of a downloaded file, and nothing else.
final class OwnAdSoundsFileTests: XCTestCase {
  private var folder: URL!
  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("own-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  private func write(_ bytes: [UInt8], as name: String = "episode.mp3") throws -> URL {
    let url = folder.appendingPathComponent(name)
    try Data(bytes).write(to: url)
    return url
  }

  /// A tag and `count` different frames (26 ms each), so the file is about `count / 38.3` seconds.
  private func file(_ count: Int) -> [UInt8] { Fake.id3(size: 300) + Marked.frames(0..<count) }

  /// What a whole read of the file gives for these stretches.
  private func expected(_ bytes: [UInt8], _ stretches: [(start: Double, end: Double)]) -> [MP3Frame] {
    MP3Frames.parse(bytes).frames.filter { frame in
      stretches.contains { frame.start < $0.end && frame.start + frame.duration > $0.start }
    }
  }

  private let stretches = [(start: 10.0, end: 20.0), (start: 40.0, end: 52.0)]

  func testOnlyTheFramesInsideTheStretchesAreKeptWhateverTheChunkSize() throws {
    let bytes = file(3000)
    let url = try write(bytes)
    let want = expected(bytes, stretches)
    XCTAssertEqual(want.count, 842, accuracy: 3)
    for size in [100, 417, 4096, 65_536, 1 << 20] {
      XCTAssertEqual(OwnAdSoundsFile.frames(in: url, stretches: stretches, chunkSize: size), want, "\(size)")
    }
    // Times and bytes are those of the whole file, not counted again from the stretch.
    XCTAssertEqual(want.first?.start ?? 0, 10, accuracy: 0.03)
  }

  func testOverlappingStretchesInAnyOrderKeepEachFrameOnce() throws {
    let bytes = file(3000)
    let url = try write(bytes)
    let tangled = [(start: 30.0, end: 40.0), (start: 15.0, end: 30.0), (start: 10.0, end: 20.0)]
    let merged = OwnAdSoundsFile.frames(in: url, stretches: tangled)
    XCTAssertEqual(merged, expected(bytes, [(start: 10, end: 40)]))
    XCTAssertEqual(Set(merged.map(\.offset)).count, merged.count)
  }

  func testTheFileIsReadInPiecesAndReadingStopsAfterTheLastStretch() throws {
    let bytes = file(3000)
    let url = try write(bytes)
    let pass = OwnAdSoundsFile.pass(in: url, stretches: stretches, chunkSize: 4096)
    XCTAssertEqual(pass.frames, expected(bytes, stretches))
    // Every piece is at most 4096 bytes, so the number of pieces says how much was read.
    XCTAssertGreaterThan(pass.chunks, 100)
    XCTAssertEqual(pass.chunks, (pass.bytes + 4095) / 4096)
    // Nothing is read after the first frame that starts past the last stretch (at 52 seconds).
    let after = MP3Frames.parse(bytes).frames.first { $0.start >= 52 }
    XCTAssertLessThanOrEqual(pass.bytes, (after?.offset ?? 0) + 418 + 4096)
    XCTAssertLessThan(pass.bytes, bytes.count)
    XCTAssertLessThanOrEqual(pass.peakPending, 2000)
  }

  func testWhatIsHeldDoesNotGrowWithTheLengthOfTheFile() throws {
    let smallFile = try write(file(3000), as: "small.mp3")
    let bigFile = try write(file(12_000), as: "big.mp3")
    let small = OwnAdSoundsFile.pass(in: smallFile, stretches: stretches, chunkSize: 4096)
    let big = OwnAdSoundsFile.pass(in: bigFile, stretches: stretches, chunkSize: 4096)
    XCTAssertEqual(big.frames, small.frames)
    XCTAssertEqual(big.chunks, small.chunks)
    XCTAssertLessThanOrEqual(big.peakPending, 2000)
    XCTAssertLessThan(big.frames.count, 12_000 / 10)
    // A stretch to the end of a file keeps reading to the end, in pieces all the same.
    let toTheEnd = [(start: 60.0, end: 600.0)]
    let whole = OwnAdSoundsFile.pass(in: smallFile, stretches: toTheEnd, chunkSize: 4096)
    XCTAssertEqual(whole.bytes, file(3000).count)
    XCTAssertEqual(whole.chunks, (whole.bytes + 4095) / 4096)
    XCTAssertEqual(whole.frames.count, 3000 - 2297, accuracy: 3)
  }

  func testNoMoreThanTheFrameLimitIsKept() {
    var keeper = StretchKeeper([(start: 0, end: 100)], mostFrames: 50)
    let kept = keeper.keep(MP3Frames.parse(Marked.frames(0..<500)).frames)
    XCTAssertEqual(kept.count, 50)
    XCTAssertTrue(keeper.done)
    XCTAssertEqual(OwnAdSoundsFile.mostFrames, 60_000)
  }

  func testAStretchBeforeTheStartOfTheFileIsCutAtTheStart() throws {
    let bytes = file(1000)
    let url = try write(bytes)
    let read = OwnAdSoundsFile.frames(in: url, stretches: [(start: -100, end: 10)])
    XCTAssertEqual(read, expected(bytes, [(start: 0, end: 10)]))
    XCTAssertEqual(read.first?.start, 0)
  }

  func testBadStretchesGiveNoFramesAndAreNotRead() throws {
    let url = try write(file(1000))
    let bad: [[(start: Double, end: Double)]] = [
      [], [(.nan, 10)], [(0, .nan)], [(.infinity, .infinity)], [(-.infinity, 20)], [(20, 10)],
      [(10, 10)], [(-5, 3)], [(0, 5)], [(0, 7.9)], [(0, 700)], [(-1e300, 1e300)], [(1e300, 1e301)],
    ]
    for stretches in bad {
      let pass = OwnAdSoundsFile.pass(in: url, stretches: stretches, chunkSize: 4096)
      XCTAssertTrue(pass.frames.isEmpty, "\(stretches)")
      XCTAssertEqual(pass.chunks, 0, "\(stretches)")
    }
    // A stretch beyond the end of the file is fine: there is nothing in it.
    XCTAssertTrue(OwnAdSoundsFile.frames(in: url, stretches: [(start: 10_000, end: 10_100)]).isEmpty)
  }

  func testAMissingEmptyOrOddFileGivesNoFrames() throws {
    let empty = try write([], as: "empty.mp3")
    let text = try write([UInt8](repeating: 0x20, count: 50_000), as: "text.mp3")
    let tagOnly = try write(Fake.id3(size: 3000), as: "tag.mp3")
    for url in [empty, text, tagOnly, folder.appendingPathComponent("missing.mp3"), folder!] {
      XCTAssertTrue(OwnAdSoundsFile.frames(in: url, stretches: stretches).isEmpty, url.lastPathComponent)
    }
    let url = try write(file(500), as: "short.mp3")
    XCTAssertTrue(OwnAdSoundsFile.frames(in: url, stretches: stretches, chunkSize: 0).isEmpty)
    XCTAssertTrue(OwnAdSoundsFile.frames(in: url, stretches: stretches, chunkSize: -5).isEmpty)
    let huge = OwnAdSoundsFile.frames(in: url, stretches: [(start: 0, end: 10)], chunkSize: .max)
    XCTAssertEqual(huge.count, 383, accuracy: 3)
  }

  // MARK: From a file to a print to a hit in another file

  func testAPrintLearnedFromAFileIsFoundInAnotherFile() throws {
    let ad = Marked.frames(0..<500)
    let one = Fake.id3(size: 300) + Marked.frames(5000..<5400) + ad + Marked.frames(6000..<6200)
    let two = Marked.frames(7000..<7100) + ad + Marked.frames(8000..<8300)
    let frame = 1152.0 / 44100
    let skipped = [(start: 400 * frame, end: 900 * frame)]
    let frames = OwnAdSoundsFile.frames(in: try write(one, as: "one.mp3"), stretches: skipped)
    XCTAssertLessThan(frames.count, 520)
    var own = OwnAdSounds()
    let stretch = MarkedStretch(start: skipped[0].start, end: skipped[0].end, sort: "sponsor", who: "Acme")
    XCTAssertEqual(own.learn(show: "show", frames: frames, stretches: [stretch], now: Own.now), 1)
    let hits = AdSoundFile.hits(in: try write(two, as: "two.mp3"), library: own.library)
    XCTAssertEqual(hits.count, 1)
    XCTAssertEqual(hits.first?.start ?? -1, 100 * frame, accuracy: 0.3)
    XCTAssertEqual(hits.first?.end ?? -1, 600 * frame, accuracy: 0.3)
  }
}
