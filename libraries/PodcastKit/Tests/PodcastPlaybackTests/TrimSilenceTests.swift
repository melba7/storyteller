import XCTest

@testable import PodcastPlayback

final class TrimSilenceTests: XCTestCase {
  /// 20 frames (1 s) of speech, then `quiet` frames of near silence, then speech again.
  private func loudness(quiet: Int, tail: Int = 20) -> [Float] {
    [Float](repeating: 0.1, count: 20) + [Float](repeating: 0.001, count: quiet)
      + [Float](repeating: 0.1, count: tail)
  }

  // MARK: Finding gaps

  func testAGapIsFoundWithItsTimes() {
    let gaps = SilenceFinder.gaps(loudness: loudness(quiet: 30))
    XCTAssertEqual(gaps, [SilentGap(start: 1.0, end: 2.5)])
  }

  func testShortQuietIsNotAGap() {
    XCTAssertEqual(SilenceFinder.gaps(loudness: loudness(quiet: 5)), [])
    XCTAssertEqual(SilenceFinder.gaps(loudness: loudness(quiet: 6)).count, 1)
  }

  func testTheThresholdFollowsTheEpisodesSpeechLevel() {
    // A quiet speaker: speech at 0.02, gaps at 0.0005 are still gaps...
    let quiet = [Float](repeating: 0.02, count: 20) + [Float](repeating: 0.0005, count: 20)
      + [Float](repeating: 0.02, count: 20)
    XCTAssertEqual(SilenceFinder.gaps(loudness: quiet).count, 1)
    // ...while the same 0.0005 is not a gap in a loud episode where speech is 0.5 and the
    // room is at 0.05 (-20 dB under speech is not silent enough).
    let loud = [Float](repeating: 0.5, count: 20) + [Float](repeating: 0.05, count: 20)
      + [Float](repeating: 0.5, count: 20)
    XCTAssertEqual(SilenceFinder.gaps(loudness: loud), [])
  }

  func testAGapAtTheEndOfTheEpisodeIsLeftOut() {
    let ending = [Float](repeating: 0.1, count: 20) + [Float](repeating: 0, count: 40)
    XCTAssertEqual(SilenceFinder.gaps(loudness: ending), [])
  }

  func testNoSpeechMeansNoGaps() {
    XCTAssertEqual(SilenceFinder.gaps(loudness: [Float](repeating: 0, count: 100)), [])
    XCTAssertEqual(SilenceFinder.gaps(loudness: []), [])
  }

  func testNotANumberIsTreatedAsQuiet() {
    var data = loudness(quiet: 10)
    data[22] = .nan
    XCTAssertEqual(SilenceFinder.gaps(loudness: data).count, 1)
  }

  // MARK: The jumps of each strength

  private let gaps = [
    SilentGap(start: 10, end: 10.5), SilentGap(start: 20, end: 21.2),
    SilentGap(start: 30, end: 33),
  ]

  func testMildOnlyTrimsLongGapsAndKeepsFourTenths() {
    let skipper = TrimSkipper(gaps: gaps, strength: .mild)
    XCTAssertEqual(
      skipper.trims,
      [Trim(start: 20.2, target: 21.0), Trim(start: 30.2, target: 32.8)])
    XCTAssertEqual(skipper.trims[1].saved, 2.6, accuracy: 1e-9)
  }

  func testStrongerStrengthsTrimMoreAndKeepLess() {
    XCTAssertEqual(TrimSkipper(gaps: gaps, strength: .medium).trims.count, 2)
    let strong = TrimSkipper(gaps: gaps, strength: .strong)
    XCTAssertEqual(strong.trims.count, 3)
    XCTAssertEqual(strong.trims[0].saved, 0.35, accuracy: 1e-9)
    let mild = TrimSkipper(gaps: gaps, strength: .mild).trims.map(\.saved).reduce(0, +)
    let medium = TrimSkipper(gaps: gaps, strength: .medium).trims.map(\.saved).reduce(0, +)
    XCTAssertGreaterThan(medium, mild)
  }

  func testOffTrimsNothing() {
    XCTAssertTrue(TrimSkipper(gaps: gaps, strength: .off).trims.isEmpty)
  }

  func testAdsAreNeverTrimmed() {
    let skipper = TrimSkipper(gaps: gaps, strength: .mild, avoiding: [19.0...20.5])
    XCTAssertEqual(skipper.trims, [Trim(start: 30.2, target: 32.8)])
    // A gap just after an ad's end counts as part of the ad's skip.
    let after = TrimSkipper(gaps: gaps, strength: .mild, avoiding: [15.0...19.8])
    XCTAssertEqual(after.trims.count, 1)
  }

  func testAShowsOwnChoiceWins() {
    XCTAssertEqual(TrimStrength.effective(show: .off, listener: .strong), .off)
    XCTAssertEqual(TrimStrength.effective(show: nil, listener: .strong), .strong)
    XCTAssertEqual(TrimStrength(stored: "medium"), .medium)
    XCTAssertEqual(TrimStrength(stored: "crazy"), .off)
  }

  // MARK: Markers and what to do at a position

  func testMarkersAreSetForTheWindowAhead() {
    let skipper = TrimSkipper(gaps: gaps, strength: .mild)
    XCTAssertEqual(skipper.boundaryTimes(after: 0, window: 25), [20.2])
    XCTAssertEqual(skipper.boundaryTimes(after: 20.2, window: 100), [30.2])
    XCTAssertEqual(skipper.boundaryTimes(after: 31, window: 100), [])
  }

  func testPlayingIntoAGapJumps() {
    let skipper = TrimSkipper(gaps: gaps, strength: .mild)
    XCTAssertEqual(skipper.reached(position: 20.25, rate: 1)?.target, 21.0)
    XCTAssertEqual(skipper.reached(position: 20.9, rate: 1)?.target, 21.0)
  }

  func testNothingToDoAwayFromAGapOrWhenItIsOver() {
    let skipper = TrimSkipper(gaps: gaps, strength: .mild)
    XCTAssertNil(skipper.reached(position: 25, rate: 1))
    XCTAssertNil(skipper.reached(position: 21.0, rate: 1))
    XCTAssertNil(skipper.reached(position: .nan, rate: 1))
  }

  func testSeekingIntoAGapPlaysIt() {
    var skipper = TrimSkipper(gaps: gaps, strength: .mild)
    skipper.seeked(to: 20.5)
    XCTAssertNil(skipper.reached(position: 20.55, rate: 1))
    // Seeking to just before it and playing on does jump.
    skipper.seeked(to: 19)
    XCTAssertNotNil(skipper.reached(position: 20.25, rate: 1))
  }

  func testAFasterSpeedAllowsALaterReport() {
    let skipper = TrimSkipper(gaps: [SilentGap(start: 20, end: 24)], strength: .mild)
    XCTAssertNil(skipper.reached(position: 22.5, rate: 1))
    XCTAssertNotNil(skipper.reached(position: 22.5, rate: 2))
  }

  // MARK: Saved files and the counter

  func testTheSilenceFileRoundTripsAndChecksTheFile() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = SilenceStore(folder: folder, sha256: "abc")
    XCTAssertNil(store.load())
    let file = SilenceFile(sha256: "abc", duration: 60, gaps: gaps)
    try store.save(file)
    XCTAssertEqual(store.url.lastPathComponent, "abc.silence.json")
    XCTAssertEqual(store.load(), file)
    XCTAssertNil(SilenceStore(folder: folder, sha256: "other").load())
    try Data("nope".utf8).write(to: store.url)
    XCTAssertNil(store.load())
  }

  func testTheCounterAddsOnlyRealSeconds() {
    var savings = TrimSavings(seconds: -3)
    XCTAssertEqual(savings.seconds, 0)
    savings.add(2.5)
    savings.add(.nan)
    savings.add(-1)
    savings.add(1)
    XCTAssertEqual(savings.seconds, 3.5)
  }
}
