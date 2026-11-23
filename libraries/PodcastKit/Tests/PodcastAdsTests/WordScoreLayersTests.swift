import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// The rows that read the transcript: "Plus repeated words" and "Plus the meaning model".
final class WordScoreLayersTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  /// An episode whose transcript is `words`, five seconds a line (see `Speech`).
  private func episode(
    _ id: String, feed: String = "fa", words: [String]
  ) -> TeachingEpisode {
    let identity = TranscriptIdentity(
      locale: "en-US", recogniser: "Fake", recogniserVersion: "1", osVersion: "26.0", sha256: id)
    let transcript = Transcript(
      identity: identity, duration: Speech.seconds(words), lines: Speech.lines(words), words: [])
    return TeachingEpisode(
      id: id, feed: feed, show: "Show", title: id, transcript: transcript, truth: [], maybe: [],
      onShelf: true, seconds: Speech.seconds(words))
  }

  private func input(_ episode: TeachingEpisode, head: Double? = nil) -> AdScoreInput {
    let transcript = head.map { AdScoreRun.head(of: episode.transcript, seconds: $0) } ?? episode.transcript
    return AdScoreInput(episode: episode, transcript: transcript, audio: nil)
  }

  // MARK: Repeated words

  func testAPlugThatIsInTwoEpisodesOfOneShowIsFoundInTheSecond() throws {
    let layer = WordScoreLayers.repeatedWords(now: now)
    XCTAssertEqual(layer.name, "Plus repeated words")
    XCTAssertFalse(layer.rewrites)
    let one = episode("e1", words: Speech.episode(tag: "one", total: 1200, plugs: [(400, Speech.plug(40))]))
    let two = episode(
      "e2", words: Speech.episode(tag: "two", total: 1200, plugs: [(903, Speech.plug(40, changed: [10, 25]))]))
    // The first episode of a show has nothing to be compared with.
    XCTAssertEqual(layer.apply(input(one), soFar: []), [])
    let row = layer.apply(input(two), soFar: [])
    let ad = try XCTUnwrap(row.first)
    XCTAssertEqual(row.count, 1)
    XCTAssertEqual(ad.source, "repeat-words")
    XCTAssertEqual(ad.source, ShowTuning.repeatWords)
    XCTAssertEqual(ad.confidence, .unsure)
    XCTAssertEqual(ad.start, Speech.time(ofWord: 903), accuracy: 5)
    XCTAssertEqual(ad.end, Speech.time(ofWord: 943), accuracy: 5)
  }

  func testAnotherShowDoesNotShareItsMemory() {
    let layer = WordScoreLayers.repeatedWords(now: now)
    let plugs = [(400, Speech.plug(40))]
    _ = layer.apply(input(episode("e1", feed: "fa", words: Speech.episode(tag: "one", total: 1200, plugs: plugs))), soFar: [])
    let other = episode("e2", feed: "fb", words: Speech.episode(tag: "two", total: 1200, plugs: plugs))
    XCTAssertEqual(layer.apply(input(other), soFar: []), [])
  }

  func testWhatAnOlderFinderFoundIsNotTouchedAndIsLeftAloneByAMarginOfASecond() throws {
    let layer = WordScoreLayers.repeatedWords(now: now)
    // A plug of 80 words (40 seconds, from 451.5 s on) is in both episodes.
    let one = episode("e1", words: Speech.episode(tag: "one", total: 1400, plugs: [(400, Speech.plug(80))]))
    let two = episode("e2", words: Speech.episode(tag: "two", total: 1400, plugs: [(903, Speech.plug(80))]))
    _ = layer.apply(input(one), soFar: [])
    // The older finder already has its last 20 seconds, from 475 s to 495 s.
    let old = foundAd(Speech.time(ofWord: 950), Speech.time(ofWord: 990))
    let row = layer.apply(input(two), soFar: [old])
    XCTAssertTrue(row.contains(old))
    XCTAssertEqual(row.filter { $0.confidence == .sure }, [old])
    let added = row.filter { $0.source == "repeat-words" }
    XCTAssertFalse(added.isEmpty)
    for ad in added { XCTAssertLessThanOrEqual(ad.end, old.start - 1 + 1e-9) }
  }

  func testTheFirstLookDoesNotRememberTheEpisodeAgainOrFindAnythingInTheFirstMinute() {
    let layer = WordScoreLayers.repeatedWords(now: now)
    let one = episode("e1", words: Speech.episode(tag: "one", total: 1200, plugs: [(400, Speech.plug(40))]))
    let two = episode("e2", words: Speech.episode(tag: "two", total: 1200, plugs: [(903, Speech.plug(40))]))
    _ = layer.apply(input(one), soFar: [])
    _ = layer.apply(input(two), soFar: [])
    XCTAssertEqual(layer.apply(input(two, head: 60), soFar: []), [])
    XCTAssertEqual(layer.apply(input(one, head: 60), soFar: []), [])
  }

  func testAnEmptyTranscriptAndNoLinesGiveNothing() {
    let layer = WordScoreLayers.repeatedWords(now: now)
    XCTAssertEqual(layer.apply(input(episode("e1", words: [])), soFar: []), [])
    XCTAssertEqual(layer.apply(input(episode("e2", words: [])), soFar: [foundAd(1, 20)]), [foundAd(1, 20)])
  }

  // MARK: The meaning model

  private let model = AdMeaningModel(data: Made.file())!

  /// Twelve lines of ten seconds: lines 4 to 8 ask for a favour (about 30 to 79 s).
  private var meaningEpisode: TeachingEpisode {
    let texts = (1...12).map { number -> String in
      let even = number % 2 == 0
      if (4...8).contains(number) { return even ? Made.ask : Made.ask2 }
      return even ? Made.talk : Made.talk2
    }
    return TeachingEpisode(
      id: "m1", feed: "fa", show: "Show", title: "m1", transcript: makeTranscript(texts), truth: [],
      maybe: [], onShelf: true)
  }

  func testTheMeaningRowAddsUnsureAdsNamedAfterTheFinder() throws {
    let notes = MeaningScoreNotes()
    let layer = WordScoreLayers.meaning(model: model, embedder: Made.embedder(), notes: notes)
    XCTAssertEqual(layer.name, "Plus the meaning model")
    XCTAssertFalse(layer.rewrites)
    let row = layer.apply(input(meaningEpisode), soFar: [])
    let ad = try XCTUnwrap(row.first)
    XCTAssertEqual(row.count, 1)
    XCTAssertEqual(ad.source, "meaning")
    XCTAssertEqual(ad.source, ShowTuning.meaning)
    XCTAssertEqual(ad.confidence, .unsure)
    XCTAssertEqual(ad.start, 30, accuracy: 1.5)
    XCTAssertEqual(notes.offReasons, [])
    XCTAssertEqual(notes.episodes, 1)
  }

  func testTheMeaningRowOnlyAddsOutsideWhatOlderFindersFound() throws {
    let layer = WordScoreLayers.meaning(
      model: model, embedder: Made.embedder(), notes: MeaningScoreNotes())
    let old = foundAd(40, 60)
    let row = layer.apply(input(meaningEpisode), soFar: [old])
    XCTAssertTrue(row.contains(old))
    XCTAssertEqual(row.filter { $0.confidence == .sure }, [old])
    let added = row.filter { $0.source == "meaning" }
    XCTAssertFalse(added.isEmpty)
    XCTAssertTrue(added.allSatisfy { $0.start >= old.end + 1 - 1e-9 || $0.end <= old.start - 1 + 1e-9 })
  }

  func testTheMeaningRowIsNotRunOnTheFirstLook() {
    let notes = MeaningScoreNotes()
    let layer = WordScoreLayers.meaning(model: model, embedder: Made.embedder(), notes: notes)
    let episode = meaningEpisode
    XCTAssertEqual(layer.apply(input(episode, head: 60), soFar: []), [])
    XCTAssertEqual(notes.episodes, 0)
  }

  func testAnEmbedderThatDoesNotFitTurnsTheRowOffAndSaysWhyOnce() {
    let notes = MeaningScoreNotes()
    let layer = WordScoreLayers.meaning(model: model, embedder: Made.embedder(revision: 9), notes: notes)
    XCTAssertEqual(layer.apply(input(meaningEpisode), soFar: [foundAd(1, 20)]), [foundAd(1, 20)])
    XCTAssertEqual(layer.apply(input(meaningEpisode), soFar: []), [])
    XCTAssertEqual(notes.offReasons.count, 1)
    XCTAssertTrue(notes.offReasons.first?.contains("revision") ?? false)
    XCTAssertEqual(notes.episodes, 0)
  }

  // MARK: What the settings row starts from

  func testTheRepeatedWordsRowKeepsItsOwnListAndTheMeaningRowKeepsItsToo() throws {
    let finders = ScoreFinderAds()
    let layer = WordScoreLayers.repeatedWords(now: now, finders: finders)
    let one = episode("e1", words: Speech.episode(tag: "one", total: 1400, plugs: [(400, Speech.plug(80))]))
    let two = episode("e2", words: Speech.episode(tag: "two", total: 1400, plugs: [(903, Speech.plug(80))]))
    _ = layer.apply(input(one), soFar: [])
    _ = finders.baseRow.apply(input(two), soFar: [])
    // An earlier new finder already has 475 s to 495 s in the row before it, not in the base.
    let before = [foundAd(Speech.time(ofWord: 950), Speech.time(ofWord: 990), .unsure)]
    let row = layer.apply(input(two), soFar: before)
    let own = finders.ads(finder: "repeat-words", for: "e2")
    XCTAssertFalse(own.isEmpty)
    // The whole plug is in its own list (the base has nothing), the row loses what the row before has.
    let ownLength = own.reduce(0) { $0 + $1.end - $1.start }
    let rowLength = row.filter { $0.source == "repeat-words" }.reduce(0) { $0 + $1.end - $1.start }
    XCTAssertGreaterThan(ownLength, rowLength + 15)
    // The first look keeps nothing and does not touch the list.
    _ = layer.apply(input(two, head: 600), soFar: [])
    XCTAssertEqual(finders.ads(finder: "repeat-words", for: "e2"), own)

    let meaningFinders = ScoreFinderAds()
    let meaning = WordScoreLayers.meaning(
      model: model, embedder: Made.embedder(), notes: MeaningScoreNotes(), finders: meaningFinders)
    _ = meaningFinders.baseRow.apply(input(meaningEpisode), soFar: [foundAd(0, 20)])
    _ = meaning.apply(input(meaningEpisode), soFar: [foundAd(0, 20), foundAd(40, 60, .unsure)])
    let kept = meaningFinders.ads(finder: "meaning", for: "m1")
    XCTAssertEqual(try XCTUnwrap(kept.first).start, 30, accuracy: 1.5)
    XCTAssertTrue(kept.allSatisfy { $0.source == "meaning" })
  }
}
