import XCTest

@testable import PodcastAds

/// What the phone works out about how a show starts from what it saw itself, and how that is put
/// beside what the Mac taught.
final class ShowHabitsOwnTests: XCTestCase {
  private func ad(_ start: Double, _ end: Double, _ confidence: AdConfidence = .sure) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "Acme", confidence: confidence,
      firstWords: "")
  }

  /// A phone that saw `opens` of `episodes` episodes (at most five) open with an ad that ended at
  /// `end` seconds.
  private func phone(opens: Int, of episodes: Int, end: Double? = 40, show: String = "s")
    -> ShowStarts
  {
    var starts = ShowStarts()
    for number in 0..<episodes {
      starts.record(show: show, hadAdAtStart: number < opens, openingEnd: end)
    }
    return starts
  }

  private func mac(
    _ episodes: Int, _ opens: Int, ends: Double? = 40, id: String = "s"
  ) -> ShowHabits {
    var habits = ShowHabits()
    habits.shows = [.init(id: id, episodes: episodes, opensWithAd: opens, openingEnds: ends)]
    return habits
  }

  private func own(_ starts: ShowStarts, show: String = "s") throws -> ShowHabits.Show {
    try XCTUnwrap(starts.habits().shows.first { $0.id == show })
  }

  // MARK: The phone's own habits

  func testThreeOfFiveEpisodesWithAnOpeningAdIsUsuallyOpeningWithAnAd() {
    XCTAssertTrue(phone(opens: 3, of: 5).habits().usuallyOpensWithAd(show: "s"))
    XCTAssertTrue(phone(opens: 5, of: 5).habits().usuallyOpensWithAd(show: "s"))
    XCTAssertTrue(phone(opens: 3, of: 4).habits().usuallyOpensWithAd(show: "s"))
  }

  func testTwoOfFiveDoesNotAndNeitherDoFewerThanThreeEpisodes() {
    XCTAssertFalse(phone(opens: 2, of: 5).habits().usuallyOpensWithAd(show: "s"))
    XCTAssertFalse(phone(opens: 0, of: 5).habits().usuallyOpensWithAd(show: "s"))
    XCTAssertFalse(phone(opens: 1, of: 3).habits().usuallyOpensWithAd(show: "s"))
    XCTAssertFalse(phone(opens: 2, of: 2).habits().usuallyOpensWithAd(show: "s"), "two episodes")
    XCTAssertFalse(phone(opens: 1, of: 1).habits().usuallyOpensWithAd(show: "s"), "one episode")
    XCTAssertTrue(phone(opens: 3, of: 3).habits().usuallyOpensWithAd(show: "s"), "three is enough")
    XCTAssertFalse(phone(opens: 5, of: 5).habits().usuallyOpensWithAd(show: "other"))
  }

  func testTheNumbersAreTheOnesTheMacCounts() throws {
    let habits = try own(phone(opens: 3, of: 5, end: 42))
    XCTAssertEqual(habits, ShowHabits.Show(id: "s", episodes: 5, opensWithAd: 3, openingEnds: 42))
    XCTAssertTrue(ShowStarts().habits().shows.isEmpty)
    XCTAssertEqual(ShowStarts().habits().version, ShowHabits.currentVersion)
    // A show with a clean start reads as clean by the Mac's rule: four episodes, none opened.
    XCTAssertTrue(phone(opens: 0, of: 4).habits().startsClean(show: "s"))
  }

  /// Episodes that all opened with an ad, ending at `ends` (nil: the end is not known).
  private func opening(ends: [Double?]) -> ShowStarts {
    var starts = ShowStarts()
    for end in ends { starts.record(show: "s", hadAdAtStart: true, openingEnd: end) }
    return starts
  }

  func testTheOpeningEndIsTheMiddleValueOfTheKnownEnds() throws {
    XCTAssertEqual(try own(opening(ends: [30, 50, 40])).openingEnds, 40, "odd: the middle one")
    XCTAssertEqual(try own(opening(ends: [30, 50, 40, 60])).openingEnds, 45, "even: the middle two")
    XCTAssertEqual(try own(opening(ends: [44])).openingEnds, 44)
    XCTAssertEqual(try own(opening(ends: [30, nil, 50, nil, 40])).openingEnds, 40, "unknown: left out")
    XCTAssertEqual(try own(opening(ends: [30, nil, 50])).openingEnds, 40)
    XCTAssertNil(try own(opening(ends: [nil, nil, nil])).openingEnds, "no end is known")
  }

  func testOnlyEpisodesThatOpenedWithAnAdCountForTheEnd() throws {
    var starts = ShowStarts()
    starts.record(show: "s", hadAdAtStart: true, openingEnd: 20)
    starts.record(show: "s", hadAdAtStart: false, openingEnd: 200)
    starts.record(show: "s", hadAdAtStart: true, openingEnd: 30)
    XCTAssertEqual(try own(starts).openingEnds, 25)
  }

  func testTheMiddleValueIsRoundedToATenthLikeTheMac() throws {
    // Worked out by teach_habits.py `summarize` on labels with these openings. An exact half goes
    // to the even tenth there (round), which a plain "round half away from zero" would not.
    XCTAssertEqual(try own(opening(ends: [40.2, 40.3])).openingEnds, 40.2)
    XCTAssertEqual(try own(opening(ends: [33.35, 33.4, 61.1, 70])).openingEnds, 47.2)
    XCTAssertEqual(try own(opening(ends: [38.4, 41.2, 44.7, 52])).openingEnds, 43.0)
  }

  /// The ads of each episode of a show, as a head scan saw them (reached 180 seconds).
  private func scanned(_ episodes: [[FoundAd]]) -> ShowStarts {
    var starts = ShowStarts()
    for ads in episodes { starts.record(show: "f", ads: ads, reached: 180) }
    return starts
  }

  func testTheSameAnswersAsTheMacForTheSameEpisodes() throws {
    // Each case is the labels of teach_habits.py's tests, high as sure and medium as unsure; the
    // expected numbers are what its `summarize` gives for them.
    let first = scanned([
      [ad(0, 38.4)], [ad(2, 41.2)], [], [ad(5, 44.7, .unsure), ad(300, 330)],
      [ad(0, 20), ad(30, 52)],  // two ads 10 seconds apart are one opening
    ])
    XCTAssertEqual(
      try own(first, show: "f"), .init(id: "f", episodes: 5, opensWithAd: 4, openingEnds: 43.0))
    let second = scanned([[ad(1, 40.2)], [ad(0, 40.3)]])
    XCTAssertEqual(
      try own(second, show: "f"), .init(id: "f", episodes: 2, opensWithAd: 2, openingEnds: 40.2))
    let third = scanned([
      [ad(0, 33.35)], [ad(0, 33.4)], [ad(10, 70)], [ad(10, 12), ad(25, 61.1, .unsure)],
    ])
    XCTAssertEqual(
      try own(third, show: "f"), .init(id: "f", episodes: 4, opensWithAd: 4, openingEnds: 47.2))
  }

  func testNoNanNegativeOrHugeEndReachesTheHabits() throws {
    var starts = phone(opens: 5, of: 5)
    starts.shows[0].ends = [Double.nan, -4, Double.infinity, 40, 1e300]
    XCTAssertEqual(try own(starts).openingEnds, 40)
    starts.shows[0].ends = [Double.nan, -4, Double.infinity, -Double.infinity, 0]
    XCTAssertNil(try own(starts).openingEnds)
    starts.shows[0].ends = [40]  // the wrong length is not believed
    XCTAssertNil(try own(starts).openingEnds)
    starts.shows[0].ends = nil
    XCTAssertNil(try own(starts).openingEnds)
    XCTAssertTrue(starts.habits().usuallyOpensWithAd(show: "s"), "the bits still say it")
  }

  func testAShowWithNoResultsSaysNothing() {
    var starts = ShowStarts()
    starts.shows = [.init(id: "empty", results: [])]
    XCTAssertTrue(starts.habits().shows.isEmpty)
  }

  // MARK: Beside the Mac's habits

  func testTheMacsEntryWinsWhereItHasOneForTheShow() {
    let merged = mac(5, 5, ends: 70).merged(with: phone(opens: 0, of: 5).habits())
    XCTAssertTrue(merged.usuallyOpensWithAd(show: "s"))
    XCTAssertEqual(merged.openingEnd(show: "s"), 70)
    let clean = mac(5, 0).merged(with: phone(opens: 5, of: 5, end: 90).habits())
    XCTAssertFalse(clean.usuallyOpensWithAd(show: "s"))
    XCTAssertTrue(clean.startsClean(show: "s"))
    XCTAssertEqual(clean.shows, mac(5, 0).shows, "nothing of the phone's is mixed in")
  }

  func testAShowOnlyThePhoneKnowsUsesThePhonesEntry() throws {
    let mine = phone(opens: 4, of: 5, end: 33, show: "mine").habits()
    let merged = mac(5, 5, id: "known").merged(with: mine)
    XCTAssertEqual(merged.shows.map(\.id), ["known", "mine"], "the Mac's shows first")
    XCTAssertTrue(merged.usuallyOpensWithAd(show: "mine"))
    XCTAssertEqual(merged.openingEnd(show: "mine"), 33)
    XCTAssertEqual(merged.firstLook(show: "mine"), 43)
    XCTAssertTrue(merged.usuallyOpensWithAd(show: "known"))
    XCTAssertFalse(merged.usuallyOpensWithAd(show: "neither"))
  }

  func testWithNothingTaughtThePhonesHabitsAreAllThereIs() {
    let taught = phone(opens: 3, of: 5).habits()
    XCTAssertEqual(ShowHabits().merged(with: taught), taught)
    XCTAssertEqual(mac(5, 5).merged(with: ShowHabits()), mac(5, 5))
    XCTAssertEqual(ShowHabits().merged(with: ShowHabits()), ShowHabits())
  }

  func testAMacEntryWhoseNumbersAreNotPossibleDoesNotHideThePhonesEntry() {
    let broken = mac(2, 9)  // more openings than episodes: it says nothing
    let merged = broken.merged(with: phone(opens: 5, of: 5).habits())
    XCTAssertTrue(merged.usuallyOpensWithAd(show: "s"))
    XCTAssertEqual(merged.shows.count, 1)
    var nan = mac(5, 5)
    nan.shows[0].openingEnds = .nan
    let healed = nan.merged(with: phone(opens: 5, of: 5, end: 33).habits())
    XCTAssertEqual(healed.openingEnd(show: "s"), 33)
  }

  func testAShowIsNeverListedTwice() {
    var twice = mac(5, 5)
    twice.shows.append(.init(id: "s", episodes: 4, opensWithAd: 0, openingEnds: nil))
    var phoneTwice = phone(opens: 5, of: 5).habits()
    phoneTwice.shows.append(contentsOf: phoneTwice.shows)
    let merged = twice.merged(with: phoneTwice)
    XCTAssertEqual(merged.shows.map(\.id), ["s", "s"], "the Mac's own list is kept as it was")
    XCTAssertEqual(merged.shows.first?.opensWithAd, 5, "the first entry answers")
    let phoneOnly = ShowHabits().merged(with: phoneTwice)
    XCTAssertEqual(phoneOnly.shows.map(\.id), ["s"])
  }

  // MARK: What it is for

  func testAShowOnlyThePhoneKnowsGetsTheLongerWaitAndTheFirstLookAtItsUsualEnd() {
    let merged = ShowHabits().merged(with: phone(opens: 4, of: 5, end: 40).habits())
    XCTAssertEqual(StartHold.longest(habits: merged, show: "s"), StartHold.longestForAdOpeners)
    XCTAssertEqual(HeadPlan(habits: merged, show: "s").steps, AdHeadRules.steps(firstLook: 50))
    XCTAssertFalse(StartHold.startsClean(habits: merged, show: "s", own: true))
    // Without the phone's own habits the same show is waited for as usual.
    XCTAssertEqual(StartHold.longest(habits: ShowHabits(), show: "s"), StartHold.longest)
    XCTAssertEqual(HeadPlan(habits: ShowHabits(), show: "s").steps, AdHeadRules.steps)
  }
}
