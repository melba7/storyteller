import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// What a layer was asked, kept for the test to read (layers are called one at a time).
private final class Asked: @unchecked Sendable {
  private let lock = NSLock()
  private var inputs: [AdScoreInput] = []
  private var before: [[FoundAd]] = []

  func add(_ input: AdScoreInput, _ soFar: [FoundAd]) {
    lock.lock()
    defer { lock.unlock() }
    inputs.append(input)
    before.append(soFar)
  }

  var all: [(input: AdScoreInput, soFar: [FoundAd])] {
    lock.lock()
    defer { lock.unlock() }
    return zip(inputs, before).map { (input: $0, soFar: $1) }
  }
}

final class AdScoreLayerTests: XCTestCase {
  private let episodes = [
    scoreEpisode(id: "1", feed: "fa", show: "A", truth: [(10, 20, "sponsor"), (40, 50, "host_ask")]),
    scoreEpisode(id: "2", feed: "fb", show: "B", truth: [(10, 20, "sponsor"), (70, 80, "sponsor")]),
    scoreEpisode(id: "3", feed: "fa", show: "A", truth: [(40, 50, "host_ask"), (70, 80, "sponsor")]),
  ]

  /// What the rows before the layers find: the first marked sponsor ad, 2 seconds late.
  private let base: (TeachingEpisode, Transcript) -> [FoundAd] = { episode, _ in
    episode.truth.first.map { [foundAd($0.start + 2, $0.end)] } ?? []
  }

  /// A layer that adds the ads at the given places in every episode.
  private func adding(_ name: String, _ spans: [(Double, Double)]) -> AdScoreLayer {
    AdScoreLayer(name: name) { _, _ in spans.map { foundAd($0.0, $0.1) } }
  }

  private func plain(_ episodes: [TeachingEpisode]) -> Scorecard {
    AdScoreRun.run(episodes: episodes, habits: ShowHabits()) { episode, transcript in
      base(episode, transcript)
    }
  }

  func testALayerAddsItsAdsToTheRowAndTheRowsBeforeAreUnchanged() {
    let cards = AdScoreRun.runLayers(
      episodes: episodes, habits: ShowHabits(), base: base,
      layers: [adding("Plus plugs", [(40, 50)]), adding("Plus sponsors", [(70, 80)])])
    XCTAssertEqual(cards.count, 2)
    let alone = plain(episodes)
    XCTAssertEqual(alone.total.ads, 6)
    XCTAssertEqual(alone.total.caught, 3)
    // The first row is the base plus the plugs; the second adds the sponsors on top of it.
    XCTAssertEqual(cards[0].total.caught, 4)
    XCTAssertEqual(cards[1].total.caught, 6)
    // The base's two seconds late in episodes 1 and 2 are all that is still heard.
    XCTAssertEqual(cards[1].total.heardSeconds, 4, accuracy: 1e-9)
    XCTAssertEqual(cards[1].total.heardBeforeSeconds, 4, accuracy: 1e-9)
    // Adding a layer at the end does not change a row before it.
    let one = AdScoreRun.runLayers(
      episodes: episodes, habits: ShowHabits(), base: base, layers: [adding("Plus plugs", [(40, 50)])])
    XCTAssertEqual(one[0], cards[0])
    // A layer that adds nothing leaves its row equal to the row before.
    let empty = AdScoreRun.runLayers(
      episodes: episodes, habits: ShowHabits(), base: base,
      layers: [adding("Nothing", [])])
    XCTAssertEqual(empty[0], plain(episodes))
  }

  func testTheLayerSeesTheEpisodeAndTheAdsSoFar() {
    let asked = Asked()
    let audio = URL(fileURLWithPath: "/teaching/audio/2.mp3")
    let spy = AdScoreLayer(name: "Spy") { input, soFar in
      asked.add(input, soFar)
      return []
    }
    _ = AdScoreRun.runLayers(
      episodes: episodes, habits: ShowHabits(),
      audio: { $0.id == "2" ? audio : nil }, base: base, layers: [adding("First", [(40, 50)]), spy])
    // Episodes 1 and 2 open with a marked ad, so they are asked a second time, for their head.
    let seen = asked.all.filter { !$0.input.isHead }
    XCTAssertEqual(seen.map(\.input.episode.id), ["1", "2", "3"])
    XCTAssertEqual(asked.all.count, 5)
    let second = seen[1]
    XCTAssertEqual(second.input.episode.feed, "fb")
    XCTAssertEqual(second.input.episode.show, "B")
    // The episode is ten lines of ten seconds: its length is the start of the last line.
    XCTAssertEqual(second.input.episode.episodeLength, 90)
    XCTAssertEqual(second.input.episode.truth.count, 2)
    XCTAssertEqual(second.input.transcript.lines.count, 10)
    XCTAssertEqual(second.input.audio, audio)
    XCTAssertNil(seen[0].input.audio)
    XCTAssertFalse(second.input.isHead)
    // The ads so far are the base's ad and the first layer's ad, joined and in order.
    XCTAssertEqual(second.soFar.map(\.start), [12, 40])
    XCTAssertEqual(second.soFar.map(\.end), [20, 50])
  }

  func testTheLayerIsAskedAgainWithOnlyTheHeadWhenTheEpisodeOpensWithAnAd() {
    let asked = Asked()
    let spy = AdScoreLayer(name: "Spy") { input, soFar in
      asked.add(input, soFar)
      return []
    }
    let opening = scoreEpisode(truth: [(2, 12, "sponsor")])
    _ = AdScoreRun.runLayers(
      episodes: [opening], habits: ShowHabits(), base: { _, transcript in
        transcript.duration < 100 ? [foundAd(0, 8)] : []
      }, layers: [spy])
    let seen = asked.all
    XCTAssertEqual(seen.map(\.input.isHead), [false, true])
    XCTAssertEqual(seen[1].input.transcript.duration, 15)
    XCTAssertEqual(seen[1].input.episode.episodeLength, 90)
    XCTAssertEqual(seen[0].soFar, [])
    XCTAssertEqual(seen[1].soFar.map(\.end), [8])
  }

  func testTheAdsAreJoinedWithTheAdsSoFar() {
    // The base skips 12 to 20 of the marked 10 to 20. The layer adds 15 to 25: one ad, 12 to 25.
    let card = AdScoreRun.runLayers(
      episodes: [episodes[0]], habits: ShowHabits(), base: base,
      layers: [adding("Overlapping", [(15, 25)])])[0]
    XCTAssertEqual(card.episodes[0].cutSeconds, 5, accuracy: 1e-9)
    XCTAssertEqual(card.episodes[0].wrongSkips, 0)
    XCTAssertEqual(card.episodes[0].heardBeforeSeconds, 2, accuracy: 1e-9)
  }

  func testAdsWithBadNumbersAreLeftOut() {
    let bad = AdScoreLayer(name: "Bad") { _, _ in
      [
        FoundAd(start: .nan, end: 30, kind: .ad, advertiser: "", confidence: .sure, firstWords: ""),
        FoundAd(start: 5, end: 5, kind: .ad, advertiser: "", confidence: .sure, firstWords: ""),
        FoundAd(start: 60, end: 50, kind: .ad, advertiser: "", confidence: .sure, firstWords: ""),
        FoundAd(start: 0, end: .infinity, kind: .ad, advertiser: "", confidence: .sure, firstWords: ""),
        foundAd(40, 50),
      ]
    }
    let card = AdScoreRun.runLayers(
      episodes: [episodes[0]], habits: ShowHabits(), base: base, layers: [bad])[0]
    // Only 40 to 50 is added: with the base's ad both marked stretches are caught, and no show
    // is cut by the ad that runs to infinity.
    XCTAssertEqual(card.episodes[0].caught, 2)
    XCTAssertEqual(card.episodes[0].ads, 2)
    XCTAssertEqual(card.episodes[0].cutSeconds, 0, accuracy: 1e-9)
  }

  func testALayerCanRewriteTheWholeList() {
    let dropEverything = AdScoreLayer.rewriting(name: "Off") { _, _ in [] }
    let moveLater = AdScoreLayer.rewriting(name: "Moved") { _, soFar in
      soFar.map { ad in
        var moved = ad
        moved.start += 1
        return moved
      }
    }
    let cards = AdScoreRun.runLayers(
      episodes: [episodes[0]], habits: ShowHabits(), base: base,
      layers: [adding("Plus plugs", [(40, 50)]), moveLater, dropEverything])
    XCTAssertEqual(cards[0].total.caught, 2)
    XCTAssertEqual(cards[0].total.heardBeforeSeconds, 2, accuracy: 1e-9)
    // The moved starts replace the old ones (they are not joined with them): 3 and 1 seconds.
    XCTAssertEqual(cards[1].total.caught, 2)
    XCTAssertEqual(cards[1].total.heardBeforeSeconds, 4, accuracy: 1e-9)
    // What the layer leaves out is gone.
    XCTAssertEqual(cards[2].total.caught, 0)
    XCTAssertEqual(cards[2].total.heardSeconds, 20, accuracy: 1e-9)
  }

  func testNoLayersAndNoEpisodes() {
    XCTAssertEqual(AdScoreRun.runLayers(episodes: episodes, habits: ShowHabits(), base: base, layers: []), [])
    let none = AdScoreRun.runLayers(
      episodes: [], habits: ShowHabits(), base: base, layers: [adding("A", []), adding("B", [])])
    XCTAssertEqual(none.count, 2)
    XCTAssertEqual(none[0].episodes, [])
    XCTAssertEqual(none[1].total.ads, 0)
  }

  func testEachRowsShowsAddUpToItsTotal() {
    let cards =
      [plain(episodes)]
      + AdScoreRun.runLayers(
        episodes: episodes, habits: ShowHabits(), base: base,
        layers: [adding("Plus plugs", [(40, 52)]), adding("Plus sponsors", [(68, 80)])])
    XCTAssertEqual(cards.count, 3)
    for card in cards {
      XCTAssertEqual(card.shows.count, 2)
      var sum = ScoreTotals()
      for show in card.shows {
        sum.episodes += show.total.episodes
        sum.shows += show.total.shows
        sum.ads += show.total.ads
        sum.caught += show.total.caught
        sum.adSeconds += show.total.adSeconds
        sum.heardSeconds += show.total.heardSeconds
        sum.heardBeforeSeconds += show.total.heardBeforeSeconds
        sum.heardAfterSeconds += show.total.heardAfterSeconds
        sum.cutSeconds += show.total.cutSeconds
        sum.showSeconds += show.total.showSeconds
        sum.wrongSkips += show.total.wrongSkips
      }
      XCTAssertEqual(sum.episodes, card.total.episodes)
      XCTAssertEqual(sum.shows, card.total.shows)
      XCTAssertEqual(sum.ads, card.total.ads)
      XCTAssertEqual(sum.caught, card.total.caught)
      XCTAssertEqual(sum.adSeconds, card.total.adSeconds, accuracy: 1e-9)
      XCTAssertEqual(sum.heardSeconds, card.total.heardSeconds, accuracy: 1e-9)
      XCTAssertEqual(sum.heardBeforeSeconds, card.total.heardBeforeSeconds, accuracy: 1e-9)
      XCTAssertEqual(sum.heardAfterSeconds, card.total.heardAfterSeconds, accuracy: 1e-9)
      XCTAssertEqual(sum.cutSeconds, card.total.cutSeconds, accuracy: 1e-9)
      XCTAssertEqual(sum.showSeconds, card.total.showSeconds, accuracy: 1e-9)
      XCTAssertEqual(sum.wrongSkips, card.total.wrongSkips)
    }
    // The rows differ, so the per-show numbers are each row's own: show A's seconds heard fall.
    let heardA = cards.map { card in
      card.shows.first { $0.feed == "fa" }?.total.heardSeconds ?? -1
    }
    XCTAssertEqual(heardA, [24, 12, 2])
  }
}
