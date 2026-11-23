import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// The lines the scorecard prints besides its rows: what the joints and the settings did, the
/// questions the phone would ask, and how the phone's own habits compare with the Mac's.
final class AdScoreNotesTests: XCTestCase {
  private func row(
    _ name: String, ad: Double = 300, heard: Double, cut: Double, before: Double = 0, after: Double = 0,
    episodes: Int = 3
  ) -> ScorecardRow {
    var total = ScoreTotals()
    total.episodes = episodes
    total.adSeconds = ad
    total.heardSeconds = heard
    total.cutSeconds = cut
    total.heardBeforeSeconds = before
    total.heardAfterSeconds = after
    return ScorecardRow(name: name, total: total, shows: [])
  }

  // MARK: What the joints and the settings did

  func testJointsThatFindMoreAndCutAboutAsMuchPay() {
    let lines = AdScoreNotes.rowLines([
      row("Plus repeated words", heard: 100, cut: 50, before: 30, after: 20),
      row(ScoreRows.joints, heard: 80, cut: 50.4, before: 10, after: 18),
    ])
    XCTAssertEqual(lines.count, 1)
    XCTAssertTrue(lines[0].contains("Joints: right seconds 3 min 40 s (3 min 20 s before)"), lines[0])
    XCTAssertTrue(lines[0].contains("before the skip 10 s (30 s)"), lines[0])
    XCTAssertTrue(lines[0].hasSuffix("Joints pay."), lines[0])
  }

  func testJointsThatCutMoreThanOneInAHundredDoNotPay() {
    let lines = AdScoreNotes.rowLines([
      row("Plus repeated words", heard: 100, cut: 50),
      row(ScoreRows.joints, heard: 80, cut: 51),
    ])
    XCTAssertTrue(lines[0].hasSuffix("Joints do not pay: show time cut by mistake rose by more than one in a hundred."), lines[0])
  }

  func testJointsThatFindNoMoreDoNotPay() {
    let lines = AdScoreNotes.rowLines([
      row("Plus repeated words", heard: 100, cut: 50), row(ScoreRows.joints, heard: 100, cut: 40),
    ])
    XCTAssertTrue(lines[0].hasSuffix("Joints do not pay: no more of the ad time is skipped."), lines[0])
  }

  func testTheSteadyRowIsJudgedAgainstThePlainJointsRow() {
    let lines = AdScoreNotes.rowLines([
      row("Plus repeated words", heard: 100, cut: 50), row(ScoreRows.joints, heard: 80, cut: 50),
      row(ScoreRows.steadyJoints, heard: 70, cut: 50),
    ])
    XCTAssertEqual(lines.count, 2)
    XCTAssertTrue(lines[1].hasPrefix("Joints in steady files too: right seconds 3 min 50 s (3 min 40 s before)"), lines[1])
    XCTAssertTrue(lines[1].hasSuffix("Steady files should be used too."), lines[1])
  }

  func testTheSettingsHoldWhenTheyKeepTheRightSecondsAndCutNoMore() {
    let lines = AdScoreNotes.rowLines([
      row(ScoreRows.steadyJoints, heard: 80, cut: 60), row(ScoreRows.settings, heard: 80, cut: 30),
    ])
    XCTAssertEqual(lines.count, 1)
    XCTAssertTrue(lines[0].contains("Per-show settings: right seconds 3 min 40 s (3 min 40 s in the row above), wrong seconds 30 s (1 min 00 s)"), lines[0])
    XCTAssertTrue(lines[0].hasSuffix("The check holds."), lines[0])
  }

  func testTheSettingsDoNotHoldWhenTheyGiveUpRightSecondsOrCutMore() {
    let lost = AdScoreNotes.rowLines([
      row(ScoreRows.steadyJoints, heard: 80, cut: 60), row(ScoreRows.settings, heard: 120, cut: 10),
    ])
    XCTAssertTrue(lost[0].hasSuffix("The check does not hold: right seconds fell by 40 s."), lost[0])
    let more = AdScoreNotes.rowLines([
      row(ScoreRows.steadyJoints, heard: 80, cut: 60), row(ScoreRows.settings, heard: 80, cut: 70),
    ])
    XCTAssertTrue(more[0].hasSuffix("The check does not hold: wrong seconds rose by 10 s."), more[0])
  }

  func testRowsThatAreNotThereOrHaveNothingBeforeThemSayNothing() {
    XCTAssertEqual(AdScoreNotes.rowLines([]), [])
    XCTAssertEqual(AdScoreNotes.rowLines([row(ScoreRows.joints, heard: 1, cut: 0)]), [])
    XCTAssertEqual(AdScoreNotes.rowLines([row("Word rules", heard: 1, cut: 0)]), [])
  }

  // MARK: What each finder row did

  /// A row before it with 100 right seconds (300 of ad, 200 heard) and 10 wrong, and a finder row
  /// that adds `right` right seconds and `wrong` wrong seconds to it.
  private func finder(
    _ name: String, right: Double, wrong: Double, episodes: Int = 3
  ) -> [ScorecardRow] {
    [
      row("Plus promo rules", heard: 200, cut: 10),
      row(name, heard: 200 - right, cut: 10 + wrong, episodes: episodes),
    ]
  }

  func testAFinderThatCutsMoreShowThanItFindsOfAdIsTurnedOffByTheMac() {
    let lines = AdScoreNotes.rowLines(finder(ScoreRows.repeatedWords, right: 4, wrong: 10))
    XCTAssertEqual(
      lines,
      ["Plus repeated words: found 4 s more right seconds and 10 s more wrong seconds. The next Teach the phone again turns it off for every show."])
  }

  func testAFinderUnderEightyFivePercentAndSkippingByDefaultOnlyAsksAfterTheNextTeach() {
    // 8 of 10 added seconds are ad: 80 percent. Own sounds and the meaning model skip by default.
    for name in [ScoreRows.ownSounds, ScoreRows.meaning] {
      let lines = AdScoreNotes.rowLines(finder(name, right: 8, wrong: 2))
      XCTAssertEqual(
        lines,
        ["\(name): found 8 s more right seconds and 2 s more wrong seconds. The next Teach the phone again makes it only ask on every show."])
    }
  }

  func testAFinderThatAlreadyOnlyAsksOrIsPreciseStaysAsItIs() {
    // The repeat finders only ask by default, so low precision changes nothing.
    for name in [ScoreRows.repeatedSounds, ScoreRows.repeatedWords] {
      let lines = AdScoreNotes.rowLines(finder(name, right: 8, wrong: 2))
      XCTAssertTrue(lines[0].hasSuffix("It stays as it is overall."), lines[0])
    }
    // Exactly 85 percent is not under it (the Mac's rule is right * 100 < 85 * (right + wrong)).
    let precise = AdScoreNotes.rowLines(finder(ScoreRows.ownSounds, right: 17, wrong: 3))
    XCTAssertTrue(precise[0].hasSuffix("It stays as it is overall."), precise[0])
    // Equal right and wrong seconds are not worse; they are imprecise.
    let even = AdScoreNotes.rowLines(finder(ScoreRows.ownSounds, right: 5, wrong: 5))
    XCTAssertTrue(even[0].hasSuffix("makes it only ask on every show."), even[0])
  }

  func testAFinderThatAddsNothingStaysAsItIs() {
    let lines = AdScoreNotes.rowLines(finder(ScoreRows.meaning, right: 0, wrong: 0))
    XCTAssertEqual(
      lines, ["Plus the meaning model: found 0 s more right seconds and 0 s more wrong seconds. It stays as it is overall."])
  }

  func testAFinderOverFewerThanThreeEpisodesIsNotJudgedByTheMac() {
    let lines = AdScoreNotes.rowLines(finder(ScoreRows.repeatedWords, right: 1, wrong: 30, episodes: 2))
    XCTAssertTrue(
      lines[0].hasSuffix("The Mac judges a finder only over 3 or more marked episodes, so it stays as it is."),
      lines[0])
  }

  func testAFinderThatLostRightSecondsIsSaidSoAndTheFinderLinesComeBeforeTheJointsLines() {
    let lines = AdScoreNotes.rowLines([
      row("Plus promo rules", heard: 100, cut: 0), row(ScoreRows.ownSounds, heard: 110, cut: 5),
      row(ScoreRows.joints, heard: 90, cut: 5),
    ])
    XCTAssertEqual(lines.count, 2)
    XCTAssertTrue(lines[0].hasPrefix("Plus the phone's own sounds: found 10 s fewer right seconds and 5 s more wrong seconds."), lines[0])
    XCTAssertTrue(lines[0].hasSuffix("turns it off for every show."), lines[0])
    XCTAssertTrue(lines[1].hasPrefix("Joints:"), lines[1])
    // A finder row that is first in the list has no row before it to be set against.
    XCTAssertEqual(AdScoreNotes.rowLines([row(ScoreRows.ownSounds, heard: 1, cut: 0)]), [])
  }

  // MARK: Questions

  /// A word model where "hi" lines are surely an ad, "mid" lines have a chance of about 0.555.
  private var model: AdWordModel {
    func key(_ feature: String) -> String { String(AdWordModel.bucket(feature, buckets: 262144)) }
    let weights: [String: Any] = [
      key("#bias"): [5.0, 0.0, 0.0, 0.0, 0.0],
      key("u:hi"): [-7.0, 7.0, 0.0, 0.0, 0.0],
      key("u:mid"): [-2.5, 2.5, 0.0, 0.0, 0.0],
    ]
    let json: [String: Any] = [
      "version": 1, "buckets": 262144, "classes": AdWordModel.classes, "weights": weights,
    ]
    return AdWordModel(data: try! JSONSerialization.data(withJSONObject: json))!
  }

  /// An episode of lines of five seconds, six seconds apart, with the given words, and the
  /// stretches marked as sponsor ads.
  private func episode(_ id: String, _ words: [String], ads: [(Double, Double)] = []) -> TeachingEpisode {
    let lines = words.enumerated().map {
      TranscriptLine(start: Double($0.offset) * 6, end: Double($0.offset) * 6 + 5, text: $0.element)
    }
    let identity = TranscriptIdentity(
      locale: "en-US", recogniser: "Fake", recogniserVersion: "1", osVersion: "", sha256: id)
    let transcript = Transcript(
      identity: identity, duration: Double(words.count) * 6, lines: lines, words: [])
    return TeachingEpisode(
      id: id, feed: "f", show: "S", title: id, transcript: transcript,
      truth: ads.map { TeachingTruth(start: $0.0, end: $0.1, sort: "sponsor") }, maybe: [], onShelf: true)
  }

  private let asking = ["plain", "plain", "mid", "mid", "mid", "mid", "plain", "plain", "plain", "plain"]

  func testQuestionsAreCountedAnHourAndAgainstTheLabels() {
    // Two episodes of 60 seconds, each with one question (12 to 35 s). The first question is
    // over a marked ad, the second is not.
    let episodes = [episode("a", asking, ads: [(12, 35)]), episode("b", asking)]
    let counted = AdScoreNotes.questions(
      model: model, episodes: episodes, finalAds: { _ in [] }, from: AdAsks.askFrom)
    XCTAssertEqual(counted.count, 2)
    XCTAssertEqual(counted.wereAds, 1)
    XCTAssertEqual(counted.hours, 120.0 / 3600, accuracy: 1e-9)
    let lines = AdScoreNotes.questionLines(counted)
    XCTAssertTrue(lines[0].contains("2 questions over 2 min 00 s"), lines[0])
    XCTAssertTrue(lines[0].contains("60.0 an hour"), lines[0])
    XCTAssertTrue(lines[0].contains("1 of 2 were ads (50%)"), lines[0])
    // The line says plainly what it does not count.
    XCTAssertTrue(
      lines[0].hasSuffix("Only the word model's questions are counted, not the repeat finders' or the meaning model's."),
      lines[0])
    XCTAssertTrue(lines[1].contains("at most 2 an hour and at least half of them ads"), lines[1])
    XCTAssertTrue(
      lines[1].hasSuffix(
        "Not met: too many questions an hour. The phone still asks, at most 3 an episode, and every ad it was unsure of is still skipped with Undo, so nothing is lost; tell Claude and the cutoff will be raised (the Mac does not change it by itself yet)."),
      lines[1])
  }

  func testQuestionsOutsideTheAdsOfTheLastRowOnly() {
    let episodes = [episode("a", asking)]
    let covered = AdScoreNotes.questions(
      model: model, episodes: episodes, finalAds: { _ in [foundAd(10, 40)] }, from: AdAsks.askFrom)
    XCTAssertEqual(covered.count, 0)
  }

  func testTheStartingGateIsMetWithFewQuestionsMostlyAds() {
    let long = asking + [String](repeating: "plain", count: 990)
    let counted = AdScoreNotes.questions(
      model: model, episodes: [episode("a", long, ads: [(12, 35)])], finalAds: { _ in [] },
      from: AdAsks.askFrom)
    XCTAssertEqual(counted.count, 1)
    let lines = AdScoreNotes.questionLines(counted)
    XCTAssertTrue(
      lines[1].hasSuffix(
        "Met. The phone asks with the cutoff in show-settings.json (0.35 unless the Mac chose another)."),
      lines[1])
    XCTAssertFalse(lines.joined().contains("\u{2014}"))
  }

  func testNoQuestionsAndNoTimeSayPlainWords() {
    let none = AdScoreNotes.questions(model: model, episodes: [], finalAds: { _ in [] }, from: 0.35)
    XCTAssertEqual(none.count, 0)
    XCTAssertEqual(AdScoreNotes.questionLines(none), ["Questions: there is no transcript time to count over."])
    let quiet = AdScoreNotes.questions(
      model: model, episodes: [episode("a", ["plain", "plain"])], finalAds: { _ in [] }, from: 0.35)
    XCTAssertTrue(AdScoreNotes.questionLines(quiet)[0].hasPrefix("Questions: none in "), "\(quiet)")
  }

  // MARK: Habits

  private func habits(_ json: String) -> ShowHabits { ShowHabits(data: Data(json.utf8)) ?? ShowHabits() }

  private func opening(_ end: Double) -> [FoundAd] { [foundAd(0, end)] }

  func testTheShowsWhoseOwnHabitsMatchTheMacsAreCounted() {
    // Three episodes each of two shows. "fa" opens with an ad that ends at 40 s on the Mac and on
    // the phone; "fb" opens with an ad on the phone, never on the Mac.
    func eps(_ feed: String) -> [TeachingEpisode] {
      (1...3).map { n in
        var e = episode("\(feed)\(n)", asking)
        e.feed = feed
        return e
      }
    }
    let mac = habits(
      """
      {"version":1,"shows":[
        {"id":"fa","episodes":4,"opensWithAd":4,"openingEnds":42.0},
        {"id":"fb","episodes":4,"opensWithAd":0}]}
      """)
    let lines = AdScoreNotes.habitLines(episodes: eps("fa") + eps("fb"), mac: mac) { episode, _ in
      opening(episode.feed == "fa" ? 40 : 30)
    }
    XCTAssertEqual(lines, ["Own habits agree with the Mac's habits for 1 of 2 shows."])
  }

  func testAShowWithTooFewEpisodesOnEitherSideIsLeftOutAndSaid() {
    let two = (1...2).map { n -> TeachingEpisode in
      var e = episode("x\(n)", asking)
      e.feed = "fa"
      return e
    }
    let mac = habits("{\"version\":1,\"shows\":[{\"id\":\"fa\",\"episodes\":5,\"opensWithAd\":5,\"openingEnds\":40}]}")
    let lines = AdScoreNotes.habitLines(episodes: two, mac: mac) { _, _ in opening(40) }
    XCTAssertEqual(
      lines,
      ["Own habits agree with the Mac's habits for 0 of 0 shows (1 show has fewer than 3 episodes on the phone's side or the Mac's, and is left out)."])
  }

  func testNoMacHabitsMeansNothingToCompare() {
    let lines = AdScoreNotes.habitLines(episodes: [episode("a", asking)], mac: ShowHabits()) { _, _ in [] }
    XCTAssertEqual(lines, ["Own habits were not compared: there is no habits.json for the Mac's side."])
  }

  func testTheOwnOpeningEndMustBeWithinTenSecondsOfTheMacs() {
    func eps() -> [TeachingEpisode] {
      (1...3).map { n in
        var e = episode("fa\(n)", asking)
        e.feed = "fa"
        return e
      }
    }
    let mac = habits("{\"version\":1,\"shows\":[{\"id\":\"fa\",\"episodes\":4,\"opensWithAd\":4,\"openingEnds\":80}]}")
    let far = AdScoreNotes.habitLines(episodes: eps(), mac: mac) { _, _ in opening(40) }
    XCTAssertEqual(far, ["Own habits agree with the Mac's habits for 0 of 1 show."])
    let near = AdScoreNotes.habitLines(episodes: eps(), mac: mac) { _, _ in opening(72) }
    XCTAssertEqual(near, ["Own habits agree with the Mac's habits for 1 of 1 show."])
  }
}
