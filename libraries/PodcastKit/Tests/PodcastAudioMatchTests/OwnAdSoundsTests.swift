import XCTest

@testable import PodcastAudioMatch

/// Made-up episodes for the phone's own sounds. Seconds since 1970 are plain numbers here.
enum Own {
  static let now = 1_700_000_000.0
  static let day = 86_400.0

  /// An episode of made-up frames: `at` frames of filler, the ad's ids, then 200 more of filler.
  /// Also the stretch of the ad, which is where the phone skipped it.
  static func episode(
    filler: Int, ad: [Int], at: Int = 300, who: String = "Acme"
  ) -> (frames: [MP3Frame], stretch: MarkedStretch) {
    let ids = Array(filler..<filler + at) + ad + Array(filler + at..<filler + at + 200)
    let stretch = MarkedStretch(
      start: Snd.time(at), end: Snd.time(at + ad.count), sort: "sponsor", who: who)
    return (Snd.frames(ids), stretch)
  }

  /// One episode that holds `count` different ads of 320 frames (8.4 seconds) with filler between.
  /// The ids of an ad are told apart by `base` and its number.
  static func crowded(count: Int, base: Int) -> (frames: [MP3Frame], stretches: [MarkedStretch]) {
    var ids: [Int] = []
    var stretches: [MarkedStretch] = []
    for number in 0..<count {
      let block = base + number * 1000
      ids += Array(block + 500..<block + 550)
      stretches.append(
        MarkedStretch(
          start: Snd.time(ids.count), end: Snd.time(ids.count + 320), sort: "sponsor",
          who: "Acme \(number)"))
      ids += Array(block..<block + 320)
    }
    return (Snd.frames(ids), stretches)
  }
}

final class OwnAdSoundsTests: XCTestCase {
  private let ad = Array(0..<500)  // about 13 seconds

  private func hits(_ own: OwnAdSounds, in frames: [MP3Frame]) -> [AdSoundHit] {
    var scanner = AdSoundScanner(library: own.library)
    return scanner.feed(frames) + scanner.finish()
  }

  // MARK: Learning from one episode and finding it in another

  func testAPrintLearnedInOneEpisodeIsFoundInAnotherWithinAThirdOfASecond() throws {
    var own = OwnAdSounds()
    let one = Own.episode(filler: 10_000, ad: ad)
    XCTAssertEqual(own.learn(show: "show", frames: one.frames, stretches: [one.stretch], now: Own.now), 1)
    // The same bytes at another place, between other audio.
    let two = Own.episode(filler: 20_000, ad: ad, at: 1000)
    let found = hits(own, in: two.frames)
    XCTAssertEqual(found.count, 1)
    let hit = try XCTUnwrap(found.first)
    XCTAssertEqual(hit.start, two.stretch.start, accuracy: 0.3)
    XCTAssertEqual(hit.end, two.stretch.end, accuracy: 0.3)
    XCTAssertEqual(hit.sort, "sponsor")
    XCTAssertEqual(hit.who, "Acme")
  }

  func testAPrintIsKeptWithItsShowAndTheTimeItWasLastSeen() throws {
    var own = OwnAdSounds()
    let one = Own.episode(filler: 10_000, ad: ad)
    own.learn(show: "show", frames: one.frames, stretches: [one.stretch], now: Own.now)
    let entry = try XCTUnwrap(own.entries.first)
    XCTAssertEqual(entry.show, "show")
    XCTAssertEqual(entry.lastSeen, Own.now)
    XCTAssertEqual(entry.sound.seen, 1)
    XCTAssertEqual(own.library.sounds, [entry.sound])
  }

  func testTheSameAdInTheNextEpisodeIsCountedAgainNotStoredTwice() throws {
    var own = OwnAdSounds()
    let one = Own.episode(filler: 10_000, ad: ad)
    let two = Own.episode(filler: 20_000, ad: ad, at: 700)
    own.learn(show: "show", frames: one.frames, stretches: [one.stretch], now: Own.now)
    XCTAssertEqual(
      own.learn(show: "show", frames: two.frames, stretches: [two.stretch], now: Own.now + Own.day), 0)
    XCTAssertEqual(own.entries.count, 1)
    XCTAssertEqual(own.entries[0].sound.seen, 2)
    XCTAssertEqual(own.entries[0].lastSeen, Own.now + Own.day)
  }

  func testAStretchShorterThanEightSecondsAddsNothing() {
    var own = OwnAdSounds()
    // 300 frames last 7.84 seconds, 320 frames 8.36 seconds.
    let short = Own.episode(filler: 10_000, ad: Array(0..<300))
    XCTAssertEqual(
      own.learn(show: "show", frames: short.frames, stretches: [short.stretch], now: Own.now), 0)
    XCTAssertTrue(own.library.sounds.isEmpty)
    let enough = Own.episode(filler: 20_000, ad: Array(1000..<1320))
    XCTAssertEqual(
      own.learn(show: "show", frames: enough.frames, stretches: [enough.stretch], now: Own.now), 1)
  }

  func testAStretchLongerThanTenMinutesAddsNothing() {
    var own = OwnAdSounds()
    let long = Snd.frames(Array(0..<24_000))  // about 627 seconds
    let stretch = MarkedStretch(start: 0, end: Snd.time(24_000), sort: "sponsor", who: "Acme")
    XCTAssertEqual(own.learn(show: "show", frames: long, stretches: [stretch], now: Own.now), 0)
  }

  func testAStretchOfAnUnknownSortAddsNothing() {
    var own = OwnAdSounds()
    let one = Own.episode(filler: 10_000, ad: ad)
    var stretch = one.stretch
    stretch.sort = "jingle"
    XCTAssertEqual(own.learn(show: "show", frames: one.frames, stretches: [stretch], now: Own.now), 0)
  }

  // MARK: What the Mac already holds

  func testASoundTheMacHoldsIsNotAdded() {
    // The Mac's sound is the ad with a margin left off each end, as the Mac makes them.
    let mac = AdSoundLibrary(sounds: [Snd.sound(Array(ad[38..<462]), who: "Mac")])
    var own = OwnAdSounds()
    let one = Own.episode(filler: 10_000, ad: ad)
    XCTAssertEqual(
      own.learn(show: "show", frames: one.frames, stretches: [one.stretch], mac: mac, now: Own.now), 0)
    XCTAssertTrue(own.entries.isEmpty)
    // Another ad is still learned, and the same ad is learned without the Mac's library.
    let other = Own.episode(filler: 30_000, ad: Array(5000..<5500))
    XCTAssertEqual(
      own.learn(show: "show", frames: other.frames, stretches: [other.stretch], mac: mac, now: Own.now), 1)
    XCTAssertEqual(
      own.learn(show: "show", frames: one.frames, stretches: [one.stretch], now: Own.now), 1)
  }

  // MARK: Limits

  func testAShowKeepsAtMostFortySoundsAndTheOldestGo() {
    var own = OwnAdSounds()
    for (call, count) in [(0, 20), (1, 20), (2, 5)] {
      let made = Own.crowded(count: count, base: 1_000_000 * (call + 1))
      own.learn(show: "show", frames: made.frames, stretches: made.stretches, now: Own.now + Double(call))
    }
    XCTAssertEqual(OwnAdSounds.mostPerShow, 40)
    XCTAssertEqual(own.entries.count, 40)
    let times = own.entries.map(\.lastSeen)
    XCTAssertEqual(times.filter { $0 == Own.now + 2 }.count, 5)
    XCTAssertEqual(times.filter { $0 == Own.now + 1 }.count, 20)
    XCTAssertEqual(times.filter { $0 == Own.now }.count, 15)
  }

  func testAllShowsTogetherKeepAtMostFourHundredSounds() {
    var own = OwnAdSounds()
    for number in 0..<11 {
      let made = Own.crowded(count: 40, base: 1_000_000 * (number + 1))
      own.learn(
        show: "show \(number)", frames: made.frames, stretches: made.stretches,
        now: Own.now + Double(number))
    }
    XCTAssertEqual(OwnAdSounds.mostInAll, 400)
    XCTAssertEqual(own.entries.count, 400)
    XCTAssertEqual(Set(own.entries.map(\.show)).count, 10)
    XCTAssertFalse(own.entries.contains { $0.show == "show 0" })
    XCTAssertLessThanOrEqual(own.data.count, OwnAdSounds.maxBytes)
  }

  func testASoundNotSeenForSixtyDaysGoes() {
    var own = OwnAdSounds()
    let a = Own.episode(filler: 10_000, ad: ad)
    let b = Own.episode(filler: 20_000, ad: Array(1000..<1500))
    let c = Own.episode(filler: 30_000, ad: Array(2000..<2500))
    own.learn(show: "show", frames: a.frames, stretches: [a.stretch], now: Own.now)
    own.learn(show: "show", frames: b.frames, stretches: [b.stretch], now: Own.now + 59 * Own.day)
    XCTAssertEqual(own.entries.count, 2)
    own.learn(show: "show", frames: c.frames, stretches: [c.stretch], now: Own.now + 61 * Own.day)
    XCTAssertEqual(own.entries.count, 2)
    XCTAssertFalse(own.entries.contains { $0.lastSeen == Own.now })
    XCTAssertEqual(OwnAdSounds.keepDays, 60)
  }

  func testTheFileIsCutToItsLimitKeepingTheNewest() {
    var own = OwnAdSounds()
    for call in 0..<3 {
      let made = Own.crowded(count: 4, base: 1_000_000 * (call + 1))
      own.learn(show: "show", frames: made.frames, stretches: made.stretches, now: Own.now + Double(call))
    }
    XCTAssertEqual(OwnAdSounds.maxBytes, 1_500_000)
    let full = own.data.count
    own.prune(now: Own.now + 3, maxBytes: full * 2 / 3)
    XCTAssertLessThanOrEqual(own.data.count, full * 2 / 3)
    XCTAssertGreaterThan(own.entries.count, 0)
    XCTAssertLessThan(own.entries.count, 12)
    let times = own.entries.map(\.lastSeen)
    XCTAssertEqual(times, times.sorted(by: >))
    XCTAssertEqual(times.first, Own.now + 2)
  }

  // MARK: Undo

  func testAnUndoneStretchIsForgottenAndTheSameBytesAreNotLearnedAgain() {
    var own = OwnAdSounds()
    let one = Own.episode(filler: 10_000, ad: ad)
    own.learn(show: "show", frames: one.frames, stretches: [one.stretch], now: Own.now)
    XCTAssertEqual(own.library.sounds.count, 1)
    // The listener undoes the skip of the same ad in the next episode.
    let two = Own.episode(filler: 20_000, ad: ad, at: 900)
    XCTAssertEqual(
      own.forget(frames: two.frames, start: two.stretch.start, end: two.stretch.end, now: Own.now + 10), 1)
    XCTAssertTrue(own.library.sounds.isEmpty)
    // Right after, the same bytes in a third episode are not learned, also not after a trip
    // through the file.
    let three = Own.episode(filler: 30_000, ad: ad)
    XCTAssertEqual(
      own.learn(show: "show", frames: three.frames, stretches: [three.stretch], now: Own.now + 20), 0)
    var reread = OwnAdSounds.read(own.data)
    XCTAssertEqual(
      reread.learn(show: "show", frames: three.frames, stretches: [three.stretch], now: Own.now + 20), 0)
    XCTAssertTrue(reread.library.sounds.isEmpty)
    // Another ad is learned as before.
    let other = Own.episode(filler: 40_000, ad: Array(5000..<5500))
    XCTAssertEqual(
      reread.learn(show: "show", frames: other.frames, stretches: [other.stretch], now: Own.now + 30), 1)
  }

  func testForgettingOneStretchKeepsTheOtherSounds() {
    var own = OwnAdSounds()
    let one = Own.episode(filler: 10_000, ad: ad)
    let other = Own.episode(filler: 20_000, ad: Array(5000..<5500), who: "Other")
    own.learn(show: "show", frames: one.frames, stretches: [one.stretch], now: Own.now)
    own.learn(show: "show", frames: other.frames, stretches: [other.stretch], now: Own.now)
    XCTAssertEqual(
      own.forget(frames: one.frames, start: one.stretch.start, end: one.stretch.end, now: Own.now), 1)
    XCTAssertEqual(own.library.sounds.map(\.who), ["Other"])
  }

  func testAStretchWithNoPrintIsStillNotLearnedAfterItWasUndone() {
    var own = OwnAdSounds()
    let one = Own.episode(filler: 10_000, ad: ad)
    XCTAssertEqual(
      own.forget(frames: one.frames, start: one.stretch.start, end: one.stretch.end, now: Own.now), 0)
    XCTAssertEqual(own.learn(show: "show", frames: one.frames, stretches: [one.stretch], now: Own.now), 0)
    // The note is forgotten after sixty days like everything else.
    XCTAssertEqual(
      own.learn(show: "show", frames: one.frames, stretches: [one.stretch], now: Own.now + 61 * Own.day), 1)
  }

  func testAPrintThatOnlyTouchesTheUndoneStretchStays() {
    var own = OwnAdSounds()
    let one = Own.episode(filler: 10_000, ad: ad)
    own.learn(show: "show", frames: one.frames, stretches: [one.stretch], now: Own.now)
    // An undone stretch from 30 seconds before the ad to one second into it: it holds only the
    // first second of the print (38 of its 500 frames), the rest of it is other audio.
    let two = Own.episode(filler: 20_000, ad: ad, at: 1500)
    let from = Snd.time(1500) - 30
    let to = Snd.time(1500) + 1
    let slice = OwnAdSounds.cut(two.frames, from: from, to: to)
    let touched = SoundLookup(own.library).hits(in: slice)
    XCTAssertEqual(touched.count, 1)  // the print does touch it: a hit of about a second
    XCTAssertLessThan((touched.first?.end ?? 99) - (touched.first?.start ?? 0), 2)
    XCTAssertEqual(own.forget(frames: two.frames, start: from, end: to, now: Own.now), 0)
    XCTAssertEqual(own.entries.count, 1)
  }

  // MARK: Bad input

  func testBadInputNeverTrapsAndAddsNothing() {
    var own = OwnAdSounds()
    let one = Own.episode(filler: 10_000, ad: ad)
    let stretch = one.stretch
    func make(_ start: Double, _ end: Double) -> MarkedStretch {
      MarkedStretch(start: start, end: end, sort: "sponsor", who: "Acme")
    }
    let bad = [
      make(.nan, 10), make(0, .nan), make(.infinity, .infinity), make(-.infinity, 1e300),
      make(-5, -1), make(20, 10), make(1e300, 1e301), make(10, 10), make(-1e300, -1e299),
      make(0, 5),
    ]
    XCTAssertEqual(own.learn(show: "show", frames: one.frames, stretches: bad, now: Own.now), 0)
    XCTAssertEqual(own.learn(show: "show", frames: [], stretches: [stretch], now: Own.now), 0)
    XCTAssertEqual(own.learn(show: "show", frames: one.frames, stretches: [], now: Own.now), 0)
    XCTAssertEqual(own.learn(show: "", frames: one.frames, stretches: [stretch], now: Own.now), 0)
    XCTAssertEqual(
      own.learn(show: "show", frames: one.frames, stretches: [stretch], now: .nan), 0)
    XCTAssertEqual(
      own.learn(show: "show", frames: one.frames, stretches: [stretch], now: -.infinity), 0)
    XCTAssertTrue(own.entries.isEmpty)
    XCTAssertEqual(own.forget(frames: [], start: 0, end: 20, now: Own.now), 0)
    XCTAssertEqual(own.forget(frames: one.frames, start: .nan, end: 20, now: Own.now), 0)
    XCTAssertEqual(own.forget(frames: one.frames, start: 20, end: 10, now: Own.now), 0)
    XCTAssertEqual(own.forget(frames: one.frames, start: 0, end: .infinity, now: Own.now), 0)
    XCTAssertEqual(own.forget(frames: one.frames, start: 1e300, end: 1e301, now: Own.now), 0)
    XCTAssertEqual(own.forget(frames: one.frames, start: 0, end: 20, now: .nan), 0)
    own.prune(now: .nan)
    own.prune(now: -.infinity)
    // A stretch that runs past the end of the file is cut at the end of the frames.
    let past = MarkedStretch(start: Snd.time(300), end: 1e9, sort: "sponsor", who: "Acme")
    XCTAssertEqual(own.learn(show: "show", frames: one.frames, stretches: [past], now: Own.now), 1)
  }
}
