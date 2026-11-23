import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// "Plus per-show settings": the Mac's show-settings.json applied to the ads of the rows before.
final class SettingsScoreLayerTests: XCTestCase {
  private let audio = URL(fileURLWithPath: "/teaching/audio/e1.mp3")

  private func input(feed: String, audio: URL?, head: Double? = nil) -> AdScoreInput {
    let episode = scoreEpisode(id: "e1", feed: feed)
    let transcript = head.map { AdScoreRun.head(of: episode.transcript, seconds: $0) } ?? episode.transcript
    return AdScoreInput(episode: episode, transcript: transcript, audio: audio)
  }

  private func ad(
    _ start: Double, _ end: Double, source: String?, kind: AdKind = .ad,
    _ confidence: AdConfidence = .unsure
  ) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: kind, advertiser: "", confidence: confidence, firstWords: "",
      source: source)
  }

  private func spans(_ ads: [FoundAd]) -> [[Double]] { ads.map { [$0.start, $0.end] } }

  /// The settings: own sounds ask and repeated sounds are off everywhere, own sounds may skip on
  /// show "fa", host asks only ask on "fb", and joints are off on "fc".
  private let tuning = ShowTuning(
    text: """
      {"version": 1, "default": {"finders": {"own-sound": "ask", "repeat-sound": "off"}},
       "shows": [
         {"feed": "fa", "finders": {"own-sound": "skip"}},
         {"feed": "fb", "sorts": {"host_ask": "ask"}},
         {"feed": "fc", "joints": false}]}
      """)

  private var soFar: [FoundAd] {
    [
      ad(10, 40, source: nil, .sure), ad(60, 90, source: "own-sound"),
      ad(100, 130, source: "repeat-sound"), ad(140, 170, source: "meaning"),
      ad(180, 200, source: nil, kind: .ownPlug, .sure),
    ]
  }

  private func layer(
    _ tuning: ShowTuning, stash: ScoreEpisodeAds = ScoreEpisodeAds(),
    snap: (@Sendable (URL, [ScoreSpan], Bool) -> [ScoreSpan])? = nil
  ) -> AdScoreLayer {
    SettingsScoreLayer.perShowSettings(tuning: tuning, stash: stash, snap: snap)
  }

  func testTheRowRewritesTheListWithWhatTheSettingsLetSkip() {
    let row = layer(tuning)
    XCTAssertEqual(row.name, "Plus per-show settings")
    XCTAssertTrue(row.rewrites)
    // On a show with no entry of its own: own sounds only ask and repeated sounds are off, so
    // the older finders' ads and the meaning model's stay.
    let other = row.apply(input(feed: "fz", audio: nil), soFar: soFar)
    XCTAssertEqual(spans(other), [[10, 40], [140, 170], [180, 200]])
    // On "fa" own sounds may skip.
    let fa = row.apply(input(feed: "fa", audio: nil), soFar: soFar)
    XCTAssertEqual(spans(fa), [[10, 40], [60, 90], [140, 170], [180, 200]])
  }

  func testASortThatOnlyAsksLeavesTheSkipsEvenOfAnOlderFinder() {
    let fb = layer(tuning).apply(input(feed: "fb", audio: nil), soFar: soFar)
    XCTAssertEqual(spans(fb), [[10, 40], [140, 170]])
  }

  func testWithNoFileEveryFinderIsAtItsBuiltInLevel() {
    // Built in: own sounds and the meaning model skip, the two repeat finders only ask.
    let row = layer(ShowTuning()).apply(input(feed: "fz", audio: nil), soFar: soFar)
    XCTAssertEqual(spans(row), [[10, 40], [60, 90], [140, 170], [180, 200]])
  }

  func testTheFirstLookAppliesTheSettingsToWhatItWasGiven() {
    let head = layer(tuning).apply(input(feed: "fz", audio: audio, head: 60), soFar: soFar)
    XCTAssertEqual(spans(head), [[10, 40], [140, 170], [180, 200]])
  }

  func testAnEmptyListStaysEmpty() {
    XCTAssertEqual(layer(tuning).apply(input(feed: "fz", audio: audio), soFar: []), [])
  }

  // MARK: Joints

  /// A snap that moves every start 1 s earlier and every end 2 s later, and says what it was told.
  private func widen(_ calls: SoundCalls) -> @Sendable (URL, [ScoreSpan], Bool) -> [ScoreSpan] {
    { url, spans, steadyToo in
      calls.ask(url.lastPathComponent, steadyToo: steadyToo)
      return spans.map { ScoreSpan(start: $0.start - 1, end: $0.end + 2, sort: $0.sort) }
    }
  }

  func testWhereJointsAreOnTheSettingsStartFromTheAdsBeforeTheJointsRowAndSnapThem() {
    let calls = SoundCalls()
    let stash = ScoreEpisodeAds()
    stash.put(soFar, for: "e1")
    // What the joints row handed on is not what the settings start from.
    let moved = soFar.map { ad($0.start - 5, $0.end + 5, source: $0.source) }
    let row = layer(tuning, stash: stash, snap: widen(calls)).apply(
      input(feed: "fa", audio: audio), soFar: moved)
    XCTAssertEqual(spans(row), [[9, 42], [59, 92], [139, 172], [179, 202]])
    // Joints are on by default and steady files are not used by default.
    XCTAssertEqual(calls.steady, [false])
  }

  func testWhereJointsAreOffTheAdsAreNotMovedAndTheJointsRowIsUndone() {
    let calls = SoundCalls()
    let stash = ScoreEpisodeAds()
    stash.put(soFar, for: "e1")
    let moved = soFar.map { ad($0.start - 5, $0.end + 5, source: $0.source) }
    let row = layer(tuning, stash: stash, snap: widen(calls)).apply(
      input(feed: "fc", audio: audio), soFar: moved)
    XCTAssertEqual(spans(row), [[10, 40], [140, 170], [180, 200]])
    XCTAssertEqual(calls.all, [])
  }

  func testSteadyFilesAreUsedOnlyWhereTheSettingsSay() {
    let steady = ShowTuning(
      text: "{\"version\": 1, \"default\": {\"steadyJoints\": true}, \"shows\": [{\"feed\": \"fb\", \"steadyJoints\": false}]}")
    let calls = SoundCalls()
    let row = layer(steady, snap: widen(calls))
    _ = row.apply(input(feed: "fa", audio: audio), soFar: [ad(10, 40, source: nil, .sure)])
    _ = row.apply(input(feed: "fb", audio: audio), soFar: [ad(10, 40, source: nil, .sure)])
    XCTAssertEqual(calls.steady, [true, false])
  }

  func testWithoutAudioNothingIsSnapped() {
    let calls = SoundCalls()
    let row = layer(tuning, snap: widen(calls)).apply(
      input(feed: "fa", audio: nil), soFar: [ad(10, 40, source: nil, .sure)])
    XCTAssertEqual(spans(row), [[10, 40]])
    XCTAssertEqual(calls.all, [])
  }
}
