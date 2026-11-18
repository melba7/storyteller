import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// Learning a show's opening words from two checked episodes, replacing them, and the small file.
final class ShowOpeningsTests: XCTestCase {
  private let opening = "from the example network this is the daily example im sam"
  private let openingWords = [
    "From", "the", "Example", "Network,", "this", "is", "The", "Daily", "Example.", "I'm", "Sam.",
  ]

  /// "<tag>x0 <tag>x1 ...": words no other list shares a run with.
  private func talk(_ tag: String, _ count: Int) -> [String] { (0..<count).map { "\(tag)x\($0)" } }

  private func timed(_ texts: [String], step: Double = 0.5) -> [TranscriptWord] {
    texts.enumerated().map {
      TranscriptWord(
        text: $0.element, start: Double($0.offset) * step, end: Double($0.offset + 1) * step)
    }
  }

  private func transcript(_ texts: [String], step: Double = 0.5) -> Transcript {
    Transcript(
      identity: TranscriptIdentity(
        locale: "en-US", recogniser: "Fake", recogniserVersion: "1", osVersion: "26.0",
        sha256: "aa"),
      duration: Double(texts.count) * step, lines: [], words: timed(texts, step: step))
  }

  private func ad(_ start: Double, _ end: Double, _ confidence: AdConfidence = .sure) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "Acme", confidence: confidence, firstWords: "")
  }

  private func file(
    _ ads: [FoundAd], undone: [UndoneAd] = [], coveredUntil: Double? = nil
  ) -> AdsFile {
    AdsFile(
      sha256: "aa", detector: "fake", detectorVersion: "1", osVersion: "26.0", duration: 600,
      ads: ads, undone: undone, coveredUntil: coveredUntil)
  }

  /// An episode: a pre-roll of `lead` words (an ad of its own words), then `then`, then talk.
  /// Returns its words and its ads file.
  private func episode(
    _ tag: String, lead: Int = 40, then: [String]? = nil, preroll: Bool = true
  ) -> (words: [String], file: AdsFile) {
    let words = talk(tag + "pre", lead) + (then ?? openingWords) + talk(tag + "show", 200)
    let ads = preroll ? [ad(0, Double(lead) * 0.5)] : []
    return (words, file(ads))
  }

  private func learn(
    _ openings: inout ShowOpenings, _ made: (words: [String], file: AdsFile), id: String,
    show: String = "show", step: Double = 0.5
  ) {
    openings.learn(
      from: made.file, transcript: transcript(made.words, step: step), show: show, episode: id)
  }

  // MARK: Learning

  func testTwoEpisodesWithTheSameOpeningAfterDifferentPrerollsLearnThoseWords() {
    var openings = ShowOpenings()
    learn(&openings, episode("a", lead: 40), id: "e1")
    XCTAssertNil(openings.opening(for: "show"), "one episode shares nothing yet")
    learn(&openings, episode("b", lead: 70), id: "e2")
    XCTAssertEqual(openings.opening(for: "show"), opening)
  }

  func testAShowWhoseEpisodesShareNoRunLearnsNothing() {
    var openings = ShowOpenings()
    learn(&openings, episode("a", then: talk("ia", 12)), id: "e1")
    learn(&openings, episode("b", then: talk("ib", 12)), id: "e2")
    learn(&openings, episode("c", then: talk("ic", 12)), id: "e3")
    XCTAssertNil(openings.opening(for: "show"))
  }

  func testASharedRunInsideASureAdIsNotLearned() {
    // The same sponsor read, 12 words long, sits in both episodes, inside the ad.
    let sponsor = talk("sponsor", 12)
    var openings = ShowOpenings()
    for (tag, id) in [("a", "e1"), ("b", "e2"), ("c", "e3")] {
      let words = talk(tag + "pre", 10) + sponsor + talk(tag + "show", 100)
      learn(&openings, (words, file([ad(0, 11)])), id: id)
    }
    XCTAssertNil(openings.opening(for: "show"))
  }

  func testAnUnsureAdAndAnUndoneAdAlsoKeepTheirWordsOut() {
    let sponsor = talk("sponsor", 12)
    var unsure = ShowOpenings()
    var undone = ShowOpenings()
    for (tag, id) in [("a", "e1"), ("b", "e2")] {
      let words = talk(tag + "pre", 10) + sponsor + talk(tag + "show", 100)
      learn(&unsure, (words, file([ad(0, 11, .unsure)])), id: id)
      learn(&undone, (words, file([ad(0, 11)], undone: [UndoneAd(start: 0, end: 11)])), id: id)
    }
    XCTAssertNil(unsure.opening(for: "show"), "it may be an ad: not learned from")
    XCTAssertNil(undone.opening(for: "show"), "the listener undid it, but it was an ad's words")
  }

  func testWordsOnTwoSidesOfAnAdAreNotJoinedIntoOneRun() {
    // Each episode has "left ... | ad | right ..." with the same four words either side: the six
    // words of a run across the gap would be 8 with them, but they are not next to each other.
    let left = talk("left", 4)
    let right = talk("right", 4)
    var openings = ShowOpenings()
    for (tag, id) in [("a", "e1"), ("b", "e2")] {
      let words = left + talk(tag + "ad", 20) + right + talk(tag + "show", 100)
      learn(&openings, (words, file([ad(2, 12)])), id: id)
    }
    XCTAssertNil(openings.opening(for: "show"))
  }

  func testRunsOfSevenAndFortyOneWordsAreNotLearnedButEightAndFortyAre() {
    for (count, learned) in [(7, false), (8, true), (40, true), (41, false)] {
      var openings = ShowOpenings()
      let shared = talk("shared", count)
      learn(&openings, episode("a", then: shared), id: "e1")
      learn(&openings, episode("b", then: shared), id: "e2")
      XCTAssertEqual(openings.opening(for: "show") != nil, learned, "\(count) words")
      if learned {
        XCTAssertEqual(openings.opening(for: "show")?.split(separator: " ").count, count)
      }
    }
  }

  func testOnlyTheFirstFiveMinutesAreRead() {
    // Two seconds a word: 140 words of talk is 280 s, 160 words is 320 s.
    for (lead, learned) in [(140, true), (160, false)] {
      var openings = ShowOpenings()
      for (tag, id) in [("a", "e1"), ("b", "e2")] {
        learn(&openings, (talk(tag + "show", lead) + openingWords, file([])), id: id, step: 2.0)
      }
      XCTAssertEqual(
        openings.opening(for: "show") != nil, learned, "the run starts at \(lead * 2) s")
    }
  }

  func testOnlyTheFirstThreeHundredWordsOutsideAdsAreKept() {
    var openings = ShowOpenings()
    for (tag, id) in [("a", "e1"), ("b", "e2")] {
      learn(&openings, (talk(tag + "show", 400) + openingWords, file([])), id: id)
    }
    XCTAssertNil(openings.opening(for: "show"), "at 200 s, but after 400 words of talk")
    XCTAssertEqual(openings.shows.first?.heard.map { $0.split(separator: " ").count }, [300])
  }

  func testAnEpisodeCountsOnceAndAPartialOrEmptyFileSaysNothing() {
    var openings = ShowOpenings()
    let first = episode("a")
    learn(&openings, first, id: "e1")
    learn(&openings, first, id: "e1")  // the same episode again must not be "a second episode"
    XCTAssertNil(openings.opening(for: "show"))
    var partial = ShowOpenings()
    learn(&partial, (episode("a").words, file([], coveredUntil: 60)), id: "e1")
    learn(&partial, (episode("b").words, file([], coveredUntil: 60)), id: "e2")
    XCTAssertTrue(partial.shows.isEmpty, "a partial ads file is not a checked episode")
    var silent = ShowOpenings()
    learn(&silent, (talk("a", 10), file([])), id: "e1")
    XCTAssertTrue(silent.shows.isEmpty, "too few words to say anything")
  }

  func testTheEarliestSharedRunWinsOverALaterOne() {
    let late = talk("late", 20)
    var openings = ShowOpenings()
    learn(&openings, episode("a", then: openingWords + talk("amid", 30) + late), id: "e1")
    learn(&openings, episode("b", then: openingWords + talk("bmid", 50) + late), id: "e2")
    XCTAssertEqual(openings.opening(for: "show"), opening)
  }

  // MARK: Keeping and replacing

  /// A show that learned its opening from two episodes.
  private func learnedShow() -> ShowOpenings {
    var openings = ShowOpenings()
    learn(&openings, episode("a"), id: "e1")
    learn(&openings, episode("b"), id: "e2")
    return openings
  }

  func testAnEpisodeWithTheOpeningKeepsItAndTwoWithoutDoNotRemoveIt() {
    var openings = learnedShow()
    learn(&openings, episode("c", then: talk("ic", 12)), id: "e3")
    learn(&openings, episode("d", then: talk("id", 12)), id: "e4")
    XCTAssertEqual(openings.opening(for: "show"), opening, "two misses are not three")
    XCTAssertEqual(openings.shows.first?.misses, 2)
    learn(&openings, episode("e"), id: "e5")
    XCTAssertEqual(openings.shows.first?.misses, 0, "an episode that has it starts the count again")
    XCTAssertEqual(openings.opening(for: "show"), opening)
  }

  func testThreeNewerEpisodesWithoutItReplaceItWithWhatTheLastTwoShare() {
    var openings = learnedShow()
    let next = "welcome back to the nightly example with sam and dana"
    learn(&openings, episode("c", then: talk("ic", 12)), id: "e3")
    learn(&openings, episode("d", then: next.split(separator: " ").map(String.init)), id: "e4")
    learn(&openings, episode("e", then: next.split(separator: " ").map(String.init)), id: "e5")
    XCTAssertEqual(openings.opening(for: "show"), next)
    XCTAssertEqual(openings.shows.first?.misses, 0)
  }

  func testThreeNewerEpisodesWithoutItAndNothingNewShareLeavesNoOpening() {
    var openings = learnedShow()
    for (tag, id) in [("c", "e3"), ("d", "e4"), ("e", "e5")] {
      learn(&openings, episode(tag, then: talk("i" + tag, 12)), id: id)
    }
    XCTAssertNil(openings.opening(for: "show"))
    learn(&openings, episode("f"), id: "e6")
    learn(&openings, episode("g"), id: "e7")
    XCTAssertEqual(openings.opening(for: "show"), opening, "and it learns again")
  }

  func testOneOpeningPerShowAndTwoHundredShowsAtMost() {
    var openings = ShowOpenings()
    for number in 0..<205 {
      learn(&openings, episode("a\(number)"), id: "e\(number)", show: "show\(number)")
    }
    XCTAssertEqual(openings.shows.count, 200)
    XCTAssertNil(openings.shows.first(where: { $0.id == "show0" }), "the oldest shows went")
    XCTAssertNotNil(openings.shows.first(where: { $0.id == "show204" }))
    learn(&openings, episode("z"), id: "ez", show: "show204")
    XCTAssertEqual(openings.shows.filter { $0.id == "show204" }.count, 1)
    XCTAssertEqual(openings.shows.last?.id, "show204", "the newest comes last")
  }

  // MARK: The file

  func testTheFileStaysUnderHalfAMegabyteForTwoHundredShowsWithNothingLearnedYet() throws {
    var openings = ShowOpenings()
    for number in 0..<200 {
      // Six letters a word: longer than the average English word, so this is a worst case.
      let words = (0..<400).map { "w\($0 % 90 + 10)xyz" }
      openings.learn(
        from: file([]), transcript: transcript(words), show: "show\(number)", episode: "e\(number)")
    }
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent(ShowOpenings.fileName)
    try openings.save(to: url)
    let size = try Data(contentsOf: url).count
    XCTAssertLessThan(size, 500_000)
    XCTAssertEqual(ShowOpenings.load(from: url), openings)
  }

  func testAMissingBrokenOrNewerFileIsAnEmptyMemory() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent(ShowOpenings.fileName)
    XCTAssertEqual(ShowOpenings.load(from: url), ShowOpenings())
    try Data("not json".utf8).write(to: url)
    XCTAssertEqual(ShowOpenings.load(from: url), ShowOpenings())
    try Data(#"{"version":99,"shows":[]}"#.utf8).write(to: url)
    XCTAssertEqual(ShowOpenings.load(from: url), ShowOpenings())
    try learnedShow().save(to: url)
    XCTAssertEqual(ShowOpenings.load(from: url).opening(for: "show"), opening)
  }

  func testOnceAnOpeningIsLearnedNothingElseIsKeptForTheShow() {
    XCTAssertEqual(ShowOpenings.fileName, "show-openings.json")
    let openings = learnedShow()
    XCTAssertEqual(openings.shows.count, 1)
    XCTAssertEqual(openings.shows.first?.heard, [])
    XCTAssertEqual(openings.shows.first?.episode, "e2")
  }
}
