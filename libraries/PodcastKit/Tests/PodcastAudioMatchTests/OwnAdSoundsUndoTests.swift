import XCTest

@testable import PodcastAudioMatch

/// Undo must forget a wrong print also when the print matched only a part of itself, or the
/// undone stretch is short. Made-up frames: a sting of 80 frames (2.1 seconds) and content of
/// 2300 frames (60 seconds), learned together as one 62 second stretch.
final class OwnAdSoundsUndoTests: XCTestCase {
  private let sting = Array(900_000..<900_080)
  private let content = Array(10_000..<12_300)

  private func hits(_ own: OwnAdSounds, in frames: [MP3Frame]) -> [AdSoundHit] {
    var scanner = AdSoundScanner(library: own.library)
    return scanner.feed(frames) + scanner.finish()
  }

  /// The phone learned a 62 second stretch made of `parts` in this order.
  private func learned(_ parts: [Int]...) -> OwnAdSounds {
    var own = OwnAdSounds()
    let ids = Array(1..<300) + parts.flatMap { $0 } + Array(50_000..<50_200)
    let length = parts.reduce(0) { $0 + $1.count }
    let stretch = MarkedStretch(
      start: Snd.time(299), end: Snd.time(299 + length), sort: "sponsor", who: "Acme")
    XCTAssertEqual(own.learn(show: "show", frames: Snd.frames(ids), stretches: [stretch], now: Own.now), 1)
    XCTAssertEqual(own.entries[0].sound.seconds, 62.17, accuracy: 0.05)
    return own
  }

  func testTheStingAtTheStartOfAPrintGivesAShortSkipAndUndoForgetsIt() throws {
    var own = learned(sting, content)
    // The next episode holds the sting alone: a skip of 2.1 seconds.
    let next = Snd.frames(Array(60_000..<63_000) + sting + Array(70_000..<73_000))
    let hit = try XCTUnwrap(hits(own, in: next).first)
    XCTAssertEqual(hit.start, Snd.time(3000), accuracy: 0.05)
    XCTAssertEqual(hit.end - hit.start, 2.1, accuracy: 0.1)
    // The listener undoes that skip: the print goes, though the skip is 2.1 seconds of 62.
    XCTAssertEqual(own.forget(frames: next, start: hit.start, end: hit.end, now: Own.now + 10), 1)
    XCTAssertTrue(own.library.sounds.isEmpty)
    XCTAssertTrue(hits(own, in: next).isEmpty)
  }

  func testTheStingAtTheEndOfAPrintGivesALongSkipAndUndoForgetsIt() throws {
    var own = learned(content, sting)
    // The sting alone near the start of the next episode: the skip begins where the whole print
    // would have begun, which is before the file, so it begins at 0.
    let next = Snd.frames(Array(60_000..<60_500) + sting + Array(70_000..<72_500))
    let hit = try XCTUnwrap(hits(own, in: next).first)
    XCTAssertEqual(hit.start, 0)
    XCTAssertEqual(hit.end, Snd.time(584), accuracy: 0.05)
    XCTAssertEqual(own.forget(frames: next, start: hit.start, end: hit.end, now: Own.now + 10), 1)
    XCTAssertTrue(own.library.sounds.isEmpty)
    XCTAssertTrue(hits(own, in: next).isEmpty)
  }

  func testAnUndoneStretchInsideAPrintForgetsIt() {
    var own = OwnAdSounds()
    let one = Own.episode(filler: 10_000, ad: Array(0..<500))
    own.learn(show: "show", frames: one.frames, stretches: [one.stretch], now: Own.now)
    // 200 frames of the 500 frame print, in a stretch that is itself shorter than 8 seconds.
    let two = Own.episode(filler: 20_000, ad: Array(0..<500))
    XCTAssertEqual(
      own.forget(frames: two.frames, start: Snd.time(300 + 100), end: Snd.time(300 + 300), now: Own.now), 1)
    XCTAssertTrue(own.library.sounds.isEmpty)
  }
}
