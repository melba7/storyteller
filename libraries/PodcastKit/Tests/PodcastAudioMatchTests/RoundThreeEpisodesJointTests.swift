import XCTest

@testable import PodcastAudioMatch

/// The joints of the whole-round test: in the made file of episode three, ACME is spliced in at
/// 64 kbps between two stretches of the show at 128 kbps, so the audio really changes at its
/// first frame and at the first frame of the show after it.
final class RoundThreeEpisodesJointTests: RoundSoundCase {
  private let episode = RoundSound.three

  private func joints() throws -> Joints {
    try XCTUnwrap(ScoreSounds.joints(in: write(episode, as: "three.mp3")))
  }

  /// The times at which the bitrate really changes, read from the frames themselves.
  private func changes() -> [Double] {
    let frames = MP3Frames.parse(episode.bytes).frames
    return zip(frames, frames.dropFirst()).filter { $0.bitrate != $1.bitrate }.map { $1.start }
  }

  func testAJointIsTheFrameWhereTheAudioReallyChanges() throws {
    let real = changes()
    XCTAssertEqual(real.count, 6, "ACME, BETA and DELTA, in and out")
    XCTAssertEqual(real[0], episode.start("acme"), accuracy: 1e-9)
    XCTAssertEqual(real[1], episode.end("acme"), accuracy: 1e-9)
    XCTAssertEqual(real[4], episode.start("delta"), accuracy: 1e-9)
    let found = try joints().times
    XCTAssertEqual(found.count, real.count, "\(found)")
    for (joint, change) in zip(found, real) { XCTAssertEqual(joint, change, accuracy: 1e-9) }
    // The same joints when the file arrives in small pieces, as a stream's bytes do.
    var reader = MP3FrameReader()
    var finder = JointFinder()
    for from in stride(from: 0, to: episode.bytes.count, by: 1000) {
      finder.feed(reader.feed(Array(episode.bytes[from..<min(from + 1000, episode.bytes.count)])))
    }
    XCTAssertEqual(finder.joints.times, found)
    XCTAssertFalse(try joints().steady)
    XCTAssertTrue(try joints().usable)
  }

  func testAStartMovesOntoTheJointFromThreeSecondsAfterItOrOneBeforeIt() throws {
    let joints = try joints()
    let joint = episode.start("acme")
    let end = episode.end("acme") - 5
    for offset in [3.0, 2.9, 0.4, 0, -0.9, -1.0] {
      let moved = JointSnap.snap(start: joint + offset, end: end, joints: joints)
      XCTAssertEqual(moved.start, joint, accuracy: 1e-9, "a start \(offset) s after the joint")
      XCTAssertEqual(moved.end, end, "the end is not near a joint")
    }
  }

  func testAnEndMovesOntoTheJointFromTwoSecondsAfterItOrFourBeforeIt() throws {
    let joints = try joints()
    let joint = episode.end("acme")
    let start = episode.start("acme") + 5
    for offset in [2.0, 1.9, 0, -3.9, -4.0] {
      let moved = JointSnap.snap(start: start, end: joint + offset, joints: joints)
      XCTAssertEqual(moved.end, joint, accuracy: 1e-9, "an end \(offset) s after the joint")
      XCTAssertEqual(moved.start, start, "the start is not near a joint")
    }
  }

  func testAJointFartherThanTheBoundMovesNothing() throws {
    let joints = try joints()
    let first = episode.start("acme")
    let last = episode.end("acme")
    for offset in [3.05, 3.5, -1.05, -2.0] {
      let moved = JointSnap.snap(start: first + offset, end: last - 5, joints: joints)
      XCTAssertEqual(moved.start, first + offset, "a start \(offset) s after the joint stays")
    }
    for offset in [2.05, 3.0, -4.05, -6.0] {
      let moved = JointSnap.snap(start: first + 5, end: last + offset, joints: joints)
      XCTAssertEqual(moved.end, last + offset, "an end \(offset) s after the joint stays")
    }
  }

  func testTheSnapOfAFilesStretchesKeepsTheBoundsOnBothBorders() throws {
    // `ScoreSounds.snap` is what the phone's pass calls: both borders of a stretch at once.
    let joints = try joints()
    let near = SoundSpan(start: episode.start("acme") + 2.5, end: episode.end("acme") - 3.5)
    let moved = ScoreSounds.snap([near], joints: joints, steadyToo: false)
    XCTAssertEqual(moved[0].start, episode.start("acme"), accuracy: 1e-9)
    XCTAssertEqual(moved[0].end, episode.end("acme"), accuracy: 1e-9)
    let far = SoundSpan(start: episode.start("acme") + 3.5, end: episode.end("acme") - 4.5)
    XCTAssertEqual(ScoreSounds.snap([far], joints: joints, steadyToo: false), [far], "both borders are past their bounds")
  }
}
