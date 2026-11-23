import XCTest

@testable import PodcastAds

/// Which ads the pull-back of a late start may apply to: only those found from the transcript's
/// words, and only by a finder the rule knows by name.
final class JointPullSourcesTests: XCTestCase {
  func testTheWordFindersMayPull() {
    for name in [ShowTuning.repeatWords, ShowTuning.meaning, "word-model"] {
      XCTAssertTrue(JointPull.allows(source: name), name)
    }
  }

  func testNothingElseMayPull() {
    // Sound finders, the listener's answers, and a name the rule does not know.
    for name in [
      ShowTuning.ownSound, ShowTuning.repeatSound, AdAsking.source, "known-ad", "apple", "chapter",
      "", "something-new",
    ] {
      XCTAssertFalse(JointPull.allows(source: name), name)
    }
  }

  func testAnAdWithNoSourceMayNotPullWhenNoWordListIsGiven() {
    XCTAssertFalse(JointPull.allows(source: nil))
    XCTAssertFalse(JointPull.allows(ad(100, nil), words: []))
  }

  // MARK: With the list of the word finders' ads

  func testAnAdWithNoSourceMayPullWhenAWordAdOfItsKindStartsThere() {
    XCTAssertTrue(JointPull.allows(ad(100, nil), words: [ad(100, nil)]))
    XCTAssertTrue(JointPull.allows(ad(100, nil), words: [ad(50, nil), ad(100.0000001, nil)]))
  }

  func testAnAdWithNoSourceMayNotPullWhenNoWordAdStartsThereOrTheKindDiffers() {
    XCTAssertFalse(JointPull.allows(ad(100, nil), words: [ad(100.5, nil), ad(40, nil)]))
    var promo = ad(100, nil)
    promo.kind = .promo
    XCTAssertFalse(JointPull.allows(ad(100, nil), words: [promo]))
  }

  func testANamedSourceNeedsNoWordsAndOtherNamesNeverPull() {
    XCTAssertTrue(JointPull.allows(ad(100, ShowTuning.meaning), words: []))
    for name in ["own-sound", "repeat-sound", "tap", "known-ad"] {
      XCTAssertFalse(JointPull.allows(ad(100, name), words: [ad(100, nil)]), name)
    }
  }

  func testAJoinedAdKeepsTheWordAdsStartOnlyWhenTheWordAdStartsFirst() {
    let word = ad(100, nil)
    var later = ad(110, nil)
    later.end = 160
    XCTAssertTrue(JointPull.allows(AdJoin.join([word, later])[0], words: [word]))
    var earlier = ad(80, nil)
    earlier.end = 120
    let joined = AdJoin.join([word, earlier])
    XCTAssertEqual(joined.count, 1)
    XCTAssertFalse(JointPull.allows(joined[0], words: [word]))
  }

  private func ad(_ start: Double, _ source: String?) -> FoundAd {
    var one = foundAd(start, start + 30)
    one.source = source
    return one
  }

  func testTheScorerHandsTheWordListToTheSaySoOfEachSpan() {
    var byStart: [Double: Bool] = [:]
    let ads = [ad(100, nil), ad(200, nil), ad(300, "known-ad"), ad(400, ShowTuning.meaning)]
    _ = ScoreAds.moved(ads, words: [ad(100, nil), ad(300, nil)]) { spans in
      for span in spans { byStart[span.start] = span.mayPull }
      return spans
    }
    XCTAssertEqual(byStart, [100: true, 200: false, 300: false, 400: true])
  }

  func testTheScorerHandsTheSaySoToTheMoveOfEachSpan() {
    var byStart: [Double: Bool] = [:]
    _ = ScoreAds.moved([ad(300, nil), ad(100, ShowTuning.repeatWords), ad(200, ShowTuning.ownSound)]) {
      spans in
      for span in spans { byStart[span.start] = span.mayPull }
      return spans
    }
    XCTAssertEqual(byStart, [100: true, 200: false, 300: false])
  }
}

/// The joint rows with the list of the word finders' ads: only an ad whose start a word finder
/// gave is pulled back to a joint.
final class JointPullRowsTests: XCTestCase {
  private let episode = scoreEpisode(id: "e1", feed: "fa")

  private func input() -> AdScoreInput {
    AdScoreInput(episode: episode, transcript: episode.transcript, audio: URL(fileURLWithPath: "/a.mp3"))
  }

  /// A snap that moves a start 5 s earlier only when the span may be pulled.
  private let pulling: @Sendable (URL, [ScoreSpan], Bool) -> [ScoreSpan] = { _, spans, _ in
    spans.map {
      ScoreSpan(start: $0.mayPull ? $0.start - 5 : $0.start, end: $0.end, sort: $0.sort)
    }
  }

  private func known(_ start: Double) -> FoundAd {
    var one = foundAd(start, start + 30)
    one.source = "known-ad"
    return one
  }

  func testTheSteadyRowPullsAWordAdsStartButNotALibraryAdOrAnAdOutsideTheWords() {
    let words: ScoreWords = { _ in [foundAd(100, 130)] }
    let layer = SoundScoreLayers.steadyJoints(pulling, stash: ScoreEpisodeAds(), words: words)
    let row = layer.apply(input(), soFar: [foundAd(100, 130), known(200), foundAd(300, 330)])
    XCTAssertEqual(row.map(\.start), [95, 200, 300])
  }

  func testTheJointsRowGetsNoPullWithNoWordList() {
    let layer = SoundScoreLayers.joints(pulling, stash: ScoreEpisodeAds())
    XCTAssertEqual(layer.apply(input(), soFar: [foundAd(100, 130)]).map(\.start), [100])
  }

  func testTheSettingsRowPullsAWordAdsStart() {
    let tuning = ShowTuning(
      text: #"{"version": 1, "default": {"joints": true, "steadyJoints": true}, "shows": []}"#)
    let words: ScoreWords = { _ in [foundAd(100, 130)] }
    let layer = SettingsScoreLayer.perShowSettings(
      tuning: tuning, finders: ScoreFinderAds(), snap: pulling, words: words)
    let row = layer.apply(input(), soFar: [foundAd(100, 130), known(200)])
    XCTAssertEqual(row.map(\.start), [95, 200])
  }
}
