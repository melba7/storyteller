import XCTest

@testable import PodcastAudioMatch

final class JointFinderTests: XCTestCase {
  private typealias Run = JointFrames.Run

  private func joints(_ frames: [MP3Frame]) -> Joints {
    var finder = JointFinder()
    finder.feed(frames)
    return finder.joints
  }

  private func parse(_ frames: [MP3Frame]) -> MP3Parse {
    MP3Parse(frames: frames, tagBytes: 0, skippedBytes: 0, bitrate: frames.first?.bitrate ?? 0)
  }

  private func assertTimes(
    _ found: [Double], _ wanted: [Double], file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(found.count, wanted.count, "\(found)", file: file, line: line)
    for (one, other) in zip(found, wanted) {
      XCTAssertEqual(one, other, accuracy: 1e-9, file: file, line: line)
    }
  }

  func testAChangeOfBitrateThatHoldsIsAJointAtItsFirstFrame() {
    let found = joints(JointFrames.spliced())
    assertTimes(found.times, [JointFrames.time(300), JointFrames.time(1300)])
    XCTAssertEqual(found.seconds, JointFrames.time(4300), accuracy: 1e-9)
    XCTAssertFalse(found.steady)
    XCTAssertTrue(found.usable)
  }

  func testAChangeThatHoldsForTheSharedNumberOfFramesIsAJointAndOneFrameLessIsNot() {
    let few = SeekDrift.seamFrames - 1
    XCTAssertTrue(
      joints(JointFrames.frames([Run(count: 300), Run(count: few, kbps: 64), Run(count: 300)]))
        .times.isEmpty)
    let enough = joints(
      JointFrames.frames([
        Run(count: 300), Run(count: SeekDrift.seamFrames, kbps: 64), Run(count: 300),
      ]))
    assertTimes(enough.times, [JointFrames.time(300), JointFrames.time(300 + SeekDrift.seamFrames)])
  }

  func testAChangeOfSampleRateOrChannelsIsAJoint() {
    let found = joints(
      JointFrames.frames([
        Run(count: 100), Run(count: 100, rate: 48000), Run(count: 100, rate: 48000, mono: true),
      ]))
    // The second run's frames are shorter: 1,152 samples at 48 kHz.
    assertTimes(found.times, [JointFrames.time(100), JointFrames.time(100) + 100 * 1152.0 / 48000])
  }

  func testAnInfoTagIsAJointOnlyAfterTheFirstFrame() {
    let found = joints(JointFrames.frames([Run(count: 200, tag: true), Run(count: 100, tag: true)]))
    assertTimes(found.times, [JointFrames.time(200)])
  }

  func testAResetOfTheReservoirIsAJointOnlyAfterTheSharedNumberOfFrames() {
    let after = SeekDrift.resetAfter
    let enough = JointFrames.frames([Run(count: after), Run(count: 1, pointer: 0), Run(count: 20)])
    assertTimes(joints(enough).times, [JointFrames.time(after)])
    let few = JointFrames.frames([Run(count: after - 1), Run(count: 1, pointer: 0), Run(count: 20)])
    XCTAssertTrue(joints(few).times.isEmpty)
    // Frames whose pointer cannot be read never reach back, so no reset follows them.
    let unknown = JointFrames.frames([
      Run(count: after, pointer: nil), Run(count: 1, pointer: 0), Run(count: 20),
    ])
    XCTAssertTrue(joints(unknown).times.isEmpty)
  }

  func testSeveralSignsAtOneFrameAreOneJoint() {
    // A new file that is joined in has its own Info tag and starts with an empty reservoir.
    let made = JointFrames.frames([
      Run(count: 300), Run(count: 100, kbps: 64, tag: true, pointer: 0),
    ])
    XCTAssertGreaterThan(SeekDrift.report(parse(made)).seams.count, 1)
    assertTimes(joints(made).times, [JointFrames.time(300)])
  }

  func testAnySplitOfTheFramesGivesTheSameJoints() {
    let made = JointFrames.spliced()
    let whole = joints(made)
    var single = JointFinder()
    for frame in made { single.feed(frame) }
    XCTAssertEqual(single.joints, whole)
    var pieces = JointFinder()
    for start in stride(from: 0, to: made.count, by: 7) {
      pieces.feed(Array(made[start..<min(start + 7, made.count)]))
    }
    XCTAssertEqual(pieces.joints, whole)
  }

  func testTheJointsAreTheOnesSeekDriftFindsOnManyMadeFiles() {
    var dice = JointFrames.Dice(state: 7)
    var total = 0  // the files must hold joints, or equal empty lists would prove nothing
    for _ in 0..<80 {
      let runs = (0..<(2 + dice.next(10))).map { _ in
        Run(
          count: [1, 3, 30, 49, 50, 51, 120, 300][dice.next(8)],
          kbps: [128, 128, 64, 96][dice.next(4)], rate: [44100, 44100, 48000][dice.next(3)],
          mono: dice.next(5) == 0, tag: dice.next(6) == 0, pointer: [nil, 0, 1, 2][dice.next(4)])
      }
      let made = JointFrames.frames(runs)
      var finder = JointFinder()
      var at = 0
      while at < made.count {
        let size = 1 + dice.next(200)
        finder.feed(Array(made[at..<min(at + size, made.count)]))
        at += size
      }
      let wanted = JointFrames.expected(parse(made))
      assertTimes(finder.joints.times, wanted)
      XCTAssertEqual(finder.joints.steady, SeekDrift.report(parse(made)).steady)
      total += wanted.count
    }
    XCTAssertGreaterThan(total, 200)
  }

  func testSteadyIsWhatSeekDriftSays() {
    let files: [[MP3Frame]] = [
      JointFrames.frames([Run(count: 4000)]),
      JointFrames.frames([Run(count: 990), Run(count: 10, kbps: 64)]),
      JointFrames.frames([Run(count: 980), Run(count: 20, kbps: 64)]),
      JointFrames.spliced(),
      [],
    ]
    for made in files {
      XCTAssertEqual(joints(made).steady, SeekDrift.report(parse(made)).steady, "\(made.count)")
    }
    XCTAssertTrue(joints(files[0]).steady)
    XCTAssertFalse(joints(files[2]).steady)
  }

  func testNoFramesGiveNoJointsAndAFileThatIsNotUsed() {
    let found = joints([])
    XCTAssertTrue(found.times.isEmpty)
    XCTAssertEqual(found.seconds, 0)
    XCTAssertFalse(found.usable)
  }

  func testWhatIsKeptStaysWithinALimitHoweverManyJointsThereAre() {
    var finder = JointFinder()
    let made = JointFrames.busy(joints: JointFinder.keepLimit + 100)
    for start in stride(from: 0, to: made.count, by: 5000) {
      finder.feed(Array(made[start..<min(start + 5000, made.count)]))
    }
    let found = finder.joints
    XCTAssertLessThanOrEqual(found.times.count, JointFinder.keepLimit)
    XCTAssertTrue(found.overflowed)
    XCTAssertFalse(found.usable)
    XCTAssertEqual(found.seconds, made.last.map { $0.start + $0.duration })
  }

  func testFramesWithTimesThatCannotBeUsedAreLeftOutAndNothingTraps() {
    var made = JointFrames.spliced()
    for index in made.indices where index >= 1300 {
      made[index].start = index.isMultiple(of: 2) ? .nan : -.infinity
    }
    let found = joints(made)
    XCTAssertTrue(found.times.allSatisfy { $0.isFinite && $0 >= 0 })
    XCTAssertTrue(found.seconds.isFinite)
    XCTAssertEqual(found.times.first ?? -1, JointFrames.time(300), accuracy: 1e-9)
  }
}
