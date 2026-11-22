import XCTest

@testable import PodcastAudioMatch

final class AdSoundBuilderTests: XCTestCase {
  /// An episode of made-up frames: filler, then the ad ids, then filler. Also the marked stretch
  /// of the ad, `slack` seconds wider or narrower on each side than the ad itself.
  private func episode(
    filler: Int, ad: [Int], slack: Double = 0, sort: String = "sponsor", who: String = "Acme"
  ) -> (frames: [MP3Frame], marked: [MarkedStretch]) {
    let ids = Array(filler..<filler + 300) + ad + Array(filler + 300..<filler + 500)
    let start = Snd.time(300) - slack
    let end = Snd.time(300 + ad.count) + slack
    return (Snd.frames(ids), [MarkedStretch(start: start, end: end, sort: sort, who: who)])
  }

  private let ad = Array(0..<500)  // about 13 seconds

  func testAStretchSeenInTwoEpisodesCountsTwiceAndIsStoredOnce() {
    var builder = AdSoundBuilder()
    let one = episode(filler: 10_000, ad: ad)
    let two = episode(filler: 20_000, ad: ad, slack: 0.3)
    builder.add(episode: "one", frames: one.frames, marked: one.marked)
    builder.add(episode: "two", frames: two.frames, marked: two.marked)
    let sounds = builder.library().sounds
    XCTAssertEqual(sounds.count, 1)
    XCTAssertEqual(sounds[0].seen, 2)
    XCTAssertEqual(sounds[0].who, "Acme")
  }

  func testTheSameEpisodeAddedTwiceCountsOnce() {
    var builder = AdSoundBuilder()
    let one = episode(filler: 10_000, ad: ad)
    builder.add(episode: "one", frames: one.frames, marked: one.marked)
    builder.add(episode: "one", frames: one.frames, marked: one.marked)
    XCTAssertEqual(builder.library().sounds.map(\.seen), [1])
  }

  func testAMarginIsLeftOffEachEnd() throws {
    var builder = AdSoundBuilder()
    let one = episode(filler: 10_000, ad: ad)
    builder.add(episode: "one", frames: one.frames, marked: one.marked)
    let sound = try XCTUnwrap(builder.library().sounds.first)
    let marked = Double(ad.count) * Snd.duration
    XCTAssertEqual(sound.seconds, marked - 2 * AdSoundBuilder.margin, accuracy: 2 * Snd.duration)
    XCTAssertEqual(sound.frames, Int((sound.seconds / Snd.duration).rounded()))
    XCTAssertEqual(sound.anchors.count, (sound.frames + 7) / 8)
    // It starts about a second into the ad: frame 38 or 39 of it, counted from the ad's frame 0.
    let first = UInt32(truncatingIfNeeded: Snd.frames(Array(0..<500))[39].hash)
    let second = UInt32(truncatingIfNeeded: Snd.frames(Array(0..<500))[38].hash)
    XCTAssertTrue([first, second].contains(sound.anchors[0]))
  }

  func testTooShortAndTooLongStretchesAreLeftOut() {
    var builder = AdSoundBuilder()
    let short = episode(filler: 10_000, ad: Array(0..<(Int(9.5 / Snd.duration))))  // 7.5 s after margins
    builder.add(episode: "short", frames: short.frames, marked: short.marked)
    let long = Snd.frames(Array(0..<24_000))  // about 627 seconds
    builder.add(
      episode: "long", frames: long,
      marked: [MarkedStretch(start: 0, end: Snd.time(24_000), sort: "sponsor", who: "Acme")])
    XCTAssertTrue(builder.library().sounds.isEmpty)
  }

  func testAStretchWithAnUnknownSortIsLeftOut() {
    var builder = AdSoundBuilder()
    let one = episode(filler: 10_000, ad: ad, sort: "jingle")
    builder.add(episode: "one", frames: one.frames, marked: one.marked)
    XCTAssertTrue(builder.library().sounds.isEmpty)
  }

  func testTheMostSeenComeFirstThenInTheOrderAdded() {
    var builder = AdSoundBuilder()
    let ads = ["a": 0, "b": 1000, "c": 2000, "d": 3000]
    var filler = 100_000
    for (name, who) in [("1", ["a", "b", "c"]), ("2", ["c"]), ("3", ["c", "b", "d"])] {
      for one in who {
        let made = episode(filler: filler, ad: Array(ads[one]!..<ads[one]! + 500), who: one)
        builder.add(episode: name, frames: made.frames, marked: made.marked)
        filler += 1000
      }
    }
    let sounds = builder.library().sounds
    XCTAssertEqual(sounds.map(\.who), ["c", "b", "a", "d"])
    XCTAssertEqual(sounds.map(\.seen), [3, 2, 1, 1])
  }

  func testTheLibraryIsCutToFitTheLimit() throws {
    var builder = AdSoundBuilder()
    for n in 0..<5 {
      let made = episode(filler: 10_000 * (n + 1), ad: Array((n * 1000)..<(n * 1000 + 500)))
      builder.add(episode: "e\(n)", frames: made.frames, marked: made.marked)
    }
    let full = builder.library()
    XCTAssertEqual(full.sounds.count, 5)
    let limit = try full.data().count - 1
    let cut = builder.library(maxBytes: limit)
    XCTAssertEqual(cut.sounds, Array(full.sounds.prefix(4)))
    XCTAssertLessThanOrEqual(try cut.data().count, limit)
    XCTAssertTrue(builder.library(maxBytes: 10).sounds.isEmpty)
  }
}
