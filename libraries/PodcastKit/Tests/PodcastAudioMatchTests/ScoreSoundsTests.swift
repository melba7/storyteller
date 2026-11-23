import XCTest

@testable import PodcastAudioMatch

/// What the scorecard's sound rows need from a file, in plain seconds: made MP3 bytes in a folder
/// of their own, one file for each episode.
final class ScoreSoundsTests: XCTestCase {
  private var folder: URL!
  private let now = 1_700_000_000.0
  /// One frame is 1152 / 44100 s long.
  private let frame = 1152.0 / 44100

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("score-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  private func write(_ bytes: [UInt8], as name: String) throws -> URL {
    let url = folder.appendingPathComponent(name)
    try Data(bytes).write(to: url)
    return url
  }

  /// An episode of made frames: ids are told apart by `Marked`, so equal ids are equal audio.
  private func episode(_ parts: Range<Int>...) -> [UInt8] {
    Fake.id3(size: 300) + parts.flatMap { Marked.frames($0) }
  }

  // MARK: The phone's own sounds

  func testASoundLearnedInOneFileIsFoundInAnotherWithinAThirdOfASecond() throws {
    // The ad is frames 500 to 1100 (15.7 s) of the first file and 1000 to 1600 of the second.
    let one = try write(episode(10_000..<10_500, 50_000..<50_600, 10_500..<11_000), as: "one.mp3")
    let two = try write(episode(20_000..<21_000, 50_000..<50_600, 21_000..<21_200), as: "two.mp3")
    var own = OwnAdSounds()
    let stretch = MarkedStretch(start: 500 * frame, end: 1100 * frame, sort: "sponsor", who: "")
    XCTAssertEqual(ScoreSounds.learnOwn(&own, show: "show", in: one, stretches: [stretch], now: now), 1)
    let found = ScoreSounds.ownSounds(in: two, own: own, show: "show")
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found.first?.start ?? 0, 1000 * frame, accuracy: 0.3)
    XCTAssertEqual(found.first?.end ?? 0, 1600 * frame, accuracy: 0.3)
    XCTAssertEqual(found.first?.sort, "sponsor")
  }

  func testASoundSeenOnceBelongsToItsShowAlone() throws {
    let one = try write(episode(10_000..<10_500, 50_000..<50_600, 10_500..<11_000), as: "one.mp3")
    let two = try write(episode(20_000..<21_000, 50_000..<50_600), as: "two.mp3")
    var own = OwnAdSounds()
    let stretch = MarkedStretch(start: 500 * frame, end: 1100 * frame, sort: "sponsor", who: "")
    ScoreSounds.learnOwn(&own, show: "show", in: one, stretches: [stretch], now: now)
    XCTAssertEqual(ScoreSounds.ownSounds(in: two, own: own, show: "another show"), [])
    XCTAssertEqual(ScoreSounds.ownSounds(in: two, own: OwnAdSounds(), show: "show"), [])
  }

  func testAMissingOrDamagedFileGivesNothingAndLearnsNothing() throws {
    let gone = folder.appendingPathComponent("nothing.mp3")
    let junk = try write([UInt8](repeating: 7, count: 5000), as: "junk.mp3")
    var own = OwnAdSounds()
    let stretch = MarkedStretch(start: 5, end: 30, sort: "sponsor", who: "")
    for url in [gone, junk] {
      XCTAssertEqual(ScoreSounds.learnOwn(&own, show: "show", in: url, stretches: [stretch], now: now), 0)
      XCTAssertEqual(ScoreSounds.ownSounds(in: url, own: own, show: "show"), [])
    }
    XCTAssertEqual(ScoreSounds.learnOwn(&own, show: "show", in: junk, stretches: [], now: now), 0)
    XCTAssertTrue(own.entries.isEmpty)
  }

  // MARK: Repeats across a show's episodes

  func testAPlugThatPlaysInTwoEpisodesIsAStretchOfTheSecondOne() throws {
    // 3000 frames (78 s) of other audio first, so the plug is not in the first minute.
    let plug = 70_000..<71_200  // 31 s
    let one = try write(episode(100_000..<103_000, plug, 104_000..<104_500), as: "one.mp3")
    let two = try write(episode(200_000..<204_000, plug, 205_000..<205_300), as: "two.mp3")
    let first = ScoreSounds.scanRepeats(in: one, older: [], episode: "e1", date: 1)
    XCTAssertEqual(first.spans, [])
    let print = try XCTUnwrap(first.print)
    XCTAssertEqual(print.episode, "e1")
    XCTAssertEqual(print.frames, 3000 + 1200 + 500)
    let second = ScoreSounds.scanRepeats(in: two, older: [print], episode: "e2", date: 2)
    XCTAssertEqual(second.spans.count, 1)
    XCTAssertEqual(second.spans.first?.start ?? 0, 4000 * frame, accuracy: 0.6)
    XCTAssertEqual(second.spans.first?.end ?? 0, 5200 * frame, accuracy: 0.6)
    XCTAssertEqual(second.print?.episode, "e2")
    XCTAssertEqual(second.print?.date, 2)
  }

  func testTheSameFileAgainIsNotARepeat() throws {
    let bytes = episode(100_000..<103_000, 70_000..<71_200, 104_000..<104_500)
    let one = try write(bytes, as: "one.mp3")
    let again = try write(bytes, as: "again.mp3")
    let print = try XCTUnwrap(ScoreSounds.scanRepeats(in: one, older: [], episode: "e1", date: 1).print)
    XCTAssertEqual(ScoreSounds.scanRepeats(in: again, older: [print], episode: "e2", date: 2).spans, [])
  }

  func testNoFileGivesNoPrintAndNoStretch() throws {
    let junk = try write([UInt8](repeating: 3, count: 4000), as: "junk.mp3")
    for url in [folder.appendingPathComponent("gone.mp3"), junk] {
      let scan = ScoreSounds.scanRepeats(in: url, older: [], episode: "e", date: 0)
      XCTAssertEqual(scan.spans, [])
      XCTAssertNil(scan.print)
    }
  }

  // MARK: Joints

  /// 1500 frames at 128 kbps, 500 at 64 and 1500 at 128: joints at 39.2 and 52.2 seconds.
  private func joinedFile() throws -> URL {
    try write(
      Fake.id3(size: 100) + Synth.frames(1500, kbps: 128) + Synth.frames(500, kbps: 64)
        + Synth.frames(1500, kbps: 128), as: "joined.mp3")
  }

  func testTheJointsOfAFileAreWhereTheEncodingChanges() throws {
    let joints = try XCTUnwrap(ScoreSounds.joints(in: joinedFile()))
    XCTAssertEqual(joints.times.count, 2)
    XCTAssertEqual(joints.times[0], 1500 * frame, accuracy: 0.05)
    XCTAssertEqual(joints.times[1], 2000 * frame, accuracy: 0.05)
    XCTAssertFalse(joints.steady)
    XCTAssertTrue(joints.usable)
  }

  func testAMissingFileHasNoJoints() {
    XCTAssertNil(ScoreSounds.joints(in: folder.appendingPathComponent("gone.mp3")))
  }

  func testBordersMoveOntoTheJointsAndStayInTheirOrder() throws {
    let joints = try XCTUnwrap(ScoreSounds.joints(in: joinedFile()))
    let joint = joints.times[0]
    // Given out of order: the answer comes back in the order given.
    let given = [SoundSpan(start: joint - 0.23, end: 70), SoundSpan(start: 20, end: joint - 0.28)]
    let moved = ScoreSounds.snap(given, joints: joints, steadyToo: false)
    // The second span's end would go to the joint, but that is after the next span's start.
    XCTAssertEqual(moved[1].start, 20)
    XCTAssertEqual(moved[1].end, joint - 0.28, accuracy: 1e-9)
    // The first span's start goes to the joint, which is not before the end of the span before.
    XCTAssertEqual(moved[0].start, joint, accuracy: 1e-9)
    XCTAssertEqual(moved[0].end, 70)
  }

  func testAnEndMovesWhenNothingStandsInItsWay() throws {
    let joints = try XCTUnwrap(ScoreSounds.joints(in: joinedFile()))
    let moved = ScoreSounds.snap([SoundSpan(start: 20, end: joints.times[0] - 1.5)], joints: joints, steadyToo: false)
    XCTAssertEqual(moved[0].end, joints.times[0], accuracy: 1e-9)
    XCTAssertEqual(moved[0].sort, "sponsor")
  }

  func testASteadyFileIsUsedOnlyWhenAskedAndBadInputIsLeftAlone() throws {
    var bytes = Fake.id3(size: 100) + Synth.frames(1000, kbps: 128)
    bytes += Synth.frame(kbps: 128, tag: "Xing") + Synth.frames(1000, kbps: 128)
    let joints = try XCTUnwrap(ScoreSounds.joints(in: write(bytes, as: "steady.mp3")))
    XCTAssertTrue(joints.steady)
    XCTAssertEqual(joints.times.count, 1)
    let span = SoundSpan(start: joints.times[0] - 1.0, end: 40)
    XCTAssertEqual(ScoreSounds.snap([span], joints: joints, steadyToo: false), [span])
    XCTAssertEqual(ScoreSounds.snap([span], joints: joints, steadyToo: true)[0].start, joints.times[0], accuracy: 1e-9)
    let bad = [SoundSpan(start: .nan, end: 5), SoundSpan(start: 9, end: 3)]
    XCTAssertEqual(ScoreSounds.snap(bad, joints: joints, steadyToo: true).count, 2)
    XCTAssertEqual(ScoreSounds.snap([], joints: joints, steadyToo: true), [])
  }
}
