import XCTest

@testable import PodcastAudioMatch

/// The sound half of the whole-round test: a made show of three episodes whose files are built
/// from numbers (`RoundSound`). The phone learns its own sound prints from the sure ads of the
/// first two episodes, after the joint snap, and finds the ads of the third by them.
final class RoundThreeEpisodesSoundTests: RoundSoundCase {
  private typealias Show = RoundSound

  /// The borders the words gave in episode one and two: always a little late at the start and
  /// early at the end, by different amounts, so only the joint snap makes the prints agree.
  private func wordsOne() -> [SoundSpan] {
    [found(Show.one, "acme", late: 1.1, early: 0.8), found(Show.one, "beta", late: 0.6, early: 1.3)]
  }
  private func wordsTwo() -> [SoundSpan] {
    [found(Show.two, "beta", late: 0.9, early: 1.0), found(Show.two, "acme", late: 0.7, early: 1.4)]
  }

  private func assertHit(
    _ hit: SoundSpan?, _ episode: RoundSound.Episode, _ ad: String, file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(hit?.start ?? -99, episode.start(ad), accuracy: 0.3, "\(ad) start", file: file, line: line)
    XCTAssertEqual(hit?.end ?? -99, episode.end(ad), accuracy: 0.3, "\(ad) end", file: file, line: line)
  }

  func testEpisodeThreesAdsAreFoundByThePhonesOwnPrintsWithinThreeTenthsOfASecond() throws {
    var own = OwnAdSounds()
    // Episode one: nothing is known yet, so nothing is found, but both sure ads are learned.
    let first = try phone(write(Show.one, as: "one.mp3"), &own, found: wordsOne())
    XCTAssertEqual(first.hits, [], "an episode is never searched with its own ads")
    XCTAssertEqual(own.entries.count, 2)
    // The snap put the borders on the joints, whatever the words said.
    XCTAssertEqual(first.snapped[0].start, Show.one.start("acme"), accuracy: 1e-6)
    XCTAssertEqual(first.snapped[0].end, Show.one.end("acme"), accuracy: 1e-6)
    // Episode two: the prints of episode one find both ads, and the same two sounds are seen again
    // (not two more), because the snapped borders give the same print each time.
    let second = try phone(write(Show.two, as: "two.mp3"), &own, found: wordsTwo())
    XCTAssertEqual(second.hits.count, 2)
    assertHit(second.hits.first, Show.two, "beta")
    assertHit(second.hits.last, Show.two, "acme")
    XCTAssertEqual(own.entries.count, 2)
    XCTAssertEqual(own.entries.map(\.sound.seen), [2, 2])
    // Episode three: found by the phone's own prints alone (the Mac has no library here).
    let hits = ScoreSounds.ownSounds(in: try write(Show.three, as: "three.mp3"), own: own, show: Show.show)
    XCTAssertEqual(hits.count, 2, "\(hits)")
    assertHit(hits.first, Show.three, "acme")
    assertHit(hits.last, Show.three, "beta")
    XCTAssertEqual(hits.map(\.sort), ["sponsor", "sponsor"])
  }

  func testWithoutTheJointSnapTheSamePrintsAreFoundAtTheWordsBorders() throws {
    // The control: learn the borders as the words gave them. The prints then start 1.1 s late and
    // end 0.8 s early, so the skip in episode three would too. That is why the snap comes first.
    var own = OwnAdSounds()
    let rough = wordsOne()
    let stretches = rough.map { MarkedStretch(start: $0.start, end: $0.end, sort: $0.sort, who: "") }
    ScoreSounds.learnOwn(
      &own, show: Show.show, in: try write(Show.one, as: "one.mp3"), stretches: stretches, now: Show.now)
    let hits = ScoreSounds.ownSounds(in: try write(Show.three, as: "three.mp3"), own: own, show: Show.show)
    XCTAssertEqual(hits.first?.start ?? 0, Show.three.start("acme") + 1.1, accuracy: 0.3)
    XCTAssertGreaterThan((hits.first?.start ?? 0) - Show.three.start("acme"), 0.3)
  }

  func testAnAdTheListenerUndidInEpisodeTwoIsNotLearnedAndNotFoundInEpisodeThree() throws {
    var own = OwnAdSounds()
    try phone(write(Show.one, as: "one.mp3"), &own, found: wordsOne())
    // Episode two: both ads are found by their prints, and the listener undoes BETA's skip. The
    // phone forgets what it knows of that stretch (read from the frames of the file) and does not
    // learn it from this episode, though the words still call it a sure ad.
    let two = try write(Show.two, as: "two.mp3")
    let beta = SoundSpan(start: Show.two.start("beta"), end: Show.two.end("beta"))
    let second = try phone(two, &own, found: wordsTwo(), undone: [wordsTwo()[0]])
    XCTAssertEqual(second.hits.count, 2, "the undone skip was made from the print, so it was found")
    let frames = OwnAdSoundsFile.frames(in: two, stretches: [(beta.start, beta.end)])
    XCTAssertEqual(own.forget(frames: frames, start: beta.start, end: beta.end, now: Show.now), 1)
    XCTAssertEqual(own.entries.count, 1)
    // Episode three has both ads again. Only ACME is found.
    let three = try write(Show.three, as: "three.mp3")
    let hits = ScoreSounds.ownSounds(in: three, own: own, show: Show.show)
    XCTAssertEqual(hits.count, 1)
    assertHit(hits.first, Show.three, "acme")
    // Even when the words call BETA a sure ad again in episode three, its bytes are not learned:
    // the phone keeps the print of what the listener undid.
    let again = MarkedStretch(
      start: Show.three.start("beta"), end: Show.three.end("beta"), sort: "sponsor", who: "")
    XCTAssertEqual(
      ScoreSounds.learnOwn(&own, show: Show.show, in: three, stretches: [again], now: Show.now), 0)
    XCTAssertEqual(ScoreSounds.ownSounds(in: three, own: own, show: Show.show).count, 1)
  }

  func testAnAdMetForTheFirstTimeInEpisodeThreeIsLearnedFromItButNotFoundInIt() throws {
    var own = OwnAdSounds()
    try phone(write(Show.one, as: "one.mp3"), &own, found: wordsOne())
    try phone(write(Show.two, as: "two.mp3"), &own, found: wordsTwo())
    // DELTA plays only in episodes three and four. In three the words call it a sure ad.
    let words = [found(Show.three, "acme", late: 0.5, early: 0.5), found(Show.three, "delta", late: 1.0, early: 0.6)]
    let third = try phone(write(Show.three, as: "three.mp3"), &own, found: words)
    XCTAssertEqual(third.hits.count, 2, "ACME and BETA, which the first two episodes taught")
    assertHit(third.hits.first, Show.three, "acme")
    assertHit(third.hits.last, Show.three, "beta")
    XCTAssertEqual(own.entries.count, 3, "DELTA is learned after the scan, not found by it")
    // Episode four: DELTA is found, by what episode three taught.
    let fourth = ScoreSounds.ownSounds(in: try write(Show.four, as: "four.mp3"), own: own, show: Show.show)
    XCTAssertEqual(fourth.count, 1)
    assertHit(fourth.first, Show.four, "delta")
  }
}
