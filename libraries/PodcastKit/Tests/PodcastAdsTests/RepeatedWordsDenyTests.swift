import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// What "not an ad" keeps out of later episodes: the whole stretch, a part of it, and nothing
/// that lies next to it.
final class RepeatedWordsDenyTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  /// A memory whose show said `passage` in two episodes, and whose listener said that the
  /// stretch offered for it in the second is not an ad.
  private func denied(_ passage: [String]) -> RepeatedWords {
    var memory = RepeatedWords()
    let old = Speech.episode(tag: "old", total: 2000, plugs: [(400, passage)])
    memory.remember(show: "show", episode: "old", lines: Speech.lines(old), now: now)
    let new = Speech.episode(tag: "new", total: 2000, plugs: [(800, passage)])
    let lines = Speech.lines(new)
    let found = memory.find(show: "show", episode: "new", lines: lines, duration: 1000, now: now)
    XCTAssertEqual(found.count, 1)
    guard let ad = found.first else { return memory }
    memory.deny(show: "show", lines: lines, start: ad.start, end: ad.end, now: now)
    memory.remember(show: "show", episode: "new", lines: lines, now: now)
    return memory
  }

  private func find(_ memory: RepeatedWords, _ words: [String]) -> [FoundAd] {
    memory.find(
      show: "show", episode: "later", lines: Speech.lines(words),
      duration: Speech.seconds(words), now: now)
  }

  func testAPartOfADeniedStretchIsNotOfferedAgain() {
    // The denied stretch is 100 words; a later episode says 40 of them, which is under half of it.
    let passage = Speech.plug(100, tag: "disc")
    let memory = denied(passage)
    let later = Speech.episode(tag: "later", total: 2000, plugs: [(700, Array(passage[20..<60]))])
    XCTAssertEqual(find(memory, later), [])
  }

  func testFortySecondsOfADeniedStretchOfTwoMinutesAreNotOfferedAgain() {
    // More than a hundred runs: only some of its hashes are kept, spread over the stretch.
    let passage = Speech.plug(240, tag: "disc")
    let memory = denied(passage)
    let later = Speech.episode(tag: "later", total: 2000, plugs: [(700, Array(passage[100..<180]))])
    XCTAssertEqual(find(memory, later), [])
    // Control: the same 40 seconds of a passage nobody denied are offered.
    let other = Speech.plug(240, tag: "other")
    var fresh = memory
    let old = Speech.episode(tag: "mid", total: 2000, plugs: [(300, other)])
    fresh.remember(show: "show", episode: "mid", lines: Speech.lines(old), now: now)
    let again = Speech.episode(tag: "later", total: 2000, plugs: [(700, Array(other[100..<180]))])
    XCTAssertEqual(find(fresh, again).count, 1)
  }

  func testAnAdReadRightAfterADeniedDisclaimerIsStillOffered() {
    let disclaimer = Speech.plug(50, tag: "disc")
    let adRead = Speech.plug(120, tag: "adread")
    var memory = denied(disclaimer)
    let mid = Speech.episode(tag: "mid", total: 2000, plugs: [(1200, adRead)])
    memory.remember(show: "show", episode: "mid", lines: Speech.lines(mid), now: now)
    let later = Speech.episode(tag: "later", total: 2000, plugs: [(700, disclaimer + adRead)])
    let found = find(memory, later)
    XCTAssertEqual(found.count, 1)
    // The ad read starts at word 750 (375 seconds) and ends at word 870 (435 seconds); the
    // disclaimer is cut away, with a second to spare.
    XCTAssertEqual(found.first?.start ?? 0, Speech.time(ofWord: 750), accuracy: 3)
    XCTAssertGreaterThanOrEqual(found.first?.start ?? 0, Speech.time(ofWord: 750))
    XCTAssertEqual(found.first?.end ?? 0, Speech.time(ofWord: 870), accuracy: 3)
  }

  func testAStretchThatIsNotDeniedKeepsItsWholeLength() {
    // A denied passage elsewhere does not cut into a passage that shares nothing with it.
    let memory = denied(Speech.plug(100, tag: "disc"))
    var other = memory
    let old = Speech.episode(tag: "mid", total: 2000, plugs: [(300, Speech.plug(100, tag: "keep"))])
    other.remember(show: "show", episode: "mid", lines: Speech.lines(old), now: now)
    let later = Speech.episode(tag: "later", total: 2000, plugs: [(700, Speech.plug(100, tag: "keep"))])
    let found = find(other, later)
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found.first?.start ?? 0, Speech.time(ofWord: 700), accuracy: 0.001)
    XCTAssertEqual(found.first?.end ?? 0, Speech.time(ofWord: 800), accuracy: 0.001)
  }
}
