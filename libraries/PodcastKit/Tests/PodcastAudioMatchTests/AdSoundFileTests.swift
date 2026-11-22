import XCTest

@testable import PodcastAudioMatch

/// The taught sounds found in a whole file or in the first bytes of a stream.
final class AdSoundFileTests: XCTestCase {
  private var folder: URL!
  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("sound-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  /// The sound of the made-up frames `ids`, as the Mac would teach it.
  private func sound(_ ids: Range<Int>, sort: String = "sponsor", who: String = "Acme") -> AdSound {
    let frames = MP3Frames.parse(Marked.frames(ids)).frames
    return AdSound(
      sort: sort, who: who, frames: frames.count, seconds: frames.last.map { $0.start + $0.duration } ?? 0,
      seen: 2,
      anchors: stride(from: 0, to: frames.count, by: AdSoundLibrary.step).map {
        UInt32(truncatingIfNeeded: frames[$0].hash)
      })
  }

  /// An ID3 tag, 200 frames of other audio, the ad, 100 more frames.
  private var episode: [UInt8] {
    Fake.id3(size: 300) + Marked.frames(5000..<5200) + Marked.frames(0..<120)
      + Marked.frames(6000..<6100)
  }

  private func write(_ bytes: [UInt8], as name: String = "episode.mp3") throws -> URL {
    let url = folder.appendingPathComponent(name)
    try Data(bytes).write(to: url)
    return url
  }

  func testASoundInAFileIsFoundWithItsPlace() throws {
    let library = AdSoundLibrary(sounds: [sound(0..<120, who: "Acme")])
    let hits = AdSoundFile.hits(in: try write(episode), library: library)
    XCTAssertEqual(hits.count, 1)
    XCTAssertEqual(hits[0].who, "Acme")
    XCTAssertEqual(hits[0].sort, "sponsor")
    let frame = MP3Frames.parse(Marked.frames(0..<1)).frames[0].duration
    XCTAssertEqual(hits[0].start, 200 * frame, accuracy: 1e-6)
    XCTAssertEqual(hits[0].end - hits[0].start, library.sounds[0].seconds, accuracy: 1e-6)
  }

  func testTheSameHitsWhateverTheChunkSize() throws {
    let library = AdSoundLibrary(sounds: [sound(0..<120)])
    let url = try write(episode)
    let whole = AdSoundFile.hits(in: url, library: library)
    XCTAssertEqual(whole.count, 1)
    for size in [1, 7, 417, 1000, 1 << 20] {
      XCTAssertEqual(AdSoundFile.hits(in: url, library: library, chunkSize: size), whole, "\(size)")
      XCTAssertEqual(AdSoundFile.hits(in: Data(episode), library: library, chunkSize: size), whole, "\(size)")
    }
  }

  func testTheFirstBytesOfAStreamAreScannedToo() {
    let library = AdSoundLibrary(sounds: [sound(0..<120)])
    XCTAssertEqual(AdSoundFile.hits(in: Data(episode), library: library).count, 1)
    // Cut inside the sound: too few anchors yet, so nothing.
    let cut = Fake.id3(size: 300) + Marked.frames(5000..<5200) + Marked.frames(0..<20)
    XCTAssertEqual(AdSoundFile.hits(in: Data(cut), library: library), [])
  }

  func testTwoSoundsComeInOrder() throws {
    let bytes = Marked.frames(7000..<7050) + Marked.frames(300..<420) + Marked.frames(0..<120)
    let library = AdSoundLibrary(sounds: [sound(0..<120, who: "A"), sound(300..<420, who: "B")])
    let hits = AdSoundFile.hits(in: try write(bytes), library: library)
    XCTAssertEqual(hits.map(\.who), ["B", "A"])
  }

  func testNothingFromAMissingFileAnEmptyLibraryOrAFileThatIsNotMP3() throws {
    let library = AdSoundLibrary(sounds: [sound(0..<120)])
    XCTAssertEqual(AdSoundFile.hits(in: folder.appendingPathComponent("nope.mp3"), library: library), [])
    XCTAssertEqual(AdSoundFile.hits(in: try write(episode), library: AdSoundLibrary()), [])
    XCTAssertEqual(AdSoundFile.hits(in: Data(episode), library: AdSoundLibrary()), [])
    let text = try write(Array(String(repeating: "this is not audio. ", count: 5000).utf8), as: "a.txt")
    XCTAssertEqual(AdSoundFile.hits(in: text, library: library), [])
    XCTAssertEqual(AdSoundFile.hits(in: Data(), library: library), [])
    XCTAssertEqual(AdSoundFile.hits(in: folder, library: library), [], "a folder is not a file")
  }
}
