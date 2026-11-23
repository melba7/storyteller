import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// What the finder returns: a stretch of a new episode whose words an older episode of the same show
/// had said, as an unsure ad from the finder "repeat-words".
final class RepeatedWordsTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private let show = "show"

  /// A memory that has heard `words` as episode `id` of the show.
  private func heard(
    _ words: [String], as id: String = "old", into memory: RepeatedWords = RepeatedWords()
  ) -> RepeatedWords {
    var memory = memory
    memory.remember(show: show, episode: id, lines: Speech.lines(words), now: now)
    return memory
  }

  private func find(
    _ memory: RepeatedWords, _ words: [String], as id: String = "new", already: [FoundAd] = []
  ) -> [FoundAd] {
    memory.find(
      show: show, episode: id, lines: Speech.lines(words), duration: Speech.seconds(words), now: now,
      already: already)
  }

  private func ad(_ start: Double, _ end: Double) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "", confidence: .sure, firstWords: "")
  }

  // MARK: What is found

  func testFortyWordsRepeatedWithTwoChangedAreFoundWithinOneLineOfTheTruth() {
    let old = Speech.episode(tag: "old", total: 1200, plugs: [(400, Speech.plug(40))])
    let new = Speech.episode(
      tag: "new", total: 1200, plugs: [(903, Speech.plug(40, changed: [10, 25]))])
    let found = find(heard(old), new)
    XCTAssertEqual(found.count, 1)
    guard let ad = found.first else { return }
    let oneLine = Double(Speech.perLine) * Speech.step
    XCTAssertEqual(ad.start, Speech.time(ofWord: 903), accuracy: oneLine)
    XCTAssertEqual(ad.end, Speech.time(ofWord: 943), accuracy: oneLine)
    XCTAssertEqual(ad.source, "repeat-words")
    XCTAssertEqual(ad.confidence, .unsure)
    XCTAssertEqual(ad.kind, .ad)
    XCTAssertEqual(
      ad.firstWords,
      "plug0 plug1 plug2 plug3 plug4 plug5 plug6 plug7 plug8 plug9 other10 plug11 plug12 plug13")
  }

  func testThreeChangedWordsStillFindTheRepeat() {
    let old = Speech.episode(tag: "old", total: 1200, plugs: [(400, Speech.plug(60))])
    let new = Speech.episode(
      tag: "new", total: 1200, plugs: [(700, Speech.plug(60, changed: [14, 15, 40]))])
    XCTAssertEqual(find(heard(old), new).count, 1)
  }

  func testTenWordsRepeatedAreNotFound() {
    let old = Speech.episode(tag: "old", total: 1200, plugs: [(400, Speech.plug(10))])
    let new = Speech.episode(tag: "new", total: 1200, plugs: [(900, Speech.plug(10))])
    XCTAssertEqual(find(heard(old), new), [])
  }

  func testARepeatNeedsTwentyFiveWordsAndFifteenSeconds() {
    let plug = Speech.plug(40)
    let memory = heard(Speech.episode(tag: "old", total: 1200, plugs: [(400, plug)]))
    // 20 words that last 20 seconds (a second a word): long enough, too few words.
    let slow = Speech.episode(tag: "new", total: 1200, plugs: [(900, Array(plug[0..<20]))])
    XCTAssertEqual(
      memory.find(
        show: show, episode: "new", lines: Speech.lines(slow, step: 1), duration: 1200, now: now), [])
    // 40 words that last 8 seconds (0.2 seconds a word): enough words, too short.
    let fast = Speech.episode(tag: "new", total: 3000, plugs: [(2000, plug)])
    XCTAssertEqual(
      memory.find(
        show: show, episode: "new", lines: Speech.lines(fast, step: 0.2), duration: 600, now: now), [])
    // 32 words at half a second are 16 seconds: found.
    let enough = Speech.episode(tag: "new", total: 1200, plugs: [(900, Array(plug[0..<32]))])
    XCTAssertEqual(find(memory, enough).count, 1)
  }

  func testAPassageThatIsLongerThanThreeHundredSecondsIsNotOffered() {
    let old = Speech.episode(tag: "old", total: 3000, plugs: [(100, Speech.plug(700))])
    let new = Speech.episode(tag: "new", total: 3000, plugs: [(1500, Speech.plug(700))])
    XCTAssertEqual(find(heard(old), new), [])
  }

  func testTwoPassagesAreBothFoundInOrder() {
    let alpha = Speech.plug(60, tag: "alpha")
    let beta = Speech.plug(60, tag: "beta")
    let old = Speech.episode(tag: "old", total: 2400, plugs: [(300, alpha), (900, beta)])
    let new = Speech.episode(
      tag: "new", total: 2400,
      plugs: [(1800, Speech.plug(60, tag: "beta")), (500, Speech.plug(60, tag: "alpha"))])
    let found = find(heard(old), new)
    XCTAssertEqual(found.count, 2)
    XCTAssertEqual(found.map(\.start), found.map(\.start).sorted())
    XCTAssertEqual(found.first?.start ?? 0, Speech.time(ofWord: 500), accuracy: 5)
    XCTAssertEqual(found.last?.start ?? 0, Speech.time(ofWord: 1800), accuracy: 5)
  }

  func testCommonPhrasesSpreadThroughTheTalkAreNotARepeat() {
    func chatty(_ tag: String) -> [String] {
      var words: [String] = []
      for block in 0..<100 {
        words += Speech.talk(8, tag: "\(tag)\(block)x") + ["you", "know", "what", "i", "mean"]
      }
      return words
    }
    XCTAssertEqual(find(heard(chatty("old")), chatty("new")), [])
  }

  func testTalkDrawnFromTheSameCommonWordsIsNotARepeat() {
    // Two hours of made-up talk from 300 words, the first ones far more often than the rest, so
    // short runs of common words do come back by chance. Nothing in it is a repeated passage.
    func talk(seed: UInt64, count: Int) -> [String] {
      var state = seed
      return (0..<count).map { _ in
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let unit = Double(state >> 11) / Double(1 << 53)
        return "w\(Int(300 * unit * unit * unit))"
      }
    }
    var memory = RepeatedWords()
    for n in 0..<3 {
      memory = heard(talk(seed: UInt64(11 + n), count: 18_000), as: "old\(n)", into: memory)
    }
    XCTAssertEqual(find(memory, talk(seed: 99, count: 18_000)), [])
  }

  func testOnlyEpisodesOfTheSameShowAreUsed() {
    let old = Speech.episode(tag: "old", total: 1200, plugs: [(400, Speech.plug(40))])
    let new = Speech.episode(tag: "new", total: 1200, plugs: [(900, Speech.plug(40))])
    let memory = heard(old)
    XCTAssertEqual(find(memory, new).count, 1)
    XCTAssertEqual(
      memory.find(
        show: "another", episode: "new", lines: Speech.lines(new), duration: 600, now: now), [])
  }

  func testTheRepeatIsFoundFromAnyOfTheOlderEpisodes() {
    var memory = RepeatedWords()
    for (n, tag) in ["one", "two", "three"].enumerated() {
      let plug = Speech.plug(40, tag: tag)
      memory = heard(
        Speech.episode(tag: "talk\(tag)", total: 800, plugs: [(200 + 40 * n, plug)]), as: tag,
        into: memory)
    }
    let new = Speech.episode(
      tag: "new", total: 1500,
      plugs: [(300, Speech.plug(40, tag: "one")), (600, Speech.plug(40, tag: "three"))])
    XCTAssertEqual(find(memory, new).count, 2)
  }

  // MARK: The first minute

  func testTheThemeAtSecondZeroIsLeftToShowOpenings() {
    let theme = Speech.plug(40, tag: "theme")
    let old = Speech.episode(tag: "old", total: 1200, plugs: [(0, theme)])
    let new = Speech.episode(tag: "new", total: 1200, plugs: [(0, theme)])
    XCTAssertEqual(find(heard(old), new), [])
  }

  func testARepeatThatRunsPastTheFirstMinuteIsOfferedOnlyFromTheMinute() {
    let long = Speech.plug(200, tag: "cold")
    let old = Speech.episode(tag: "old", total: 1200, plugs: [(60, long)])
    let new = Speech.episode(tag: "new", total: 1200, plugs: [(60, long)])
    let found = find(heard(old), new)
    XCTAssertEqual(found.count, 1)
    XCTAssertGreaterThanOrEqual(found.first?.start ?? 0, 60)
    XCTAssertEqual(found.first?.end ?? 0, Speech.time(ofWord: 260), accuracy: 5)
  }

  // MARK: Itself

  func testTheSameEpisodeNeverMatchesItself() {
    // A short episode, so that the whole of it after the first minute would be one stretch of
    // 140 seconds if it were compared with itself.
    let words = Speech.talk(400, tag: "same")
    let memory = heard(words, as: "e1")
    XCTAssertEqual(find(memory, words, as: "e1"), [])
    // The same words under another name are another episode, and are found.
    XCTAssertEqual(find(memory, words, as: "e2").count, 1)
    // Asking twice does not store it twice, and so does not change the answer.
    XCTAssertEqual(heard(words, as: "e1", into: memory).shows[0].episodes.count, 1)
  }

  func testAnEpisodeThatMostlyRepeatsIsAReRunAndGivesNothing() {
    let plugs = (0..<3).map { (at: 100 + $0 * 300, words: Speech.plug(200, tag: "re\($0)x")) }
    let old = Speech.episode(tag: "old", total: 1200, plugs: plugs)
    let new = Speech.episode(tag: "new", total: 1200, plugs: plugs)
    XCTAssertEqual(find(heard(old), new), [])
    // One of the three passages alone is a sixth of the episode: found.
    let one = Speech.episode(tag: "new", total: 1200, plugs: [plugs[0]])
    XCTAssertEqual(find(heard(old), one).count, 1)
  }

  // MARK: Ads that others found

  func testAStretchThatOverlapsAnAdOthersFoundIsCutOrDropped() {
    let old = Speech.episode(tag: "old", total: 1600, plugs: [(200, Speech.plug(120))])
    let new = Speech.episode(tag: "new", total: 1600, plugs: [(903, Speech.plug(120))])
    let memory = heard(old)
    // The stretch is 451.5 to 511.5 seconds.
    XCTAssertEqual(find(memory, new).count, 1)
    // A middle part is named: two pieces are left, each long enough, clear of it by a second.
    let middle = find(memory, new, already: [ad(470, 490)])
    XCTAssertEqual(middle.count, 2)
    for piece in middle {
      XCTAssertTrue(piece.end <= 469 + 0.001 || piece.start >= 491 - 0.001, "\(piece)")
      XCTAssertEqual(piece.source, "repeat-words")
    }
    // Everything is named: nothing is left. Only a short end is left (under 15 seconds): dropped.
    XCTAssertEqual(find(memory, new, already: [ad(440, 520)]), [])
    XCTAssertEqual(find(memory, new, already: [ad(440, 505)]), [])
    // The start is named and a long end stays.
    let tail = find(memory, new, already: [ad(440, 480)])
    XCTAssertEqual(tail.count, 1)
    XCTAssertGreaterThanOrEqual(tail.first?.start ?? 0, 481 - 0.001)
    XCTAssertEqual(tail.first?.end ?? 0, 511.5, accuracy: 0.001)
  }

  func testAnAdThatIsNotAStretchOfTheEpisodeChangesNothing() {
    let old = Speech.episode(tag: "old", total: 1200, plugs: [(400, Speech.plug(40))])
    let new = Speech.episode(tag: "new", total: 1200, plugs: [(900, Speech.plug(40))])
    let memory = heard(old)
    let plain = find(memory, new)
    let others = [ad(10, 20), ad(Double.nan, 500), ad(500, 400), ad(.infinity, .infinity)]
    XCTAssertEqual(find(memory, new, already: others), plain)
  }

  // MARK: The file

  func testTheMemoryComesBackFromItsFileAndFindsTheSame() {
    let old = Speech.episode(tag: "old", total: 1200, plugs: [(400, Speech.plug(40))])
    let new = Speech.episode(tag: "new", total: 1200, plugs: [(900, Speech.plug(40, changed: [5]))])
    let memory = heard(old)
    let again = RepeatedWords.read(memory.data)
    XCTAssertEqual(again, memory)
    XCTAssertEqual(find(again, new), find(memory, new))
    XCTAssertEqual(find(again, new).count, 1)
  }

  func testOnlyHashesAreKeptNotTheWords() {
    let old = Speech.episode(tag: "old", total: 1200, plugs: [(400, Speech.plug(40))])
    let text = String(decoding: heard(old).data, as: UTF8.self)
    XCTAssertFalse(text.contains("plug"))
    XCTAssertFalse(text.contains("old1"))
  }
}
