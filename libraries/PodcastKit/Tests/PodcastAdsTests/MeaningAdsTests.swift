import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

final class MeaningAdsTests: XCTestCase {
  private let model = AdMeaningModel(data: Made.file())!

  /// Twelve lines of ten seconds: lines 4 to 8 ask for a favour, the rest are plain talk.
  private var texts: [String] {
    (1...12).map { number -> String in
      let even = number % 2 == 0
      if (4...8).contains(number) { return even ? Made.ask : Made.ask2 }
      return even ? Made.talk : Made.talk2
    }
  }

  func testASpanBecomesAnUnsureAdWithItsSource() throws {
    let transcript = makeTranscript(texts)
    let embedder = Made.embedder()
    // The model is sure of this span (so the plain decoder says "sure")...
    let lines = AdChunker.number(transcript.lines)
    let spans = model.spans(lines: lines, duration: nil, embedder: embedder)
    XCTAssertEqual(spans.count, 1)
    XCTAssertTrue(spans[0].sure)
    // ...and the finder still never says more than "unsure".
    let ads = MeaningAds.find(model: model, transcript: transcript, embedder: embedder)
    XCTAssertEqual(ads.count, 1)
    let ad = try XCTUnwrap(ads.first)
    XCTAssertEqual(ad.source, "meaning")
    XCTAssertEqual(ad.confidence, .unsure)
    XCTAssertEqual(ad.kind, .ownPlug)  // the model's "host_ask"
    XCTAssertEqual(ad.start, 30, accuracy: 1.5)
    XCTAssertEqual(ad.end, 79, accuracy: 3)
  }

  func testTheRunKeepsTheRowsAndTheState() {
    let transcript = makeTranscript(texts)
    let run = MeaningAds.run(model: model, transcript: transcript, embedder: Made.embedder())
    XCTAssertEqual(run.state, .ready)
    XCTAssertEqual(run.rows.count, 12)
    // The rows are in the order of the transcript's lines, so a caller can pick the middle band.
    XCTAssertGreaterThan(run.rows[5][3], 0.9)
    XCTAssertGreaterThan(run.rows[0][0], 0.9)
    XCTAssertEqual(run.ads.count, 1)
    XCTAssertNotNil(run.secondsPerLine)
  }

  func testPlainTalkGivesNoAds() {
    let transcript = makeTranscript((1...12).map { $0 % 2 == 0 ? Made.talk : Made.talk2 })
    XCTAssertEqual(MeaningAds.find(model: model, transcript: transcript, embedder: Made.embedder()), [])
  }

  func testALayerThatIsOffFindsNothingAndSaysWhy() {
    let transcript = makeTranscript(texts)
    let run = MeaningAds.run(model: model, transcript: transcript, embedder: Made.embedder(revision: 9))
    XCTAssertEqual(run.ads, [])
    XCTAssertEqual(run.rows, [])
    guard case .off(let why) = run.state else { return XCTFail("should be off") }
    XCTAssertFalse(why.isEmpty)
    XCTAssertEqual(MeaningAds.find(model: model, transcript: transcript, embedder: Made.embedder(revision: 9)), [])
  }

  func testASlowPhoneFindsNothing() {
    let clock = FakeClock()
    let embedder = Made.embedder()
    embedder.onCall { clock.advance(0.05) }
    let run = MeaningAds.run(
      model: model, transcript: makeTranscript(texts), embedder: embedder, clock: clock.now)
    XCTAssertEqual(run.ads, [])
    guard case .off = run.state else { return XCTFail("should give up") }
  }

  func testAnEmptyTranscriptHasNoAds() {
    let identity = TranscriptIdentity(
      locale: "en-US", recogniser: "t", recogniserVersion: "1", osVersion: "", sha256: "")
    let empty = Transcript(identity: identity, duration: 0, lines: [], words: [])
    let run = MeaningAds.run(model: model, transcript: empty, embedder: Made.embedder())
    XCTAssertEqual(run.ads, [])
    XCTAssertEqual(run.rows, [])
    XCTAssertEqual(run.state, .ready)
  }

  func testTheFinderNeverTouchesWhatTheOldLayersFind() {
    // The finder is its own function: the result of LocalAds does not depend on it.
    let transcript = makeTranscript(texts)
    let before = LocalAds(model: nil).ads(transcript: transcript)
    _ = MeaningAds.find(model: model, transcript: transcript, embedder: Made.embedder())
    XCTAssertEqual(LocalAds(model: nil).ads(transcript: transcript), before)
    XCTAssertTrue(before.allSatisfy { $0.source == nil })
  }
}
