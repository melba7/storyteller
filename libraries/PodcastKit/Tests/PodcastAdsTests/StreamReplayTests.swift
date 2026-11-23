import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// The stream replay: the reaches and times of a stream's scans, the player's skips on a stream,
/// and the bar of the jumps. Made-up episodes and a fake finder; no real transcripts.
final class StreamReplayTests: XCTestCase {
  private let settings = AdSkipSettings()

  private func ad(_ start: Double, _ end: Double, _ confidence: AdConfidence = .sure) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "", confidence: confidence, firstWords: "")
  }

  /// An episode of `seconds` seconds (lines of ten) whose marked ads are `truth`.
  private func episode(_ seconds: Int, truth: [(Double, Double)], feed: String = "f") -> TeachingEpisode {
    TeachingEpisode(
      id: "e", feed: feed, show: "S", title: "T", transcript: makeTranscript(talk(seconds / 10)),
      truth: truth.map { TeachingTruth(start: $0.0, end: $0.1, sort: "sponsor") }, maybe: [],
      onShelf: true)
  }

  /// A finder that sees an ad `[start, end]` once `seen` seconds of it are transcribed, and then
  /// reports it as far as the transcript reaches.
  private func finder(start: Double, end: Double, seen: Double) -> (Double) -> [FoundAd] {
    { reach in reach >= start + seen ? [self.ad(start, min(end, reach))] : [] }
  }

  private func jumps(
    _ episode: TeachingEpisode, pace: StreamPace = .standard, habits: ShowHabits = ShowHabits(),
    model: [FoundAd]? = nil, local: (Double) -> [FoundAd]
  ) -> [StreamJump] {
    StreamScore.jumps(
      episode: episode, habits: habits, settings: settings, pace: pace, model: model, local: local)
  }

  private func bar(_ episode: TeachingEpisode, _ jumps: [StreamJump]) -> BarTotals {
    AdBar.score(episode: episode, found: StreamReplay.asAds(jumps), settings: settings)
  }

  /// The standard pace with no wait for the model, as on a phone without Apple Intelligence.
  private var noModelWait: StreamPace {
    var pace = StreamPace.standard
    pace.waitsForModel = false
    return pace
  }

  // MARK: Pace and times

  func testThePacesHaveTheDocumentedNumbers() {
    let pace = StreamPace.standard
    XCTAssertEqual([pace.connect, pace.download, pace.speech, pace.stepOverhead], [1, 40, 12, 0.5])
    XCTAssertEqual([pace.modelPerMinute, pace.modelFloor, pace.seek], [2, 2, 1])
    XCTAssertEqual(pace.modelSeconds(forAudio: 15), 2)
    XCTAssertEqual(pace.modelSeconds(forAudio: 150), 5)
    let slow = StreamPace.slow
    XCTAssertEqual([slow.download, slow.speech, slow.connect, slow.seek], [4, 5, 1, 1])
    XCTAssertTrue(pace.summary.contains("40 s of audio downloaded"))
  }

  func testTheHeadStepsOfAShowAreDoneAtTheTimesThePaceGives() {
    let events = StreamTimeline.events(
      duration: 2700, plan: HeadPlan(habits: ShowHabits(), show: "f"), pace: .standard,
      withModel: false)
    let head = events.prefix(7)
    XCTAssertEqual(head.map(\.reach), [15, 30, 60, 90, 120, 150, 180])
    XCTAssertEqual(head[0].at, 1 + 15.0 / 40 + 15.0 / 12 + 0.5, accuracy: 1e-9)
    XCTAssertEqual(head[1].at, head[0].at + 15.0 / 12 + 0.5, accuracy: 1e-9)
    XCTAssertEqual(head[2].at, head[1].at + 30.0 / 12 + 0.5, accuracy: 1e-9)
  }

  func testTheReachesOfA45MinuteEpisodeAreTheHeadStepsThenThePiecesFromZero() {
    let events = StreamTimeline.events(
      duration: 2700, plan: HeadPlan(habits: ShowHabits(), show: "f"), pace: .standard,
      withModel: false)
    XCTAssertEqual(
      events.map(\.reach),
      [15, 30, 60, 90, 120, 150, 180, 60, 180, 480, 780, 1080, 1380, 1680, 1980, 2280, 2580, 2700])
    XCTAssertEqual(events.map(\.at), events.map(\.at).sorted())
    XCTAssertEqual(events.dropFirst(7).map(\.headStep), Array(repeating: nil, count: 11))
  }

  func testAHeadStepIsNeverPastTheEndOfAShortEpisode() {
    let events = StreamTimeline.events(
      duration: 40, plan: HeadPlan(habits: ShowHabits(), show: "f"), pace: .standard,
      withModel: false)
    XCTAssertEqual(events.prefix(3).map(\.reach), [15, 30, 40])
    XCTAssertEqual(events.last?.reach, 40)
  }

  func testAModelStepAddsASnapshotAfterTheModelsTimeAndTheNextStepWaitsForIt() {
    let plan = HeadPlan(habits: ShowHabits(), show: "f")
    let plain = StreamTimeline.events(duration: 600, plan: plan, pace: .standard, withModel: false)
    let model = StreamTimeline.events(duration: 600, plan: plan, pace: .standard, withModel: true)
    XCTAssertEqual(model.filter { $0.modelAnswers && $0.headStep != nil }.map(\.reach), [30, 60, 120, 180])
    let at30 = model.filter { $0.reach == 30 && $0.headStep != nil }
    XCTAssertEqual(at30.count, 2)
    XCTAssertEqual(at30[1].at - at30[0].at, 2, accuracy: 1e-9)  // the floor
    XCTAssertEqual(model[3].at, plain[2].at + 2, accuracy: 1e-9)  // the 60 s step waited for the model
    XCTAssertFalse(plain.contains { $0.modelAnswers })
  }

  func testTheModelsTimeInAHeadStepIsCountedOnTheWholeHeadSoFar() {
    let plan = HeadPlan(habits: ShowHabits(), show: "f")
    let events = StreamTimeline.events(duration: 600, plan: plan, pace: .standard, withModel: true)
    let step = events.first { $0.reach == 180 && $0.headStep != nil && !$0.modelAnswers }!
    let model = events.first { $0.reach == 180 && $0.headStep != nil && $0.modelAnswers }!
    XCTAssertEqual(model.at - step.at, 6, accuracy: 1e-9)  // 2 s per minute of the 3 minutes
  }

  func testTheModelsWaitIsPartOfTheHeadScanEvenWithNoAnswersUnlessThePaceSaysNot() {
    let plan = HeadPlan(habits: ShowHabits(), show: "f")
    let waiting = StreamScore.timeline(duration: 600, plan: plan, pace: .standard, model: nil)
    XCTAssertEqual(waiting.filter { $0.modelAnswers && $0.headStep != nil }.map(\.reach), [30, 60, 120, 180])
    var without = StreamPace.standard
    without.waitsForModel = false
    let plain = StreamScore.timeline(duration: 600, plan: plan, pace: without, model: nil)
    XCTAssertFalse(plain.contains { $0.modelAnswers })
    XCTAssertGreaterThan(waiting.last!.at, plain.last!.at)
    // An answer from the model always means its wait is counted.
    XCTAssertTrue(StreamScore.timeline(duration: 600, plan: plan, pace: without, model: []).contains { $0.modelAnswers })
  }

  func testAnInstantPaceKnowsEverythingBeforePlayAndChainsAdsTheWayThePlayerDoes() {
    let sample = episode(600, truth: [(100, 130), (130.3, 160)])
    let local: (Double) -> [FoundAd] = { _ in [self.ad(100, 130), self.ad(130.3, 160)] }
    let found = jumps(sample, pace: .instant, local: local)
    XCTAssertEqual(found.count, 1)  // less than half a second apart: one jump
    XCTAssertEqual(found[0].from, 100, accuracy: 0.01)
    XCTAssertEqual(found[0].to, 160, accuracy: 0.01)
  }

  func testAReadyEpisodeUsesTheFinishedFileNotWhatAHeadStepSawOnACutTranscript() {
    // On a cut transcript the finder runs the opening ad on to 44.5 s; on the whole transcript it
    // ends at 34.9 s. A ready episode holds the finished file, so the jump lands at 34.9 s.
    let sample = episode(600, truth: [(0, 35)])
    let local: (Double) -> [FoundAd] = { reach in
      reach >= 600 - 0.01 ? [self.ad(0, 34.9)] : [self.ad(0, 44.5)]
    }
    let found = jumps(sample, pace: .instant, local: local)
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found[0].to, 34.9, accuracy: 0.01)
  }

  func testTheReadyNumbersAreTheSamePlayerWithEverythingKnownAtTheStart() {
    let sample = episode(600, truth: [(0, 60)])
    let result = StreamScore.run(
      episodes: [sample], habits: ShowHabits(), settings: settings, models: nil,
      whole: { _ in [self.ad(0, 60)] },
      detect: { _, transcript in transcript.duration >= 60 ? [self.ad(0, 60)] : [] })
    XCTAssertEqual(result.finders.ready?.breaks, 1)
    XCTAssertEqual(result.finders.ready?.passed, 1)
    XCTAssertEqual(result.finders.ready?.earlyPassed, 1)
  }

  func testTheSpeechSpeedsOfTheSensitivityAreKeptBesideTheStandardNumbers() {
    let sample = episode(600, truth: [(0, 60)])
    let result = StreamScore.run(
      episodes: [sample], habits: ShowHabits(), settings: settings, models: nil,
      whole: { _ in [self.ad(0, 60)] },
      detect: { _, transcript in transcript.duration >= 60 ? [self.ad(0, 60)] : [] })
    XCTAssertEqual(result.finders.speeds?.map(\.speech), [6, 25])
    XCTAssertEqual(result.finders.speeds?.map(\.bar.breaks), [1, 1])
  }

  func testAShowThatIsNotWaitedForStartsAtTheFirstByte() {
    var habits = ShowHabits()
    habits.shows = [
      .init(id: "clean", episodes: 5, opensWithAd: 0, openingEnds: nil),
      .init(id: "opener", episodes: 5, opensWithAd: 5, openingEnds: 40),
    ]
    let pace = StreamPace.standard
    func start(_ show: String, _ done: Double?) -> Double {
      StreamTimeline.playStart(habits: habits, show: show, firstLookDone: done, pace: pace)
    }
    XCTAssertEqual(start("clean", 3.1), pace.connect)
    XCTAssertEqual(start("unknown", 3.1), 3.0)  // the hold ends first
    XCTAssertEqual(start("unknown", 2.2), 2.2)  // the first look is done first
    XCTAssertEqual(start("opener", 9), 5.0)  // the longer hold of a show that opens with an ad
  }

  // MARK: The replay

  func testASixtySecondAdTheFinderSeesAfter30SecondsIsHeardABitAndThenLeft() {
    let sample = episode(600, truth: [(0, 60)])
    let found = jumps(sample, pace: noModelWait, local: finder(start: 0, end: 60, seen: 30))
    XCTAssertEqual(found.count, 2)
    XCTAssertEqual(found[0].from, 1.875, accuracy: 0.01)  // heard from 3 s of the clock to the 30 s step
    XCTAssertEqual(found[0].to, 30, accuracy: 0.01)
    XCTAssertEqual(found[1].to, 60, accuracy: 0.01)
    let result = bar(sample, found)
    XCTAssertEqual(result.breaks, 1)
    XCTAssertEqual(result.passed, 1)
  }

  func testTheModelsWaitInTheHeadScanLeavesMoreOfThatAdHeardAndItFails() {
    let sample = episode(600, truth: [(0, 60)])
    let found = jumps(sample, local: finder(start: 0, end: 60, seen: 30))
    XCTAssertEqual(found.count, 2)
    XCTAssertEqual(found[1].from, 34, accuracy: 0.01)  // the 60 s step waited for the model at 30 s
    XCTAssertEqual(bar(sample, found).passed, 0)
  }

  func testAnAdAt20MinutesIsSkippedWhole() {
    let sample = episode(3000, truth: [(1200, 1260)])
    let found = jumps(sample, local: finder(start: 1200, end: 1260, seen: 30))
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found[0].from, 1200, accuracy: 0.1)
    XCTAssertEqual(found[0].to, 1260, accuracy: 0.01)
    XCTAssertEqual(bar(sample, found).passed, 1)
  }

  func testAnAdKnownOnlyAfterThePlayheadPassedItsEndIsHeardWhole() {
    let found = StreamReplay.play(
      snapshots: [StreamSnapshot(at: 500, ads: [ad(100, 160)])], startsAt: 1, duration: 600)
    XCTAssertEqual(found, [])
    let sample = episode(600, truth: [(100, 160)])
    let result = bar(sample, found)
    XCTAssertEqual(result.breaks, 1)
    XCTAssertEqual(result.passed, 0)
    XCTAssertEqual(result.count(.missed), 1)
  }

  func testASlowPaceTurnsAPassIntoAFail() {
    let sample = episode(600, truth: [(200, 260)])
    let local = finder(start: 200, end: 260, seen: 100)
    XCTAssertEqual(bar(sample, jumps(sample, pace: .standard, local: local)).passed, 1)
    let slow = bar(sample, jumps(sample, pace: .slow, local: local))
    XCTAssertEqual(slow.breaks, 1)
    XCTAssertEqual(slow.passed, 0)
  }

  func testTheModelsAnswersCountOnlyWhereTheyEndWithinTheReachAndAreSureAtTheFirstModelStep() {
    let plan = HeadPlan(habits: ShowHabits(), show: "f")
    let events = StreamTimeline.events(duration: 600, plan: plan, pace: .standard, withModel: true)
    let model = [ad(0, 20), ad(10, 25, .unsure), ad(100, 130)]
    let at30 = events.first { $0.reach == 30 && $0.modelAnswers }!
    XCTAssertEqual(
      StreamScore.counted(model, event: at30, opensWithAd: false).map(\.start), [0])
    XCTAssertEqual(
      StreamScore.counted(model, event: at30, opensWithAd: true).map(\.start), [0, 10])
    let at60 = events.first { $0.reach == 60 && $0.modelAnswers }!
    XCTAssertEqual(
      StreamScore.counted(model, event: at60, opensWithAd: false).map(\.start), [0, 10])
    let whole = events.last!
    XCTAssertEqual(StreamScore.counted(model, event: whole, opensWithAd: false).count, 3)
  }

  func testAnEpisodeWithAModelAnswerIsSkippedFromTheModelsMomentOn() {
    let sample = episode(600, truth: [(300, 360)])
    let found = jumps(sample, model: [ad(300, 360)], local: { _ in [] })
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found[0].to, 360, accuracy: 0.01)
    XCTAssertEqual(jumps(sample, local: { _ in [] }), [])
  }

  func testNoSnapshotEverMakesThePlayheadGoBackwards() {
    let snapshots = [
      StreamSnapshot(at: 5, ads: [ad(0, 30)]), StreamSnapshot(at: 20, ads: [ad(0, 30), ad(10, 20)]),
      StreamSnapshot(at: 40, ads: [ad(0, 90), ad(10, 20), ad(60, 80)]),
      StreamSnapshot(at: 50, ads: []),
    ]
    let found = StreamReplay.play(snapshots: snapshots, startsAt: 1, duration: 300)
    XCTAssertFalse(found.isEmpty)
    for jump in found { XCTAssertGreaterThan(jump.to, jump.from) }
    for (earlier, later) in zip(found, found.dropFirst()) {
      XCTAssertGreaterThanOrEqual(later.from, earlier.to)
    }
  }

  func testTheReplayEndsAtTheEndOfTheEpisodeEvenWithAnAdThatRunsToIt() {
    XCTAssertEqual(StreamReplay.play(snapshots: [], startsAt: 1, duration: 100), [])
    let found = StreamReplay.play(
      snapshots: [StreamSnapshot(at: 0.5, ads: [ad(40, 100)])], startsAt: 1, duration: 100)
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found[0].from, 40, accuracy: 0.01)
    XCTAssertEqual(found[0].to, 99.95, accuracy: 0.01)
    XCTAssertEqual(StreamReplay.play(snapshots: [], startsAt: 1, duration: 0), [])
  }

  func testEachReachsFindersRunOncePerEpisodeAndBothPacesReplayFromThem() {
    let sample = episode(600, truth: [(200, 260)])
    var asked: [Double] = []
    let result = StreamScore.run(
      episodes: [sample], habits: ShowHabits(), settings: settings, models: nil,
      whole: { _ in [self.ad(200, 260)] },
      detect: { _, transcript in
        asked.append(transcript.duration)
        return transcript.duration >= 300 ? [self.ad(200, min(260, transcript.duration))] : []
      })
    XCTAssertEqual(asked.count, Set(asked).count)
    XCTAssertEqual(result.finders.standard.passed, 1)
    XCTAssertEqual(result.finders.slow.passed, 0)
    XCTAssertNil(result.withModel)
  }
}
