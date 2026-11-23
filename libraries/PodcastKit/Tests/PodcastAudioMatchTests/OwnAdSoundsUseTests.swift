import XCTest

@testable import PodcastAudioMatch

/// What the phone does with the prints when it scans an episode: which hits it trusts, and which
/// prints it scans for in which show.
final class OwnAdSoundsUseTests: XCTestCase {
  private let ad = Array(0..<500)  // about 13 seconds

  private func hits(_ library: AdSoundLibrary, in frames: [MP3Frame]) -> [AdSoundHit] {
    var scanner = AdSoundScanner(library: library)
    return scanner.feed(frames) + scanner.finish()
  }

  // MARK: Hits that matched only a part of a print

  func testAHitSaysHowManyAnchorsMatched() throws {
    var own = OwnAdSounds()
    let one = Own.episode(filler: 10_000, ad: ad)
    own.learn(show: "show", frames: one.frames, stretches: [one.stretch], now: Own.now)
    let two = Own.episode(filler: 20_000, ad: ad, at: 700)
    let hit = try XCTUnwrap(hits(own.library, in: two.frames).first)
    XCTAssertEqual(hit.matched, own.entries[0].sound.anchors.count)
    XCTAssertEqual(hit.matched, 63)
  }

  func testAFullMatchIsTrusted() {
    var own = OwnAdSounds()
    let one = Own.episode(filler: 10_000, ad: ad)
    own.learn(show: "show", frames: one.frames, stretches: [one.stretch], now: Own.now)
    let two = Own.episode(filler: 20_000, ad: ad, at: 700)
    let found = hits(own.library, in: two.frames)
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(OwnAdSounds.trusted(found), found)
  }

  func testAMatchOfTheEndOfALongPrintIsNotTrusted() throws {
    // A 62 second stretch: 60 seconds of the show, then a sting of 2 seconds.
    var own = OwnAdSounds()
    let sting = Array(900_000..<900_080)
    let ids = Array(1..<300) + Array(10_000..<12_300) + sting + Array(50_000..<50_200)
    let stretch = MarkedStretch(start: Snd.time(299), end: Snd.time(299 + 2380), sort: "sponsor", who: "X")
    XCTAssertEqual(own.learn(show: "show", frames: Snd.frames(ids), stretches: [stretch], now: Own.now), 1)
    // The next episode holds the sting alone, at 80.5 seconds.
    let next = Snd.frames(Array(60_000..<63_080) + sting + Array(70_000..<70_200))
    let found = hits(own.library, in: next)
    let hit = try XCTUnwrap(found.first)
    XCTAssertEqual(found.count, 1)
    // The hit begins where the whole print would begin and ends after the sting.
    XCTAssertEqual(hit.start, 20.4, accuracy: 0.1)
    XCTAssertEqual(hit.end, 82.5, accuracy: 0.1)
    XCTAssertEqual(hit.matched, 10)
    XCTAssertTrue(OwnAdSounds.trusted(found).isEmpty)
  }

  func testTrustedKeepsTheTrustedHitsAndLeavesTheOthers() {
    func hit(_ start: Double, _ end: Double, matched: Int) -> AdSoundHit {
      AdSoundHit(sound: 0, sort: "sponsor", who: "A", start: start, end: end, matched: matched)
    }
    let whole = hit(10, 23, matched: 63)  // 13 seconds, all matched
    let half = hit(100, 110, matched: 25)  // 25 anchors are 5.2 seconds: just over half of 10
    let less = hit(200, 210, matched: 23)  // 4.8 seconds: just under half
    let none = hit(300, 310, matched: 0)  // a hit made by hand says nothing about its anchors
    XCTAssertEqual(OwnAdSounds.trusted([whole, less, half, none]), [whole, half])
    XCTAssertTrue(OwnAdSounds.trusted([]).isEmpty)
    XCTAssertTrue(OwnAdSounds.trusted([hit(.nan, 5, matched: 10), hit(5, .nan, matched: 10)]).isEmpty)
  }

  func testAHitFromTheMacsScannerKeepsItsOtherFields() throws {
    // A hit is what it was; `matched` is added to it.
    let mac = AdSoundLibrary(sounds: [Snd.sound(ad, who: "Mac")])
    let found = hits(mac, in: Snd.frames(Snd.ids(1000..<1200, 0..<500)))
    let hit = try XCTUnwrap(found.first)
    XCTAssertEqual(hit.who, "Mac")
    XCTAssertEqual(hit.start, Snd.time(200), accuracy: 1e-9)
    XCTAssertEqual(hit.end, Snd.time(700), accuracy: 1e-9)
    XCTAssertEqual(hit.matched, 63)
  }

  // MARK: The show of a print

  func testAPrintIsScannedForInItsOwnShowAndInAnotherOnlyAfterItWasSeenTwice() {
    var own = OwnAdSounds()
    let one = Own.episode(filler: 10_000, ad: ad, who: "One")
    let other = Own.episode(filler: 20_000, ad: Array(5000..<5500), who: "Other")
    own.learn(show: "A", frames: one.frames, stretches: [one.stretch], now: Own.now)
    own.learn(show: "B", frames: other.frames, stretches: [other.stretch], now: Own.now)
    XCTAssertEqual(own.library.sounds.count, 2)
    XCTAssertEqual(own.library(for: "A").sounds.map(\.who), ["One"])
    XCTAssertEqual(own.library(for: "B").sounds.map(\.who), ["Other"])
    XCTAssertTrue(own.library(for: "C").sounds.isEmpty)
    XCTAssertTrue(own.library(for: "").sounds.isEmpty)
    // The ad of show A comes back in the next episode: seen twice, it may cross shows.
    let again = Own.episode(filler: 30_000, ad: ad, at: 800, who: "One")
    own.learn(show: "A", frames: again.frames, stretches: [again.stretch], now: Own.now + 1)
    XCTAssertEqual(own.library(for: "C").sounds.map(\.who), ["One"])
    XCTAssertEqual(Set(own.library(for: "B").sounds.map(\.who)), ["One", "Other"])
    XCTAssertEqual(own.library(for: "A").sounds.map(\.who), ["One"])
    XCTAssertEqual(own.library.sounds.count, 2)
  }
}
