import XCTest

@testable import PodcastAudioMatch

/// Made-up copies of one episode: each frame is one byte, and a "show" is a run of bytes that is
/// the same in every copy while each "ad" has bytes of its own.
private enum Copy {
  static let frame = 1152.0 / 44100.0

  /// `count` bytes that depend on `seed` only, and look random.
  static func bytes(_ seed: UInt64, _ count: Int) -> [UInt8] {
    var state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 1
    return (0..<count).map { _ in
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return UInt8(truncatingIfNeeded: state >> 33)
    }
  }

  /// Frames for `seconds` of audio.
  static func audio(_ seed: UInt64, seconds: Double) -> [UInt8] {
    bytes(seed, Int((seconds / frame).rounded()))
  }

  static func map(_ parts: [[UInt8]], marks: [EpisodeMapMark]) -> EpisodeMap {
    let frames = parts.flatMap { $0 }
    return EpisodeMap(
      feed: "https://show.test/rss", guid: "g1", sha256: String(repeating: "a", count: 64),
      duration: Double(frames.count) * frame, frameSeconds: frame, frames: Data(frames),
      marks: marks)
  }

  static func heard(_ parts: [[UInt8]], from: Double = 0) -> HeardFrames {
    HeardFrames(hashes: parts.flatMap { $0 }, frameSeconds: frame, from: from)
  }

  static func seconds(_ parts: [UInt8]...) -> Double {
    Double(parts.reduce(0) { $0 + $1.count }) * frame
  }
}

final class EpisodeMapAlignerTests: XCTestCase {
  private let intro = Copy.audio(1, seconds: 60)
  private let middle = Copy.audio(2, seconds: 120)
  private let outro = Copy.audio(3, seconds: 90)
  private let macAd = Copy.audio(10, seconds: 30)

  /// The Mac's copy: intro, an ad the Mac marked (60 to 90 s), the middle, the outro.
  private var map: EpisodeMap {
    Copy.map(
      [intro, macAd, middle, outro],
      marks: [EpisodeMapMark(start: Copy.seconds(intro), end: Copy.seconds(intro, macAd), kind: "ad")])
  }

  private func assertStretch(
    _ got: (start: Double, end: Double), _ start: Double, _ end: Double,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(got.start, start, accuracy: 0.03, file: file, line: line)
    XCTAssertEqual(got.end, end, accuracy: 0.03, file: file, line: line)
  }

  func testIdenticalCopiesCarryEveryMarkAtItsOwnTimes() {
    let carry = EpisodeMapAligner(map: map).carry(
      Copy.heard([intro, macAd, middle, outro]), complete: true)
    XCTAssertTrue(carry.lined)
    XCTAssertEqual(carry.marks.count, 1)
    assertStretch((carry.marks[0].start, carry.marks[0].end), 60, 90)
    XCTAssertEqual(carry.marks[0].kind, "ad")
    XCTAssertEqual(carry.marks[0].from, map.marks[0].start)
    XCTAssertTrue(carry.unmatched.isEmpty)
  }

  func testAShortMarkIsKeptWhenTheCopiesAreTheSame() {
    var same = map
    same.marks = [EpisodeMapMark(start: 200, end: 203, kind: "promo")]
    let carry = EpisodeMapAligner(map: same).carry(Copy.heard([intro, macAd, middle, outro]))
    XCTAssertEqual(carry.marks.count, 1)
    assertStretch((carry.marks[0].start, carry.marks[0].end), 200, 203)
  }

  func testAnAdOnlyThePhoneHasIsAnUnmatchedStretchAndLaterMarksMove() {
    let phoneAd = Copy.audio(20, seconds: 25)
    var later = map
    later.marks.append(EpisodeMapMark(start: 250, end: 270, kind: "promo"))
    let carry = EpisodeMapAligner(map: later).carry(
      Copy.heard([intro, macAd, Copy.audio(2, seconds: 120).prefix(2000).map { $0 }, phoneAd,
        Array(middle.dropFirst(2000)), outro]))
    XCTAssertTrue(carry.lined)
    let inserted = 60 + 30 + 2000 * Copy.frame
    XCTAssertEqual(carry.unmatched.count, 1)
    assertStretch((carry.unmatched[0].start, carry.unmatched[0].end), inserted, inserted + 25)
    XCTAssertEqual(carry.marks.count, 2)
    assertStretch((carry.marks[0].start, carry.marks[0].end), 60, 90)
    assertStretch((carry.marks[1].start, carry.marks[1].end), 275, 295)
  }

  func testAnAdThePhoneDoesNotHaveLeavesNoMarkAndMovesTheRestEarlier() {
    var later = map
    later.marks.append(EpisodeMapMark(start: 250, end: 270, kind: "promo"))
    let carry = EpisodeMapAligner(map: later).carry(Copy.heard([intro, middle, outro]))
    XCTAssertTrue(carry.lined)
    XCTAssertTrue(carry.unmatched.isEmpty)
    XCTAssertEqual(carry.marks.count, 1)
    assertStretch((carry.marks[0].start, carry.marks[0].end), 220, 240)
    XCTAssertEqual(carry.marks[0].kind, "promo")
  }

  func testADifferentAdInTheSamePlaceIsSkippedAsUnmatched() {
    let phoneAd = Copy.audio(21, seconds: 45)
    let carry = EpisodeMapAligner(map: map).carry(Copy.heard([intro, phoneAd, middle, outro]))
    XCTAssertTrue(carry.lined)
    XCTAssertTrue(carry.marks.isEmpty)
    XCTAssertEqual(carry.unmatched.count, 1)
    assertStretch((carry.unmatched[0].start, carry.unmatched[0].end), 60, 105)
  }

  func testADifferentPreRollIsUnmatchedFromTheEpisodesStart() {
    let macPre = Copy.audio(30, seconds: 20)
    let phonePre = Copy.audio(31, seconds: 35)
    let withPre = Copy.map(
      [macPre, intro, macAd, middle, outro],
      marks: [
        EpisodeMapMark(start: 0, end: 20, kind: "ad"), EpisodeMapMark(start: 80, end: 110, kind: "ad"),
      ])
    let carry = EpisodeMapAligner(map: withPre).carry(
      Copy.heard([phonePre, intro, macAd, middle, outro]))
    XCTAssertTrue(carry.lined)
    XCTAssertEqual(carry.unmatched.count, 1)
    assertStretch((carry.unmatched[0].start, carry.unmatched[0].end), 0, 35)
    XCTAssertEqual(carry.marks.count, 1)
    assertStretch((carry.marks[0].start, carry.marks[0].end), 95, 125)
  }

  func testAStartInTheMiddleOfTheEpisodeLinesUpWithThePhonesOwnTimes() {
    // The phone has frames from 100 s of its own copy on: the last 80 s of the middle, then the
    // outro. Nothing before its first frame is called an ad.
    var later = map
    later.marks.append(EpisodeMapMark(start: 215, end: 235, kind: "ad"))
    let tail = Array(middle.suffix(Int((80 / Copy.frame).rounded())))
    let carry = EpisodeMapAligner(map: later).carry(Copy.heard([tail, outro], from: 100))
    XCTAssertTrue(carry.lined)
    XCTAssertTrue(carry.unmatched.isEmpty)
    XCTAssertEqual(carry.marks.count, 1)
    // 215 s of the Mac's copy is 5 s after the outro starts, which the phone has at 180 s.
    assertStretch((carry.marks[0].start, carry.marks[0].end), 185, 205)
  }

  func testAStartInTheMiddleDoesNotCallItsUnmatchedBeginningAnAd() {
    let other = Copy.audio(40, seconds: 30)
    let carry = EpisodeMapAligner(map: map).carry(Copy.heard([other, middle, outro], from: 400))
    XCTAssertTrue(carry.lined)
    XCTAssertTrue(carry.unmatched.isEmpty)
  }

  func testAnUnmatchedStretchUnderEightSecondsIsNotGiven() {
    let glitch = Copy.audio(50, seconds: 6)
    let carry = EpisodeMapAligner(map: map).carry(
      Copy.heard([intro, macAd, glitch, middle, outro]))
    XCTAssertTrue(carry.lined)
    XCTAssertTrue(carry.unmatched.isEmpty)
  }

  func testAnUnmatchedEndIsNotGivenBecauseNoMatchedAudioFollowsIt() {
    let carry = EpisodeMapAligner(map: map).carry(
      Copy.heard([intro, macAd, middle, Copy.audio(60, seconds: 40)]), complete: true)
    XCTAssertTrue(carry.lined)
    XCTAssertTrue(carry.unmatched.isEmpty)
  }

  func testACarriedPieceUnderFiveSecondsIsDroppedWhenTheCopiesDiffer() {
    // The Mac's mark runs 3 s into the show after its ad (an overshoot). The phone has another
    // ad there, so only the 3 s sliver matches: it is not a skip.
    var over = map
    over.marks = [EpisodeMapMark(start: 60, end: 93, kind: "ad")]
    let carry = EpisodeMapAligner(map: over).carry(
      Copy.heard([intro, Copy.audio(22, seconds: 30), middle, outro]))
    XCTAssertTrue(carry.lined)
    XCTAssertTrue(carry.marks.isEmpty)
    XCTAssertEqual(carry.unmatched.count, 1)
  }

  func testAMarkThePhoneHasWithOtherAudioInItsMiddleStaysOnePiece() {
    // The Mac marked one break of two spots. The phone has the first spot, then 4 s of other
    // audio, then the second spot: the whole of it is the break.
    let spotOne = Copy.audio(70, seconds: 20), spotTwo = Copy.audio(71, seconds: 20)
    let twoSpots = Copy.map(
      [intro, spotOne, spotTwo, middle],
      marks: [EpisodeMapMark(start: 60, end: 100, kind: "ad")])
    let carry = EpisodeMapAligner(map: twoSpots).carry(
      Copy.heard([intro, spotOne, Copy.audio(72, seconds: 4), spotTwo, middle]))
    XCTAssertEqual(carry.marks.count, 1)
    assertStretch((carry.marks[0].start, carry.marks[0].end), 60, 104)
  }

  func testAReEditThatDiffersOverThirtyPercentIsNoMap() {
    // Only the intro is the same audio; the rest of the phone's copy was cut again.
    let carry = EpisodeMapAligner(map: map).carry(
      Copy.heard([intro, Copy.audio(80, seconds: 100), Array(middle.prefix(400)),
        Copy.audio(81, seconds: 110)]), complete: true)
    XCTAssertFalse(carry.lined)
    XCTAssertTrue(carry.marks.isEmpty)
    XCTAssertTrue(carry.unmatched.isEmpty)
  }

  func testACopyWithNothingInCommonIsNoMap() {
    let carry = EpisodeMapAligner(map: map).carry(Copy.heard([Copy.audio(90, seconds: 200)]))
    XCTAssertFalse(carry.lined)
  }

  func testDigitalSilenceInBothCopiesIsNotAMatchByItself() {
    let silence = [UInt8](repeating: 7, count: 2000)
    let quiet = Copy.map([silence, intro], marks: [EpisodeMapMark(start: 10, end: 30, kind: "ad")])
    let carry = EpisodeMapAligner(map: quiet).carry(
      Copy.heard([Copy.audio(91, seconds: 30), silence, Copy.audio(92, seconds: 30)]))
    XCTAssertFalse(carry.lined)
  }

  func testAnHourLinesUpInWellUnderASecond() {
    let show = (0..<12).map { Copy.audio(UInt64(100 + $0), seconds: 290) }
    let macAds = (0..<12).map { Copy.audio(UInt64(200 + $0), seconds: 10) }
    let phoneAds = (0..<12).map { Copy.audio(UInt64(300 + $0), seconds: 10) }
    let hour = Copy.map(
      zip(show, macAds).flatMap { [$0, $1] },
      marks: (0..<12).map {
        EpisodeMapMark(start: Double($0) * 300 + 290, end: Double($0 + 1) * 300, kind: "ad")
      })
    let aligner = EpisodeMapAligner(map: hour)
    let heard = Copy.heard(zip(show, phoneAds).flatMap { [$0, $1] })
    let started = Date()
    let carry = aligner.carry(heard, complete: true)
    XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)
    XCTAssertTrue(carry.lined)
    XCTAssertEqual(carry.unmatched.count, 11)  // the last one has no matched audio after it
    XCTAssertTrue(carry.marks.isEmpty)
  }
}
