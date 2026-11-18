import XCTest

@testable import PodcastAudioMatch

final class CopyTruthTests: XCTestCase {
  private let frame = 1152.0 / 44100

  private func ads(_ a: MP3Parse, _ b: MP3Parse) -> [String] {
    CopyTruth.lines(a, b).filter { !$0.hasPrefix("#") }
  }

  private func notes(_ a: MP3Parse, _ b: MP3Parse) -> String {
    CopyTruth.lines(a, b).filter { $0.hasPrefix("#") }.joined(separator: "\n")
  }

  func testTheStretchOnlyCopyAHasIsMarkedWithItsTimesInCopyA() {
    let before = Marked.frames(0..<100)
    let after = Marked.frames(100..<200)
    let a = Marked.parse(before, Marked.frames(5_000..<5_200), after)  // a 200 frame spot
    let b = Marked.parse(before, Marked.frames(6_000..<6_150), after)  // a different, shorter one
    XCTAssertEqual(ads(a, b), ["0:02.612 0:07.837"])
  }

  func testAStretchThatDiffersAtTheStartIsMarkedFromZero() {
    let show = Marked.frames(0..<100)
    let a = Marked.parse(Marked.frames(5_000..<5_150), show)
    let b = Marked.parse(Marked.frames(6_000..<6_120), show)
    XCTAssertEqual(ads(a, b), ["0:00.000 0:03.918"])
  }

  func testTwoSeparateStretchesAreTwoLines() {
    let one = Marked.frames(0..<100)
    let two = Marked.frames(100..<200)
    let three = Marked.frames(200..<300)
    let first = Marked.frames(5_000..<5_100)
    let second = Marked.frames(5_100..<5_300)
    let a = Marked.parse(one, first, two, second, three)
    let b = Marked.parse(one, two, three)
    XCTAssertEqual(ads(a, b), ["0:02.612 0:05.224", "0:07.837 0:13.061"])
  }

  func testAStretchOnlyCopyBHasIsLeftOutAndSaid() {
    let before = Marked.frames(0..<100)
    let after = Marked.frames(100..<200)
    let a = Marked.parse(before, after)
    let b = Marked.parse(before, Marked.frames(6_000..<6_150), after)
    XCTAssertTrue(ads(a, b).isEmpty)
    XCTAssertTrue(notes(a, b).contains("only the second"), notes(a, b))
  }

  func testAShortDifferenceIsLeftOutAndSaid() {
    // 20 frames is half a second: a glitch, not an ad.
    let before = Marked.frames(0..<100)
    let after = Marked.frames(100..<200)
    let a = Marked.parse(before, Marked.frames(5_000..<5_020), after)
    let b = Marked.parse(before, Marked.frames(6_000..<6_020), after)
    XCTAssertTrue(ads(a, b).isEmpty)
    XCTAssertTrue(notes(a, b).contains("under 1 s"), notes(a, b))
  }

  func testWhatCopyAHasAfterTheLastJoinIsSaidAndNotMarked() {
    let show = Marked.frames(0..<100)
    let a = Marked.parse(show, Marked.frames(5_000..<5_200))
    let b = Marked.parse(show, Marked.frames(6_000..<6_100))
    XCTAssertTrue(ads(a, b).isEmpty)
    XCTAssertTrue(notes(a, b).contains("after the last place where they agree"), notes(a, b))
  }

  func testCopiesThatShareNothingMarkNothingAndSayWhy() {
    let a = Marked.parse(Marked.frames(0..<200))
    let b = Marked.parse(Marked.frames(1_000..<1_200))
    XCTAssertTrue(ads(a, b).isEmpty)
    XCTAssertTrue(notes(a, b).contains("no frame in common"), notes(a, b))
  }

  func testTheNotesSayAdsBothCopiesGotAreNotMarked() {
    let show = Marked.frames(0..<100)
    XCTAssertTrue(notes(Marked.parse(show), Marked.parse(show)).contains("both"))
  }

  func testTimesAreWrittenToTheMillisecondAndNeverShowSixtySeconds() {
    XCTAssertEqual(CopyTruth.clock(0), "0:00.000")
    XCTAssertEqual(CopyTruth.clock(2.6122), "0:02.612")
    XCTAssertEqual(CopyTruth.clock(59.9996), "1:00.000")
    XCTAssertEqual(CopyTruth.clock(754.5), "12:34.500")
    XCTAssertEqual(CopyTruth.clock(3723.5), "1:02:03.500")
  }
}
