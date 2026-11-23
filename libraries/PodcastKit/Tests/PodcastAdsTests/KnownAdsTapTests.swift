import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// `learnTapped` remembers the one stretch the listener said "yes" to, and only that one.
final class KnownAdsTapTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  /// The words of one 60-word ad, such as "spot0 spot1 ... spot59" (30 s at two words a second).
  private func words(_ name: String, _ count: Int = 60) -> [String] { (0..<count).map { "\(name)\($0)" } }

  private func timed(_ texts: [String]) -> [TranscriptWord] {
    texts.enumerated().map {
      TranscriptWord(text: $0.element, start: Double($0.offset) * 0.5, end: Double($0.offset + 1) * 0.5)
    }
  }

  /// An episode of talk, then ad A (15 s to 45 s), talk, ad B (60 s to 90 s) and talk.
  private var texts: [String] {
    words("talk", 30) + words("spot") + words("chat", 30) + words("plug") + words("more", 30)
  }

  private var transcript: Transcript {
    let all = texts
    return Transcript(
      identity: TranscriptIdentity(
        locale: "en-US", recogniser: "Fake", recogniserVersion: "1", osVersion: "26.0", sha256: "aa"),
      duration: Double(all.count) * 0.5, lines: [], words: timed(all))
  }

  private func ad(_ start: Double, _ end: Double, _ confidence: AdConfidence = .sure) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "Acme", confidence: confidence,
      firstWords: "", source: "tap")
  }

  private func file(_ ads: [FoundAd]) -> AdsFile {
    AdsFile(
      sha256: "aa", detector: "fake", detectorVersion: "1", osVersion: "26.0", duration: 120, ads: ads)
  }

  func testOneConfirmedStretchIsRemembered() {
    var known = KnownAds()
    // The question as it was asked: a guess. The listener's "yes" makes it sure.
    let changed = known.learnTapped(
      ad(60, 90, .guess), transcript: transcript, show: "show", now: now)
    XCTAssertTrue(changed)
    XCTAssertEqual(known.ads.count, 1)
    let learned = known.ads[0]
    XCTAssertEqual(learned.words, words("plug"))
    XCTAssertEqual(learned.showId, "show")
    XCTAssertEqual(learned.advertiser, "Acme")
    XCTAssertEqual(learned.kind, .ad)
    XCTAssertEqual(learned.length, 30)
    XCTAssertEqual(learned.seen, 1)
    XCTAssertEqual(learned.lastSeen, now)
  }

  func testAnAdThatIsAlreadySureIsRememberedTheSameWay() {
    var known = KnownAds()
    known.learnTapped(ad(60, 90, .sure), transcript: transcript, show: "show", now: now)
    XCTAssertEqual(known.ads.first?.words, words("plug"))
  }

  func testTheRememberedStretchIsFoundAgainInItsShowOnly() {
    var known = KnownAds()
    known.learnTapped(ad(60, 90), transcript: transcript, show: "show", now: now)
    let hits = known.find(in: transcript.words, show: "show")
    XCTAssertEqual(hits.count, 1)
    XCTAssertEqual(hits.first?.match.start, 60)
    XCTAssertEqual(known.find(in: transcript.words, show: "other").count, 0)
  }

  func testTheFilesOtherAdsAreNotCountedAgain() {
    // Ad A was learned when the file was finished. The listener now confirms B.
    var known = KnownAds()
    known.learn(from: file([ad(15, 45)]), transcript: transcript, show: "show", now: now)
    XCTAssertEqual(known.ads.map(\.seen), [1])
    let later = now.addingTimeInterval(86_400)
    known.learnTapped(ad(60, 90), transcript: transcript, show: "show", now: later)
    XCTAssertEqual(known.ads.count, 2)
    let a = known.ads.first { $0.words == words("spot") }
    let b = known.ads.first { $0.words == words("plug") }
    XCTAssertEqual(a?.seen, 1, "A is not counted a second time")
    XCTAssertEqual(a?.lastSeen, now, "and not touched")
    XCTAssertEqual(b?.seen, 1)
    XCTAssertEqual(b?.lastSeen, later)

    // The reason: learning from the whole file again counts A again.
    var whole = KnownAds()
    whole.learn(from: file([ad(15, 45)]), transcript: transcript, show: "show", now: now)
    whole.learn(from: file([ad(15, 45), ad(60, 90)]), transcript: transcript, show: "show", now: later)
    XCTAssertEqual(whole.ads.first { $0.words == words("spot") }?.seen, 2)
  }

  func testTheSameWordsAgainAreOneEntryThatWasSeenTwice() {
    var known = KnownAds()
    known.learnTapped(ad(60, 90), transcript: transcript, show: "show", now: now)
    known.learnTapped(ad(60, 90), transcript: transcript, show: "show", now: now.addingTimeInterval(60))
    XCTAssertEqual(known.ads.count, 1, "never two entries for one stretch")
    XCTAssertEqual(known.ads.first?.seen, 2, "each call is one sighting: ask it once for each answer")
  }

  func testAStretchThatTheMemoryWouldNotKeepIsNotRemembered() {
    var known = KnownAds()
    // 12 s is shorter than the shortest ad the memory keeps (15 s).
    XCTAssertFalse(known.learnTapped(ad(60, 72), transcript: transcript, show: "show", now: now))
    // A stretch with no words: past the end of the transcript.
    XCTAssertFalse(known.learnTapped(ad(500, 540), transcript: transcript, show: "show", now: now))
    XCTAssertFalse(known.learnTapped(ad(.nan, .nan), transcript: transcript, show: "show", now: now))
    XCTAssertTrue(known.ads.isEmpty)
  }
}
