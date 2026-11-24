import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// The stream replay follows the phone: the head scan asks Apple's model and waits for it only on
/// a show whose Apple level is "skip", and only the answers that skip count.
final class StreamAppleLevelTests: XCTestCase {
  private let settings = AdSkipSettings()

  private func ad(_ start: Double, _ end: Double) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "", confidence: .sure, firstWords: "",
      source: "apple-model")
  }

  private func episode(id: String, feed: String) -> TeachingEpisode {
    TeachingEpisode(
      id: id, feed: feed, show: "S", title: "T", transcript: makeTranscript(talk(60)),
      truth: [TeachingTruth(start: 200, end: 260, sort: "sponsor")], maybe: [], onShelf: true)
  }

  /// Settings that let Apple's model skip on the show whose feed is "skipper" and leave the rest.
  private let skipOnOne = ShowTuning(
    text: #"{"version": 1, "shows": [{"feed": "skipper", "finders": {"apple-model": "skip"}}]}"#)

  /// Nothing but Apple's model finds the ad, so a pass means the model's answer was used.
  private func run(_ tuning: ShowTuning, speech: Double? = nil) -> (
    finders: StreamNumbers, withModel: StreamNumbers?, waiting: Int
  ) {
    StreamScore.run(
      episodes: [episode(id: "a", feed: "skipper"), episode(id: "b", feed: "asker")],
      habits: ShowHabits(), settings: settings,
      models: ["a": [ad(200, 260)], "b": [ad(200, 260)]], tuning: tuning, speech: speech,
      whole: { _ in [] }, detect: { _, _ in [] })
  }

  func testUnderTheBuiltInDefaultNoShowWaitsForTheModelAndItsAnswersAreNotUsed() {
    let result = run(ShowTuning())
    XCTAssertEqual(result.waiting, 0)
    XCTAssertEqual(result.finders.standard.passed, 0)
    XCTAssertEqual(result.withModel?.standard, result.finders.standard)
    XCTAssertEqual(result.withModel?.slow, result.finders.slow)
    XCTAssertEqual(result.withModel?.ready, result.finders.ready)
    XCTAssertEqual(result.withModel?.speeds, result.finders.speeds)
  }

  func testAShowSetToSkipWaitsForTheModelAndUsesItsAnswersWhileTheOtherDoesNot() {
    let result = run(skipOnOne)
    XCTAssertEqual(result.waiting, 1)
    XCTAssertEqual(result.finders.standard.breaks, 2)
    XCTAssertEqual(result.finders.standard.passed, 0)
    XCTAssertEqual(result.withModel?.standard.passed, 1, "only the show that skips is helped")
    XCTAssertEqual(result.withModel?.ready?.passed, 1)
  }

  func testThePaceOfEachShowWaitsForTheModelOnlyWhereItsLevelIsSkip() {
    let plan = HeadPlan(habits: ShowHabits(), show: "f")
    for show in ["skipper", "asker", ""] {
      let waits = show == "skipper"
      let pace = StreamScore.paced(.standard, tuning: skipOnOne, show: show)
      XCTAssertEqual(pace.waitsForModel, waits, show)
      XCTAssertEqual(StreamScore.paced(.slow, tuning: skipOnOne, show: show).waitsForModel, waits)
      XCTAssertFalse(StreamScore.paced(.standard, tuning: ShowTuning(), show: show).waitsForModel)
      // Everything else about the pace stays, and a show that does not wait has no model step.
      XCTAssertEqual(pace.speech, StreamPace.standard.speech)
      let moments = StreamScore.timeline(duration: 600, plan: plan, pace: pace, model: nil)
      XCTAssertEqual(moments.contains { $0.modelAnswers }, waits, show)
    }
    let quick = StreamScore.timeline(
      duration: 600, plan: plan, pace: StreamScore.paced(.standard, tuning: ShowTuning(), show: "x"),
      model: nil)
    let slow = StreamScore.timeline(duration: 600, plan: plan, pace: .standard, model: nil)
    XCTAssertLessThan(quick.last!.at, slow.last!.at, "no wait for the model, so it is ready sooner")
  }

  func testTheReportSaysHowManyEpisodesWaitedForTheModel() {
    let rows = [(name: "Row", stream: StreamNumbers())]
    let some = StreamReport.lines(rows, waiting: (episodes: 2, of: 5)).joined(separator: "\n")
    XCTAssertTrue(some.contains("waits for Apple's model only on a show whose Apple level is skip"), some)
    XCTAssertTrue(some.contains("waits in 2 of 5 episodes"), some)
    let none = StreamReport.lines(rows, waiting: (episodes: 0, of: 5)).joined(separator: "\n")
    XCTAssertTrue(none.contains("waits in 0 of 5 episodes"), none)
    XCTAssertFalse(StreamPace.standard.summary.contains("waits for it"), "the replay decides, not the pace")
  }
}
