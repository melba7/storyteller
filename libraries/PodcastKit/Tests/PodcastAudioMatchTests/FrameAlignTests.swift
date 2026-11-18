import XCTest

@testable import PodcastAudioMatch

final class FrameAlignTests: XCTestCase {
  private let show: [UInt64] = (100..<160).map { UInt64($0) }

  private func join(_ parts: [UInt64]...) -> [UInt64] { parts.flatMap { $0 } }
  private func ids(_ range: Range<Int>) -> [UInt64] { range.map { UInt64($0) } }

  func testDifferentStartsAlignAtTheRightFrame() {
    let a = join(ids(1..<6), show)  // a 5 frame ad, then the show
    let b = join(ids(200..<212), show)  // a 12 frame ad, then the show
    let result = FrameAlign.align(a, b)
    XCTAssertEqual(result.differing, [FrameDifference(a: 0..<5, b: 0..<12)])
    XCTAssertEqual(result.matched, 60)
    XCTAssertEqual(result.unmatchedTailA, 0)
    XCTAssertEqual(result.unmatchedTailB, 0)
  }

  func testAnAdInTheMiddleOfOneCopyOnly() {
    let a = join(Array(show[0..<20]), [900, 901, 902], Array(show[20...]))
    let result = FrameAlign.align(a, show)
    XCTAssertEqual(result.differing, [FrameDifference(a: 20..<23, b: 20..<20)])
    XCTAssertEqual(result.matched, 60)
  }

  func testIdenticalListsHaveNoDifferingRange() {
    let result = FrameAlign.align(show, show)
    XCTAssertTrue(result.differing.isEmpty)
    XCTAssertEqual(result.matched, 60)
    XCTAssertEqual(result.unmatchedTailA, 0)
  }

  func testListsThatNeverJoinAgainGiveNothing() {
    let a = join(Array(show[0..<20]), ids(500..<540))
    let b = join(Array(show[0..<20]), ids(700..<745))
    let result = FrameAlign.align(a, b)
    XCTAssertTrue(result.differing.isEmpty)
    XCTAssertEqual(result.matched, 20)
    XCTAssertEqual(result.unmatchedTailA, 40)
    XCTAssertEqual(result.unmatchedTailB, 45)
  }

  func testTwoSeparateAds() {
    let a = join(Array(show[0..<10]), [900, 901], Array(show[10..<40]), [910], Array(show[40...]))
    let b = join(Array(show[0..<10]), [800, 801, 802], Array(show[10..<40]), [810, 811], Array(show[40...]))
    let result = FrameAlign.align(a, b)
    XCTAssertEqual(
      result.differing,
      [FrameDifference(a: 10..<12, b: 10..<13), FrameDifference(a: 42..<43, b: 43..<45)])
  }

  func testEmptyListsAreFine() {
    XCTAssertTrue(FrameAlign.align([], show).differing.isEmpty)
    XCTAssertTrue(FrameAlign.align([], []).differing.isEmpty)
  }

  func testAShortCommonStretchDoesNotCountAsJoining() {
    // Only 3 frames agree after the difference, fewer than the anchor of 8.
    let a = join(Array(show[0..<10]), [900, 901], [1, 2, 3])
    let b = join(Array(show[0..<10]), [800, 801, 802], [1, 2, 3])
    XCTAssertTrue(FrameAlign.align(a, b).differing.isEmpty)
  }
}
