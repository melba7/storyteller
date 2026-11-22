import XCTest

@testable import PodcastAds

/// How a stream's head scan follows what the Mac taught about the show, and its diary line.
final class HeadPlanTests: XCTestCase {
  private func habits(_ episodes: Int, _ opens: Int, ends: Double? = 40) -> ShowHabits {
    var habits = ShowHabits()
    habits.shows = [.init(id: "s", episodes: episodes, opensWithAd: opens, openingEnds: ends)]
    return habits
  }

  private func range(_ confidence: AdConfidence) -> AdRange {
    AdRange(startLine: 1, endLine: 2, advertiser: "", kind: .ad, confidence: confidence)
  }

  func testAShowTheMacKnowsNothingAboutGetsTheUsualSteps() {
    let plan = HeadPlan(habits: ShowHabits(), show: "s")
    XCTAssertEqual(plan.steps, AdHeadRules.steps)
    XCTAssertEqual(plan.modelSteps, AdHeadRules.modelSteps)
    XCTAssertFalse(plan.opensWithAd)
    XCTAssertEqual(HeadPlan(habits: habits(5, 5), show: nil).steps, AdHeadRules.steps)
  }

  func testAShowThatOpensWithAnAdLooksFirstWhereItsOpeningEnds() {
    let plan = HeadPlan(habits: habits(5, 5, ends: 40), show: "s")
    XCTAssertEqual(plan.steps, AdHeadRules.steps(firstLook: 50))
    XCTAssertEqual(plan.steps.first, 50)
    XCTAssertEqual(plan.modelSteps, AdHeadRules.modelSteps(firstLook: 50))
    XCTAssertTrue(plan.modelSteps.contains(50))
    XCTAssertTrue(plan.opensWithAd)
  }

  func testUnsureAnswersCountFromTheFirstStepOnlyForAShowThatOpensWithAnAd() {
    let answer = [range(.sure), range(.unsure)]
    let usual = HeadPlan(habits: ShowHabits(), show: "s")
    XCTAssertEqual(usual.counted(answer, atStep: 30), [range(.sure)])
    XCTAssertEqual(usual.counted(answer, atStep: 60), answer)
    let opener = HeadPlan(habits: habits(5, 5), show: "s")
    XCTAssertEqual(opener.counted(answer, atStep: 30), answer)
  }

  func testTheLocalLineSaysWhatEachLayerFoundAndHowLong() {
    XCTAssertEqual(
      HeadNotes.local(ads: 2, sounds: 1, milliseconds: 35), "local: 2 ads, sounds: 1 ad in 35 ms")
    XCTAssertEqual(
      HeadNotes.local(ads: 0, sounds: 0, milliseconds: 4), "local: 0 ads, sounds: 0 ads in 4 ms")
  }

  func testWhetherAShowStartsCleanTheMacWinsWhereItKnowsTheShow() {
    XCTAssertFalse(StartHold.startsClean(habits: habits(5, 5), show: "s", own: true))
    XCTAssertTrue(StartHold.startsClean(habits: habits(5, 0), show: "s", own: false))
    XCTAssertTrue(StartHold.startsClean(habits: habits(4, 0), show: "s", own: false))
  }

  func testWhereTheMacKnowsNothingWhatThePhoneSawItselfCounts() {
    XCTAssertTrue(StartHold.startsClean(habits: ShowHabits(), show: "s", own: true))
    XCTAssertFalse(StartHold.startsClean(habits: ShowHabits(), show: "s", own: false))
    XCTAssertTrue(StartHold.startsClean(habits: habits(5, 5), show: "other", own: true))
    XCTAssertFalse(StartHold.startsClean(habits: habits(5, 0), show: nil, own: false))
    XCTAssertTrue(StartHold.startsClean(habits: habits(5, 0), show: nil, own: true))
    // Too few episodes to say either way (one of three opened with an ad is not "usually").
    XCTAssertTrue(StartHold.startsClean(habits: habits(3, 1), show: "s", own: true))
  }

  func testTheLongestWaitFollowsTheHabits() {
    XCTAssertEqual(StartHold.longest(habits: habits(5, 5), show: "s"), 5.0)
    XCTAssertEqual(StartHold.longest(habits: habits(5, 0), show: "s"), 3.0)
    XCTAssertEqual(StartHold.longest(habits: ShowHabits(), show: "s"), 3.0)
    XCTAssertEqual(StartHold.longest(habits: habits(5, 5), show: nil), 3.0)
  }
}
