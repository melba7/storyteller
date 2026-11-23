import XCTest

@testable import PodcastAds

/// What the per-show settings say about each finder, each sort and the joints, and how they sort
/// a list of ads into "skip" and "ask". The file's text is read in ShowTuningFileTests.
final class ShowTuningTests: XCTestCase {
  private func ad(
    _ start: Double, _ source: String?, kind: AdKind = .ad, confidence: AdConfidence = .unsure
  ) -> FoundAd {
    FoundAd(
      start: start, end: start + 20, kind: kind, advertiser: "", confidence: confidence,
      firstWords: "", source: source)
  }

  /// A settings file with `default` and `shows` (one entry for feed "feed-a", with `show` as the
  /// rest of its keys), read with a table that knows that feed as show "a".
  private func tuning(default block: String = "{}", show keys: String = "") -> ShowTuning {
    let text = #"{"version": 1, "default": \#(block), "shows": [{"feed": "feed-a"\#(keys)}]}"#
    return ShowTuning(text: text, showOf: MacFiles.table([FeedKey.key("feed-a"): "a"]))
  }

  // MARK: The built-in default

  func testTheBuiltInDefaultIsTheOneTheMacShips() {
    let plain = ShowTuning()
    for show in ["a", "", "never-heard-of"] {
      XCTAssertEqual(plain.level(forFinder: "own-sound", show: show), .skip)
      XCTAssertEqual(plain.level(forFinder: "repeat-sound", show: show), .ask)
      XCTAssertEqual(plain.level(forFinder: "repeat-words", show: show), .ask)
      XCTAssertEqual(plain.level(forFinder: "meaning", show: show), .skip)
      XCTAssertTrue(plain.joints(show: show))
      XCTAssertFalse(plain.steadyJoints(show: show))
      for sort in ShowTuning.sortNames { XCTAssertEqual(plain.level(forSort: sort, show: show), .skip) }
    }
    XCTAssertEqual(plain.askThreshold, 0.35)
  }

  func testAnUnknownFinderOrSortIsNotHeldBack() {
    let plain = ShowTuning()
    XCTAssertEqual(plain.level(forFinder: "tap", show: "a"), .skip)
    XCTAssertEqual(plain.level(forFinder: "", show: "a"), .skip)
    XCTAssertEqual(plain.level(forSort: "poetry", show: "a"), .skip)
  }

  // MARK: Settings

  func testAShowEntryOverridesTheDefaultOneKeyAtATime() {
    let set = tuning(
      default: #"{"finders": {"meaning": "ask"}, "joints": false, "steadyJoints": true}"#,
      show: #", "finders": {"repeat-words": "skip"}, "sorts": {"host_ask": "ask"}, "joints": true"#)
    // The show's own choices.
    XCTAssertEqual(set.level(forFinder: "repeat-words", show: "a"), .skip)
    XCTAssertEqual(set.level(forSort: "host_ask", show: "a"), .ask)
    XCTAssertTrue(set.joints(show: "a"))
    // What the show does not say comes from the default block, then the built-in default.
    XCTAssertEqual(set.level(forFinder: "meaning", show: "a"), .ask)
    XCTAssertEqual(set.level(forFinder: "repeat-sound", show: "a"), .ask)
    XCTAssertEqual(set.level(forFinder: "own-sound", show: "a"), .skip)
    XCTAssertEqual(set.level(forSort: "sponsor", show: "a"), .skip)
    XCTAssertTrue(set.steadyJoints(show: "a"))
    // Another show gets the default block only.
    XCTAssertEqual(set.level(forFinder: "repeat-words", show: "b"), .ask)
    XCTAssertEqual(set.level(forSort: "host_ask", show: "b"), .skip)
    XCTAssertFalse(set.joints(show: "b"))
    XCTAssertTrue(set.steadyJoints(show: "b"))
  }

  func testTheDefaultBlockCanSwitchAFinderOffEverywhereAndAShowCanBringItBack() {
    let set = tuning(
      default: #"{"finders": {"meaning": "off"}}"#, show: #", "finders": {"meaning": "skip"}"#)
    XCTAssertEqual(set.level(forFinder: "meaning", show: "b"), .off)
    XCTAssertEqual(set.level(forFinder: "meaning", show: "a"), .skip)
  }

  func testOneFileCanSwitchEveryNewFinderOff() {
    let set = tuning(
      default: #"{"finders": {"own-sound": "off", "repeat-sound": "off", "repeat-words": "off", "meaning": "off"}}"#)
    let ads = [ad(0, "own-sound"), ad(30, "repeat-sound"), ad(60, "repeat-words"), ad(90, "meaning")]
    let sorted = set.apply(to: ads, show: "a")
    XCTAssertEqual(sorted.skip, [])
    XCTAssertEqual(sorted.ask, [])
  }

  // MARK: Sorting ads

  func testAnAdGoesWhereItsFinderIsAllowedToPutIt() {
    let ads = [
      ad(0, "own-sound"), ad(30, "repeat-sound"), ad(60, "repeat-words"), ad(90, "meaning"),
    ]
    let sorted = ShowTuning().apply(to: ads, show: "a")
    XCTAssertEqual(sorted.skip.map(\.source), ["own-sound", "meaning"])
    XCTAssertEqual(sorted.ask.map(\.source), ["repeat-sound", "repeat-words"])
  }

  func testAFinderThatIsOffIsDropped() {
    let set = tuning(show: #", "finders": {"repeat-sound": "off", "own-sound": "off"}"#)
    let sorted = set.apply(to: [ad(0, "own-sound"), ad(30, "repeat-sound"), ad(60, "meaning")], show: "a")
    XCTAssertEqual(sorted.skip.map(\.source), ["meaning"])
    XCTAssertEqual(sorted.ask, [])
    // The same ads on a show with no entry keep their default.
    let other = set.apply(to: [ad(0, "own-sound"), ad(30, "repeat-sound")], show: "b")
    XCTAssertEqual(other.skip.map(\.source), ["own-sound"])
    XCTAssertEqual(other.ask.map(\.source), ["repeat-sound"])
  }

  func testAnAdWithNoSourceIsUntouchedByFinderLevels() {
    // Every finder is off, and an old finder's ads (no source) and a tap's (source "tap") stay.
    let set = tuning(
      default: #"{"finders": {"own-sound": "off", "repeat-sound": "off", "repeat-words": "off", "meaning": "off"}}"#)
    let old = ad(0, nil, confidence: .sure)
    let tapped = ad(30, "tap", confidence: .sure)
    let sorted = set.apply(to: [old, tapped, ad(60, "meaning")], show: "a")
    XCTAssertEqual(sorted.skip, [old, tapped])
    XCTAssertEqual(sorted.ask, [])
  }

  func testASortThatIsOffDropsAndOneThatAsksMovesTheAdWhateverFoundIt() {
    let set = tuning(
      show: #", "sorts": {"host_ask": "ask", "network_promo": "off", "intro_credits": "ask"}"#)
    let ads = [
      ad(0, nil, kind: .ad), ad(30, nil, kind: .ownPlug), ad(60, "meaning", kind: .promo),
      ad(90, "own-sound", kind: .credits), ad(120, "meaning", kind: .ownPlug),
    ]
    let sorted = set.apply(to: ads, show: "a")
    XCTAssertEqual(sorted.skip.map(\.start), [0])
    XCTAssertEqual(sorted.ask.map(\.start), [30, 90, 120])
    // On another show nothing is asked or dropped.
    XCTAssertEqual(set.apply(to: ads, show: "b").skip.map(\.start), [0, 30, 60, 90, 120])
  }

  func testTheStricterOfTheFinderAndTheSortDecides() {
    // repeat-sound asks by default; its sponsor ads are off for this show.
    let set = tuning(
      show: #", "sorts": {"sponsor": "off", "host_ask": "ask"}, "finders": {"meaning": "off"}"#)
    let ads = [
      ad(0, "repeat-sound", kind: .ad),  // ask and skip -> off
      ad(30, "own-sound", kind: .ownPlug),  // skip and ask -> ask
      ad(60, "meaning", kind: .ownPlug),  // off and ask -> off
      ad(90, "own-sound", kind: .promo),  // skip and skip -> skip
    ]
    let sorted = set.apply(to: ads, show: "a")
    XCTAssertEqual(sorted.skip.map(\.start), [90])
    XCTAssertEqual(sorted.ask.map(\.start), [30])
  }

  func testTheListsKeepTheOrderAndTheAdsAsTheyWere() {
    let first = ad(100, "repeat-words")
    let second = ad(10, "repeat-sound", confidence: .sure)
    let kept = ad(50, "own-sound")
    let sorted = ShowTuning().apply(to: [first, kept, second], show: "a")
    XCTAssertEqual(sorted.ask, [first, second], "not changed, not sorted by time")
    XCTAssertEqual(sorted.skip, [kept])
    let empty = ShowTuning().apply(to: [], show: "a")
    XCTAssertEqual(empty.skip, [])
    XCTAssertEqual(empty.ask, [])
  }

  // MARK: Where it runs

  func testTheFinderNamesAreTheOnesTheFileUsesAndTheFindersMustPutInSource() {
    XCTAssertEqual(ShowTuning.ownSound, "own-sound")
    XCTAssertEqual(ShowTuning.repeatSound, "repeat-sound")
    XCTAssertEqual(ShowTuning.repeatWords, "repeat-words")
    XCTAssertEqual(ShowTuning.meaning, "meaning")
    XCTAssertEqual(
      ShowTuning.finderNames,
      [ShowTuning.ownSound, ShowTuning.repeatSound, ShowTuning.repeatWords, ShowTuning.meaning])
  }

  func testItRunsOnEachFindersOwnListBeforeTheJoinBecauseAJoinedAdLosesItsSource() {
    // Two finders find nearly the same stretch. Both ask by default.
    let words = ad(100, "repeat-words")
    let sound = ad(101, "repeat-sound")
    let own = ShowTuning()
    // Right: apply to each finder's own list, and join only what may skip.
    let mine = own.apply(to: [words], show: "a")
    let theirs = own.apply(to: [sound], show: "a")
    XCTAssertEqual(mine.skip + theirs.skip, [], "no skip")
    XCTAssertEqual(mine.ask.count + theirs.ask.count, 2, "two questions")
    XCTAssertEqual(AdJoin.join(mine.skip + theirs.skip), [])
    // Wrong: after the join the ad has no source, counts as an old finder's and skips.
    let joined = AdJoin.join([words, sound])
    XCTAssertEqual(joined.count, 1)
    XCTAssertNil(joined[0].source, "two finders' names are not kept")
    let late = own.apply(to: joined, show: "a")
    XCTAssertEqual(late.skip.count, 1, "this is why the order matters")
    XCTAssertEqual(late.ask.count, 0)
  }

  // MARK: The stricter of two modes

  func testStricterIsOffThenAskThenSkip() {
    let all: [FinderMode] = [.skip, .ask, .off]
    for a in all {
      for b in all {
        let expected = all.reversed().first { $0 == a || $0 == b }
        XCTAssertEqual(ShowTuning.stricter(a, b), expected, "\(a) and \(b)")
        XCTAssertEqual(ShowTuning.stricter(a, b), ShowTuning.stricter(b, a))
      }
    }
    XCTAssertEqual(ShowTuning.stricter(.skip, .ask), .ask)
    XCTAssertEqual(ShowTuning.stricter(.ask, .off), .off)
    XCTAssertEqual(ShowTuning.stricter(.off, .skip), .off)
  }
}
