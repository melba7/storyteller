import XCTest

@testable import PodcastAudioMatch

/// The builder learns from the sound bank as it learns from the audio, and gets the same library.
final class SoundBankBuilderTests: XCTestCase {
  /// An episode of made-up frames: filler, then the ad ids, then filler, and the marked stretch of the ad.
  private func episode(
    filler: Int, ad: [Int], slack: Double = 0, sort: String = "sponsor", who: String = "Acme"
  ) -> (frames: [MP3Frame], marked: [MarkedStretch]) {
    let ids = Array(filler..<filler + 300) + ad + Array(filler + 300..<filler + 500)
    let marked = MarkedStretch(
      start: Snd.time(300) - slack, end: Snd.time(300 + ad.count) + slack, sort: sort, who: who)
    return (Snd.frames(ids), [marked])
  }

  private let ad = Array(0..<500)  // about 13 seconds

  /// Several episodes: one ad twice (cut a little differently), a second and a third ad, a
  /// stretch that is too short and one of a sort that is not kept.
  private func episodes() -> [(id: String, frames: [MP3Frame], marked: [MarkedStretch])] {
    let made = [
      ("one", episode(filler: 10_000, ad: ad)),
      ("two", episode(filler: 20_000, ad: ad, slack: 0.3)),
      ("three", episode(filler: 30_000, ad: Array(1000..<1600), who: "Beta")),
      ("four", episode(filler: 40_000, ad: Array(2000..<2700), sort: "network_promo", who: "Net")),
      ("five", episode(filler: 50_000, ad: Array(0..<(Int(9.5 / Snd.duration))))),
      ("six", episode(filler: 60_000, ad: ad, sort: "jingle")),
      ("seven", episode(filler: 70_000, ad: Array(1000..<1600), who: "Beta")),
    ]
    return made.map { ($0.0, $0.1.frames, $0.1.marked) }
  }

  func testTheSliceHasTheFramesOfTheStretchLessTheMargins() throws {
    let one = episode(filler: 10_000, ad: ad)
    let slices = AdSoundBuilder.slice(frames: one.frames, marked: one.marked)
    XCTAssertEqual(slices.count, 1)
    let slice = slices[0]
    XCTAssertEqual(slice.sort, "sponsor")
    XCTAssertEqual(slice.who, "Acme")
    XCTAssertEqual(slice.seconds, Double(ad.count) * Snd.duration - 2 * AdSoundBuilder.margin, accuracy: 2 * Snd.duration)
    // It starts about a second into the ad: frame 38 or 39 of it. Times count from its first frame.
    let hashes = Snd.frames(ad).map { UInt32(truncatingIfNeeded: $0.hash) }
    XCTAssertTrue([hashes[38], hashes[39]].contains(slice.frames[0].hash))
    XCTAssertEqual(slice.frames[0].start, 0)
    XCTAssertEqual(slice.frames[1].start, Float(Snd.duration), accuracy: 1e-6)
    XCTAssertEqual(slice.frames[10].start, Float(10 * Snd.duration), accuracy: 1e-5)
    XCTAssertEqual(slice.frames[10].duration, Float(Snd.duration))
    let shift = slice.frames[0].hash == hashes[38] ? 38 : 39
    XCTAssertEqual(slice.frames.map(\.hash), Array(hashes[shift..<(shift + slice.frames.count)]))
  }

  func testTheSliceLeavesOutWhatTheLibraryWouldNotKeep() {
    let short = episode(filler: 10_000, ad: Array(0..<(Int(9.5 / Snd.duration))))  // 7.5 s after margins
    XCTAssertTrue(AdSoundBuilder.slice(frames: short.frames, marked: short.marked).isEmpty)
    let jingle = episode(filler: 10_000, ad: ad, sort: "jingle")
    XCTAssertTrue(AdSoundBuilder.slice(frames: jingle.frames, marked: jingle.marked).isEmpty)
    let long = Snd.frames(Array(0..<24_000))  // about 627 seconds
    let all = [MarkedStretch(start: 0, end: Snd.time(24_000), sort: "sponsor", who: "Acme")]
    XCTAssertTrue(AdSoundBuilder.slice(frames: long, marked: all).isEmpty)
    // Past the end of the file there is nothing.
    let past = [MarkedStretch(start: Snd.time(30_000), end: Snd.time(31_000), sort: "sponsor", who: "Acme")]
    XCTAssertTrue(AdSoundBuilder.slice(frames: long, marked: past).isEmpty)
  }

  func testTheLibraryMadeFromTheBankIsTheLibraryMadeFromTheAudioByteForByte() throws {
    var fromAudio = AdSoundBuilder()
    var fromBank = AdSoundBuilder()
    for one in episodes() {
      fromAudio.add(episode: one.id, frames: one.frames, marked: one.marked)
      // What the bank holds: written as a file and read back, with the frames long gone.
      let bytes = try SoundBank.data(
        episode: one.id, stretches: AdSoundBuilder.slice(frames: one.frames, marked: one.marked))
      let kept = try XCTUnwrap(SoundBank.stretches(from: bytes, episode: one.id))
      fromBank.add(episode: one.id, stretches: kept)
    }
    // The test means something: sounds seen twice, a sound seen once, one of each kept sort.
    XCTAssertEqual(fromAudio.library().sounds.map(\.seen), [2, 2, 1])
    XCTAssertEqual(Set(fromAudio.library().sounds.map(\.sort)), ["sponsor", "network_promo"])
    XCTAssertEqual(try fromBank.library().data(), try fromAudio.library().data())
    XCTAssertEqual(try fromBank.library(maxBytes: .max).data(), try fromAudio.library(maxBytes: .max).data())
  }

  func testSomeEpisodesFromAudioAndSomeFromTheBankMakeTheSameLibrary() throws {
    var fromAudio = AdSoundBuilder()
    var mixed = AdSoundBuilder()
    for (number, one) in episodes().enumerated() {
      fromAudio.add(episode: one.id, frames: one.frames, marked: one.marked)
      if number % 2 == 0 {
        mixed.add(episode: one.id, frames: one.frames, marked: one.marked)
      } else {
        let bytes = try SoundBank.data(
          episode: one.id, stretches: AdSoundBuilder.slice(frames: one.frames, marked: one.marked))
        mixed.add(episode: one.id, stretches: try XCTUnwrap(SoundBank.stretches(from: bytes, episode: one.id)))
      }
    }
    XCTAssertEqual(try mixed.library().data(), try fromAudio.library().data())
  }

  func testTheSameEpisodeFromTheAudioAndFromTheBankCountsOnce() throws {
    var builder = AdSoundBuilder()
    let one = episode(filler: 10_000, ad: ad)
    builder.add(episode: "one", frames: one.frames, marked: one.marked)
    builder.add(episode: "one", stretches: AdSoundBuilder.slice(frames: one.frames, marked: one.marked))
    XCTAssertEqual(builder.library().sounds.map(\.seen), [1])
  }

  func testBankedStretchesThatBreakTheRulesAreLeftOut() {
    let good = AdSoundBuilder.slice(
      frames: episode(filler: 10_000, ad: ad).frames,
      marked: episode(filler: 10_000, ad: ad).marked)[0]
    var jingle = good
    jingle.sort = "jingle"
    var tiny = good
    tiny.frames = Array(good.frames.prefix(3))
    var empty = good
    empty.frames = []
    var builder = AdSoundBuilder()
    builder.add(episode: "one", stretches: [jingle, tiny, empty])
    XCTAssertTrue(builder.library().sounds.isEmpty)
    builder.add(episode: "two", stretches: [jingle, good, tiny])
    XCTAssertEqual(builder.library().sounds.count, 1)
  }
}
