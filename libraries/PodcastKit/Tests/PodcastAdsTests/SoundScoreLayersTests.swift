import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// A record of what a fake sound finder was asked, kept for the test to read.
final class SoundCalls: @unchecked Sendable {
  private let lock = NSLock()
  private var asked: [String] = []
  private var flags: [Bool] = []
  private var learned: [[ScoreSpan]] = []

  func ask(_ what: String, steadyToo: Bool = false, learn: [ScoreSpan] = []) {
    lock.lock()
    defer { lock.unlock() }
    asked.append(what)
    flags.append(steadyToo)
    learned.append(learn)
  }

  var all: [String] { lock.lock(); defer { lock.unlock() }; return asked }
  var steady: [Bool] { lock.lock(); defer { lock.unlock() }; return flags }
  var learn: [[ScoreSpan]] { lock.lock(); defer { lock.unlock() }; return learned }
}

/// The rows that need an episode's audio, with sound finders that are made up: each answers from
/// a table, so the layers' own work (what they hand over, trimming, naming, the head) is what is
/// tested.
final class SoundScoreLayersTests: XCTestCase {
  private let audio = URL(fileURLWithPath: "/teaching/audio/e1.mp3")

  private func input(_ episode: TeachingEpisode, audio: URL?, head: Double? = nil) -> AdScoreInput {
    let transcript = head.map { AdScoreRun.head(of: episode.transcript, seconds: $0) } ?? episode.transcript
    return AdScoreInput(episode: episode, transcript: transcript, audio: audio)
  }

  private func spans(_ ads: [FoundAd]) -> [[Double]] { ads.map { [$0.start, $0.end] } }

  // MARK: The phone's own sounds

  func testTheOwnSoundsRowAddsUnsureAdsOfItsOwnNameAndLearnsFromTheSureOnes() throws {
    let calls = SoundCalls()
    let layer = SoundScoreLayers.ownSounds { url, show, episode, learn in
      calls.ask("\(url.lastPathComponent) \(show) \(episode)", learn: learn)
      return [ScoreSpan(start: 200, end: 230, sort: "network_promo")]
    }
    XCTAssertEqual(layer.name, "Plus the phone's own sounds")
    XCTAssertFalse(layer.rewrites)
    let episode = scoreEpisode(id: "e1", feed: "fa")
    let soFar = [foundAd(10, 40), foundAd(60, 80, kind: .promo, .unsure)]
    let row = layer.apply(input(episode, audio: audio), soFar: soFar)
    XCTAssertEqual(spans(row), [[10, 40], [60, 80], [200, 230]])
    let added = try XCTUnwrap(row.last)
    XCTAssertEqual(added.source, "own-sound")
    XCTAssertEqual(added.source, ShowTuning.ownSound)
    XCTAssertEqual(added.confidence, .unsure)
    XCTAssertEqual(added.kind, .promo)
    // It learns from the sure ad only, and was asked about this show and this episode.
    XCTAssertEqual(calls.all, ["e1.mp3 fa e1"])
    XCTAssertEqual(calls.learn.first?.map { [$0.start, $0.end] }, [[10, 40]])
  }

  func testAnEpisodeWithNoAudioIsLeftAsItWas() {
    let calls = SoundCalls()
    let layer = SoundScoreLayers.ownSounds { _, _, _, _ in
      calls.ask("asked")
      return [ScoreSpan(start: 200, end: 230)]
    }
    let soFar = [foundAd(10, 40)]
    XCTAssertEqual(layer.apply(input(scoreEpisode(), audio: nil), soFar: soFar), soFar)
    XCTAssertEqual(calls.all, [])
  }

  func testWhatTouchesAnOlderAdIsCutBackSoTheOlderAdIsNeverLengthened() {
    let layer = SoundScoreLayers.ownSounds { _, _, _, _ in
      [ScoreSpan(start: 100, end: 160), ScoreSpan(start: 30, end: 39)]
    }
    let old = foundAd(110, 130)
    let row = layer.apply(input(scoreEpisode(), audio: audio), soFar: [old])
    XCTAssertEqual(spans(row), [[110, 130], [131, 160]])
    XCTAssertEqual(row.first { $0.confidence == .sure }.map { [$0.start, $0.end] }, [110, 130])
  }

  func testTheFirstLookAnswersFromTheWholeEpisode() {
    let calls = SoundCalls()
    let layer = SoundScoreLayers.ownSounds { _, _, _, _ in
      calls.ask("scan")
      return [ScoreSpan(start: 2, end: 20), ScoreSpan(start: 300, end: 340)]
    }
    let episode = scoreEpisode()
    _ = layer.apply(input(episode, audio: audio), soFar: [])
    let first = layer.apply(input(episode, audio: audio, head: 30), soFar: [])
    // The audio is read once. The look at the first 30 seconds keeps what ends by then.
    XCTAssertEqual(calls.all, ["scan"])
    XCTAssertEqual(spans(first), [[2, 20]])
  }

  // MARK: Repeated sounds

  func testTheRepeatedSoundsRowNamesItsAdsAndAsksForTheShowAndEpisode() {
    let calls = SoundCalls()
    let layer = SoundScoreLayers.repeatedSounds { _, show, episode in
      calls.ask("\(show) \(episode)")
      return [ScoreSpan(start: 90, end: 140)]
    }
    XCTAssertEqual(layer.name, "Plus repeated sounds")
    let row = layer.apply(input(scoreEpisode(id: "e7", feed: "fb"), audio: audio), soFar: [])
    XCTAssertEqual(calls.all, ["fb e7"])
    XCTAssertEqual(row.first?.source, "repeat-sound")
    XCTAssertEqual(row.first?.source, ShowTuning.repeatSound)
    XCTAssertEqual(row.first?.kind, .ad)
    XCTAssertEqual(row.first?.confidence, .unsure)
    XCTAssertEqual(layer.apply(input(scoreEpisode(), audio: nil), soFar: []), [])
  }

  func testStretchesThatAreTooShortOrTooLongForAnAdGiveNothing() {
    let layer = SoundScoreLayers.repeatedSounds { _, _, _ in
      [ScoreSpan(start: 90, end: 99), ScoreSpan(start: 400, end: 800)]
    }
    XCTAssertEqual(layer.apply(input(scoreEpisode(), audio: audio), soFar: []), [])
  }

  // MARK: Joints

  /// A snap that moves every start 1 s earlier and every end 2 s later.
  private func widen(_ calls: SoundCalls) -> @Sendable (URL, [ScoreSpan], Bool) -> [ScoreSpan] {
    { url, spans, steadyToo in
      calls.ask(url.lastPathComponent, steadyToo: steadyToo)
      return spans.map { ScoreSpan(start: $0.start - 1, end: $0.end + 2, sort: $0.sort) }
    }
  }

  func testTheJointsRowReturnsTheWholeListWithTheBordersMoved() {
    let calls = SoundCalls()
    let layer = SoundScoreLayers.joints(widen(calls), stash: ScoreEpisodeAds())
    XCTAssertEqual(layer.name, "Plus joints")
    XCTAssertTrue(layer.rewrites)
    let soFar = [foundAd(100, 130, kind: .ad, .sure), foundAd(300, 320, kind: .promo, .unsure)]
    let row = layer.apply(input(scoreEpisode(), audio: audio), soFar: soFar)
    XCTAssertEqual(spans(row), [[99, 132], [299, 322]])
    XCTAssertEqual(calls.steady, [false])
    XCTAssertEqual(row.map(\.confidence), [.sure, .unsure])
  }

  func testTheJointsRowChangesNothingWithoutAudioOrOnTheFirstLook() {
    let calls = SoundCalls()
    let layer = SoundScoreLayers.joints(widen(calls), stash: ScoreEpisodeAds())
    let soFar = [foundAd(100, 130)]
    XCTAssertEqual(layer.apply(input(scoreEpisode(), audio: nil), soFar: soFar), soFar)
    XCTAssertEqual(layer.apply(input(scoreEpisode(), audio: audio, head: 50), soFar: soFar), soFar)
    XCTAssertEqual(calls.all, [])
    // And it never wipes the row: no ads in, no ads out.
    XCTAssertEqual(layer.apply(input(scoreEpisode(), audio: audio), soFar: []), [])
  }

  func testTheSteadyRowSnapsTheAdsFromBeforeTheJointsRowAsAnAlternative() {
    let calls = SoundCalls()
    let stash = ScoreEpisodeAds()
    let joints = SoundScoreLayers.joints(widen(calls), stash: stash)
    let steady = SoundScoreLayers.steadyJoints(widen(calls), stash: stash)
    XCTAssertEqual(steady.name, "Plus joints (steady files too)")
    XCTAssertTrue(steady.rewrites)
    let episode = scoreEpisode()
    let before = [foundAd(100, 130)]
    let afterJoints = joints.apply(input(episode, audio: audio), soFar: before)
    XCTAssertEqual(spans(afterJoints), [[99, 132]])
    XCTAssertEqual(stash.ads(for: episode.id), before)
    // The steady row stands on the row before it, but moves the ads as they were before the
    // joints row, not the ones it already moved: 99 and 132 would become 98 and 134.
    let afterSteady = steady.apply(input(episode, audio: audio), soFar: afterJoints)
    XCTAssertEqual(spans(afterSteady), [[99, 132]])
    XCTAssertEqual(calls.steady, [false, true])
  }

  func testTheSteadyRowStandsOnTheRowBeforeWhenTheJointsRowDidNotRun() {
    let calls = SoundCalls()
    let steady = SoundScoreLayers.steadyJoints(widen(calls), stash: ScoreEpisodeAds())
    let row = steady.apply(input(scoreEpisode(), audio: audio), soFar: [foundAd(100, 130)])
    XCTAssertEqual(spans(row), [[99, 132]])
    XCTAssertEqual(calls.steady, [true])
  }

  // MARK: What the settings row starts from

  func testAFinderRowKeepsItsOwnAdsCutAgainstTheOlderFindersOnlyAndHandsOnTheCutRow() {
    let finders = ScoreFinderAds()
    let layer = SoundScoreLayers.ownSounds(
      { _, _, _, _ in [ScoreSpan(start: 100, end: 200)] }, finders: finders)
    let episode = scoreEpisode(id: "e1", feed: "fa")
    let base = [foundAd(90, 110)]
    _ = finders.baseRow.apply(input(episode, audio: audio), soFar: base)
    // An earlier new finder holds 130 to 145 in the row before.
    let before = base + [foundAd(130, 145, .unsure)]
    let row = layer.apply(input(episode, audio: audio), soFar: before)
    // Its own list loses only what the older finders have; the row loses what the row before has.
    XCTAssertEqual(spans(finders.ads(finder: "own-sound", for: "e1")), [[111, 200]])
    XCTAssertEqual(spans(row), [[90, 110], [111, 129], [130, 145], [146, 200]])
  }

  func testTheFirstLookKeepsNothingForTheSettingsRow() {
    let finders = ScoreFinderAds()
    let layer = SoundScoreLayers.repeatedSounds({ _, _, _ in [ScoreSpan(start: 100, end: 200)] }, finders: finders)
    let episode = scoreEpisode(id: "e1", feed: "fa")
    _ = layer.apply(input(episode, audio: audio, head: 50), soFar: [])
    XCTAssertEqual(finders.ads(finder: "repeat-sound", for: "e1"), [])
    _ = layer.apply(input(episode, audio: audio), soFar: [])
    XCTAssertEqual(spans(finders.ads(finder: "repeat-sound", for: "e1")), [[100, 200]])
  }
}
