import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// A replay that the recogniser heard a little differently each time, so that it comes in pieces;
/// what other finders named already; and a phrase that only comes back now and then.
final class RepeatedWordsReplayTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func heard(_ words: [String], as id: String = "old") -> RepeatedWords {
    var memory = RepeatedWords()
    memory.remember(show: "show", episode: id, lines: Speech.lines(words), now: now)
    return memory
  }

  private func find(
    _ memory: RepeatedWords, _ words: [String], already: [FoundAd] = []
  ) -> [FoundAd] {
    memory.find(
      show: "show", episode: "new", lines: Speech.lines(words), duration: Speech.seconds(words),
      now: now, already: already)
  }

  /// `passage` with four words in a row changed at each of the `places`.
  private func differing(_ passage: [String], at places: [Int]) -> [String] {
    var changed = passage
    for place in places { for k in 0..<4 { changed[place + k] = "diff\(place + k)" } }
    return changed
  }

  // MARK: Replays that come in pieces

  func testALongReplayInPiecesIsNotOfferedPieceByPiece() {
    // 450 seconds of one replayed passage, heard differently every 100 seconds: five pieces of
    // about 100 seconds, each a few seconds from the next. Together they are over 300 seconds.
    let passage = Speech.plug(900, tag: "replay")
    let old = Speech.episode(tag: "old", total: 4000, plugs: [(400, passage)])
    let changed = differing(passage, at: [200, 400, 600, 800])
    let new = Speech.episode(tag: "new", total: 4000, plugs: [(1500, changed)])
    XCTAssertEqual(find(heard(old), new), [])
  }

  func testAReplayUnderThreeHundredSecondsInTwoPiecesIsOfferedInTwo() {
    let passage = Speech.plug(500, tag: "replay")
    let old = Speech.episode(tag: "old", total: 4000, plugs: [(400, passage)])
    let new = Speech.episode(
      tag: "new", total: 4000, plugs: [(1500, differing(passage, at: [250]))])
    let found = find(heard(old), new)
    XCTAssertEqual(found.count, 2)
    XCTAssertEqual(found.first?.start ?? 0, Speech.time(ofWord: 1500), accuracy: 5)
    XCTAssertEqual(found.last?.end ?? 0, Speech.time(ofWord: 2000), accuracy: 5)
  }

  func testPiecesApartAreNotOneReplay() {
    // Two passages of 250 seconds with 160 seconds of new talk between them are not one replay of
    // 660 seconds, so each is offered.
    let first = Speech.plug(500, tag: "first")
    let second = Speech.plug(500, tag: "second")
    let old = Speech.episode(tag: "old", total: 4000, plugs: [(400, first), (1500, second)])
    let new = Speech.episode(tag: "new", total: 4000, plugs: [(300, first), (1120, second)])
    XCTAssertEqual(find(heard(old), new).count, 2)
  }

  func testARebroadcastIsNotOfferedInPieces() {
    // 1200 seconds of new talk, then 2400 seconds of an older episode, heard differently every
    // 200 seconds in its first 1000 seconds. Two thirds of the episode repeats.
    let body = Speech.talk(4800, tag: "body")
    let replay = differing(body, at: [400, 800, 1200, 1600])
    let new = Speech.talk(2400, tag: "fresh") + replay
    XCTAssertEqual(find(heard(body), new), [])
  }

  // MARK: What others named

  func testTimeThatOtherFindersNamedIsNotCountedAsARerun() {
    // 600 seconds: four ads of 50 seconds that others found (they repeat too), and a repeated
    // promo of 30 seconds that nobody found. Without the named ads the repeat is 5% of the
    // episode, so the promo is offered.
    let ads = (0..<4).map { Speech.plug(100, tag: "ad\($0)x") }
    let promo = Speech.plug(60, tag: "promo")
    var old = Speech.talk(1200, tag: "old")
    var new = Speech.talk(1200, tag: "new")
    for (n, at) in [150, 350, 550, 750].enumerated() {
      old.replaceSubrange(at..<(at + 100), with: ads[n])
      new.replaceSubrange((at + 10)..<(at + 110), with: ads[n])
    }
    old.replaceSubrange(950..<1010, with: promo)
    new.replaceSubrange(960..<1020, with: promo)
    let named = [160, 360, 560, 760].map {
      FoundAd(
        start: Speech.time(ofWord: $0), end: Speech.time(ofWord: $0 + 100), kind: .ad,
        advertiser: "", confidence: .sure, firstWords: "")
    }
    let memory = heard(old)
    let found = find(memory, new, already: named)
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found.first?.start ?? 0, Speech.time(ofWord: 960), accuracy: 5)
    // Nobody named them: now 230 of 600 seconds repeat, and the episode is a re-run.
    XCTAssertEqual(find(memory, new), [])
  }

  // MARK: A phrase that comes back now and then

  func testAFivewordPhraseEveryEightWordsForFortySecondsGivesNothing() {
    // "you know what i mean" after every three other words, in both episodes, ten times (40
    // seconds): one run of five words in every eight is the same. The hits are far apart, so
    // none of them is solid.
    func chatty(_ tag: String) -> [String] {
      (0..<10).flatMap { Speech.talk(3, tag: "\(tag)\($0)x") + ["you", "know", "what", "i", "mean"] }
    }
    let old = Speech.episode(tag: "old", total: 1200, plugs: [(200, chatty("a"))])
    let new = Speech.episode(tag: "new", total: 1200, plugs: [(300, chatty("b"))])
    XCTAssertEqual(find(heard(old), new), [])
  }
}
