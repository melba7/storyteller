import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// Order and settings in the whole-round test. The Mac's per-show choice (`ShowTuning.apply`) must
/// run on each new finder's OWN list, before `AdJoin` and `AdCleanup` take the finder's name
/// (`source`) away from an ad. The scorecard's settings row is the code that does it in this
/// package, so the first tests run the made show through the real rows. The finder guard can
/// only make a finder stricter than the Mac's file says, never looser.
final class RoundThreeEpisodesOrderTests: XCTestCase {
  private let one = RoundShow.one
  private let two = RoundShow.two

  // MARK: The scorecard's rows over the made show

  /// The scorecard names a show by its feed address, so its settings are read with the feed as id.
  private func scoreTuning(default block: String = "{}", show keys: String = "") -> ShowTuning {
    ShowTuning(
      text: #"{"version": 1, "default": \#(block), "shows": [{"feed": "\#(RoundShow.feed)"\#(keys)}]}"#)
  }

  private struct Rows {
    var base: [FoundAd]
    /// The ads after the two finder rows, joined by the scorecard before the settings row.
    var beforeSettings: [FoundAd]
    var settings: [FoundAd]
    var finders: ScoreFinderAds
  }

  /// Episodes one and two through the real rows: the older finders, "Plus repeated sounds" (made
  /// to hear the plug in episode two), "Plus repeated words", and the settings row last.
  private func rows(_ tuning: ShowTuning, snap: SoundCalls? = nil) -> Rows {
    let finders = ScoreFinderAds()
    let plug = (start: two.start("plug") + 1.5, end: two.end("plug") - 1)
    let sounds = SoundScoreLayers.repeatedSounds(
      { _, _, episode in episode == "e2" ? [ScoreSpan(start: plug.start, end: plug.end)] : [] },
      finders: finders)
    let words = WordScoreLayers.repeatedWords(now: RoundShow.now, finders: finders)
    var moving: (@Sendable (URL, [ScoreSpan], Bool) -> [ScoreSpan])?
    if let calls = snap {
      moving = { url, spans, steady in
        calls.ask(url.lastPathComponent, steadyToo: steady)
        return spans.map { ScoreSpan(start: $0.start - 1, end: $0.end + 1, sort: $0.sort) }
      }
    }
    let settings = SettingsScoreLayer.perShowSettings(tuning: tuning, finders: finders, snap: moving)
    var last = Rows(base: [], beforeSettings: [], settings: [], finders: finders)
    for episode in [one, two] {
      let input = AdScoreInput(
        episode: TeachingEpisode(
          id: episode.id, feed: RoundShow.feed, show: "Round", title: episode.id,
          transcript: episode.transcript, truth: [], maybe: [], onShelf: true,
          seconds: episode.transcript.duration),
        transcript: episode.transcript,
        audio: URL(fileURLWithPath: "/teaching/audio/\(episode.id).mp3"))
      let base = LocalAds().ads(transcript: episode.transcript, episodeDuration: episode.transcript.duration)
      _ = finders.baseRow.apply(input, soFar: base)
      let joined = words.apply(input, soFar: sounds.apply(input, soFar: base))
      last = Rows(base: base, beforeSettings: joined, settings: settings.apply(input, soFar: joined), finders: finders)
    }
    return last
  }

  func testTwoFindersThatOnlyAskDoNotSkipWhenTheirAdsAreJoined() {
    let run = rows(scoreTuning())
    // Both finders heard the plug, each on its own (the words also heard the quiz). Both ask by
    // default.
    let ofWords = run.finders.ads(finder: ShowTuning.repeatWords, for: "e2")
    let ofSound = run.finders.ads(finder: ShowTuning.repeatSound, for: "e2")
    XCTAssertEqual(ofWords.count, 2)
    XCTAssertEqual(ofSound.count, 1)
    XCTAssertTrue(run.beforeSettings.contains { $0.source == ShowTuning.repeatSound }, "\(run.beforeSettings)")
    // The row that applies the settings gives back exactly what the older finders found.
    XCTAssertEqual(run.settings, run.base)
    // Why the order matters, with these very lists: joined first, the two names are lost and the
    // one ad has no source, so the settings would take it for an older finder's and let it skip.
    let joined = AdJoin.join(ofWords + ofSound)
    XCTAssertEqual(joined.count, 2, "the plug of both finders is one ad, the quiz another")
    XCTAssertNil(joined.first?.source)
    XCTAssertEqual(joined.last?.source, ShowTuning.repeatWords)
    XCTAssertEqual(scoreTuning().apply(to: joined, show: RoundShow.feed).skip.count, 1)
    XCTAssertEqual(scoreTuning().apply(to: ofWords, show: RoundShow.feed).skip, [])
    XCTAssertEqual(scoreTuning().apply(to: ofSound, show: RoundShow.feed).skip, [])
  }

  func testAFinderTheFileLetsSkipSkipsAndTheOneThatAsksStillDoesNot() throws {
    let run = rows(scoreTuning(show: #", "finders": {"repeat-words": "skip"}"#))
    let added = run.settings.filter { !run.base.contains($0) }
    XCTAssertEqual(added.map(\.source), [ShowTuning.repeatWords, ShowTuning.repeatWords], "the plug and the quiz")
    XCTAssertTrue(added.allSatisfy { $0.confidence == .unsure }, "a new finder alone is unsure at most")
    XCTAssertFalse(run.settings.contains { $0.source == ShowTuning.repeatSound })
    // Each finder's own list is cut back to the older finders only, so the part the sound finder
    // heard is not lost to a finder that only asks.
    XCTAssertEqual(try XCTUnwrap(added.first).start, two.start("plug"), accuracy: 5)
    XCTAssertEqual(try XCTUnwrap(added.first).end, two.end("plug"), accuracy: 5)
  }

  func testTheJointsAreAppliedLastAndOnlyWhereTheSettingsLetThem() {
    let on = SoundCalls()
    let withJoints = rows(scoreTuning(show: #", "finders": {"repeat-words": "skip"}"#), snap: on)
    XCTAssertEqual(on.all, ["e1.mp3", "e2.mp3"], "one snap for each episode, after the settings chose the ads")
    XCTAssertEqual(withJoints.settings.count, withJoints.base.count + 2)
    let off = SoundCalls()
    let without = rows(
      scoreTuning(default: #"{"joints": false}"#, show: #", "finders": {"repeat-words": "skip"}"#), snap: off)
    XCTAssertEqual(off.all, [], "joints are off: the borders stay where the finders put them")
    XCTAssertEqual(without.settings.count, withJoints.settings.count)
  }

  func testWithEveryFinderAndTheJointsOffTheSettingsRowGivesTheOlderFindersExactly() {
    let calls = SoundCalls()
    let run = rows(
      scoreTuning(
        default:
          #"{"finders": {"own-sound": "off", "repeat-sound": "off", "repeat-words": "off", "meaning": "off"}, "joints": false}"#),
      snap: calls)
    XCTAssertNotEqual(run.beforeSettings, run.base, "the finder rows did add their ads")
    XCTAssertEqual(run.settings, run.base, "same ads, same starts and ends, same order")
    XCTAssertEqual(calls.all, [], "and no border was moved")
  }

  // MARK: The finder guard only makes a finder stricter

  private let undoneTwice: (inout FinderGuard) -> Void = { guardFile in
    for _ in 0..<2 { guardFile.undone(finder: ShowTuning.repeatWords, show: RoundShow.show, now: RoundShow.now) }
  }
  private let deniedTwice: (inout FinderGuard) -> Void = { guardFile in
    for _ in 0..<2 { guardFile.denied(finder: ShowTuning.repeatWords, show: RoundShow.show, now: RoundShow.now) }
  }

  /// The made show's plug in episode two: skipped, only asked, or neither, for a file that says
  /// `level` and a guard that has heard `answers`.
  private func plug(
    file level: String, guard answers: ((inout FinderGuard) -> Void)? = nil
  ) throws -> (skipped: Bool, asked: Bool, ran: Bool) {
    // A folder of its own: a file saved earlier would carry its questions into this one.
    let own = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: own) }
    var phone = RoundPhone(
      folder: own, tuning: RoundShow.tuning(show: #", "finders": {"repeat-words": "\#(level)"}"#))
    if let answers { answers(&phone.guardFile) }
    try phone.finish(one)
    let file = try phone.finish(two).file
    return (
      RoundPhone.touches(file, two.start("plug"), two.end("plug")),
      AdAsking.open(in: file).contains { abs($0.start - two.start("plug")) <= 5 },
      phone.ran.contains(ShowTuning.repeatWords)
    )
  }

  func testTheGuardTurnsASkipIntoAQuestionOrIntoNothingButNeverTheOtherWay() throws {
    // The file lets the repeat of words skip. With no answers the guard agrees and it skips.
    var made = try plug(file: "skip")
    XCTAssertTrue(made.skipped)
    XCTAssertFalse(made.asked)
    // Two undone skips make the guard say "ask": the plug becomes a question.
    made = try plug(file: "skip", guard: undoneTwice)
    XCTAssertFalse(made.skipped)
    XCTAssertTrue(made.asked)
    // Two "not an ad" answers make it say "off": the finder does not run.
    made = try plug(file: "skip", guard: deniedTwice)
    XCTAssertEqual([made.skipped, made.asked, made.ran], [false, false, false])
    // A guard that is content never loosens the file: ask stays ask, and off stays off.
    made = try plug(file: "ask")
    XCTAssertEqual([made.skipped, made.asked], [false, true])
    made = try plug(file: "off")
    XCTAssertEqual([made.skipped, made.asked, made.ran], [false, false, false])
    // And the guard's "ask" does not loosen a file's "off".
    made = try plug(file: "off", guard: undoneTwice)
    XCTAssertEqual([made.skipped, made.asked, made.ran], [false, false, false])
  }

  func testTheStricterOfTheFileAndTheGuardDecidesInEveryCase() {
    let file: [FinderMode] = [.skip, .ask, .off]
    let answers: [((inout FinderGuard) -> Void)?] = [nil, undoneTwice, deniedTwice]
    let guardSays: [FinderMode] = [.skip, .ask, .off]
    let expected: [[FinderMode]] = [[.skip, .ask, .off], [.ask, .ask, .off], [.off, .off, .off]]
    for (f, level) in file.enumerated() {
      for (g, give) in answers.enumerated() {
        var guardFile = FinderGuard(appBuild: "1")
        give?(&guardFile)
        let mode = guardFile.mode(
          finder: ShowTuning.repeatWords, show: RoundShow.show, episode: "e2", now: RoundShow.now)
        XCTAssertEqual(mode, guardSays[g])
        let tuning = RoundShow.tuning(show: #", "finders": {"repeat-words": "\#(level.rawValue)"}"#)
        let chosen = ShowTuning.stricter(
          tuning.level(forFinder: ShowTuning.repeatWords, show: RoundShow.show), mode)
        XCTAssertEqual(chosen, expected[f][g], "file \(level), guard \(mode)")
      }
    }
  }
}
