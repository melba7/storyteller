import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// The joint rows with the joints kept in `joints.json`: an episode with no audio file still gets
/// them, and what the cache holds is used before the audio is read.
final class ScoreCachedJointsTests: XCTestCase {
  private let text = "[0:00:00.0] hello and welcome\n[0:00:10.5] the weather is nice today\n[0:01:00.0] back to the show\n[0:01:30.0] and so it ends\n"
  private var folder: FolderWriter!
  private var printed: [String] = []

  override func setUpWithError() throws { folder = try FolderWriter() }
  override func tearDown() { folder.remove() }

  /// A cache that holds `ids` and moves every start 2 s earlier, and says who was asked.
  private func cache(_ ids: Set<String>, _ calls: SoundCalls) -> ScoreCachedJoints {
    ScoreCachedJoints(
      has: { ids.contains($0) },
      snap: { id, spans, steady in
        calls.ask("cached \(id)", steadyToo: steady)
        return spans.map { ScoreSpan(start: $0.start - 2, end: $0.end, sort: $0.sort) }
      })
  }

  private func input(_ id: String, audio: URL?) -> AdScoreInput {
    let episode = scoreEpisode(id: id, feed: "fa")
    return AdScoreInput(episode: episode, transcript: episode.transcript, audio: audio)
  }

  func testTheJointsRowsUseTheCacheForAnEpisodeWithNoAudio() {
    let calls = SoundCalls()
    let stash = ScoreEpisodeAds()
    let joints = SoundScoreLayers.joints({ _, spans, _ in spans }, stash: stash, cached: cache(["e1"], calls))
    let steady = SoundScoreLayers.steadyJoints({ _, spans, _ in spans }, stash: stash, cached: cache(["e1"], calls))
    let before = [foundAd(100, 130)]
    let one = joints.apply(input("e1", audio: nil), soFar: before)
    XCTAssertEqual(one.map(\.start), [98])
    let two = steady.apply(input("e1", audio: nil), soFar: one)
    XCTAssertEqual(two.map(\.start), [98])
    XCTAssertEqual(calls.steady, [false, true])
    // An episode that the cache does not hold, with no audio, is left as it is.
    XCTAssertEqual(joints.apply(input("e2", audio: nil), soFar: before), before)
  }

  func testTheCacheIsUsedBeforeTheAudioAndTheAudioWhenTheCacheLacksTheEpisode() {
    let calls = SoundCalls()
    let audio = URL(fileURLWithPath: "/teaching/audio/e1.mp3")
    let layer = SoundScoreLayers.joints(
      { url, spans, _ in
        calls.ask("audio \(url.lastPathComponent)")
        return spans.map { ScoreSpan(start: $0.start - 1, end: $0.end, sort: $0.sort) }
      }, stash: ScoreEpisodeAds(), cached: cache(["e1"], calls))
    XCTAssertEqual(layer.apply(input("e1", audio: audio), soFar: [foundAd(100, 130)]).map(\.start), [98])
    XCTAssertEqual(layer.apply(input("e2", audio: audio), soFar: [foundAd(100, 130)]).map(\.start), [99])
    XCTAssertEqual(calls.all, ["cached e1", "audio e1.mp3"])
  }

  func testTheSettingsRowSnapsFromTheCacheToo() {
    let calls = SoundCalls()
    let layer = SettingsScoreLayer.perShowSettings(
      tuning: ShowTuning(text: "{\"version\": 1, \"default\": {\"joints\": true, \"steadyJoints\": true}}"),
      finders: ScoreFinderAds(), snap: { _, spans, _ in spans }, cached: cache(["e1"], calls))
    let row = layer.apply(input("e1", audio: nil), soFar: [foundAd(100, 130, .sure)])
    XCTAssertEqual(row.map(\.start), [98])
    XCTAssertEqual(calls.steady, [true])
  }

  // MARK: The command

  private func fill() throws {
    try folder.write(
      "episodes.json",
      "{\"version\": 1, \"episodes\": [{\"id\": \"e1\", \"feed\": \"f1\", \"show\": \"One\", \"title\": \"T1\"},"
        + "{\"id\": \"e2\", \"feed\": \"f2\", \"show\": \"Two\", \"title\": \"T2\"}]}")
    for id in ["e1", "e2"] {
      try folder.write("transcripts/\(id).txt", text)
      try folder.write("labels/\(id).json", labelJSON(segmentJSON(start: "10", end: "40")))
    }
  }

  private func run(_ extras: ScoreExtras) -> Int32 {
    printed = []
    return AdScoreCommand.run(
      [folder.url.path, "--no-model", "--no-library", "--all"], extras: extras,
      out: { self.printed.append($0) }, err: { _ in })
  }

  private func rowNames() -> [String] {
    ScorecardHistory.load(from: folder.url.appendingPathComponent("scorecard.json")).runs.last?.rows.map(\.name) ?? []
  }

  func testAFolderWithJointsAndNoAudioStillGetsItsJointRowsAndOnlyThose() throws {
    try fill()
    let calls = SoundCalls()
    let kit = ScoreSoundKit(cachedJoints: cache(["e1"], calls))
    XCTAssertEqual(run(ScoreExtras(sounds: { _, _ in kit })), 0)
    XCTAssertEqual(
      rowNames(),
      [
        "Word rules", "Plus promo rules", "Plus repeated words", "Plus joints",
        "Plus joints (steady files too)", "Plus per-show settings",
      ])
    // Nothing found an ad in the plain talk, so there was nothing to move; the cache was never asked
    // about an episode it does not hold.
    XCTAssertTrue(calls.all.allSatisfy { $0 == "cached e1" }, "\(calls.all)")
    let output = printed.joined(separator: "\n")
    XCTAssertTrue(output.contains("joints.json"), output)
    XCTAssertTrue(output.contains("1 of 2"), output)
  }

  func testAnEpisodeWithJointsButNoMP3IsNamedAsLeftOutOfTheAudioRows() throws {
    try fill()
    try folder.write(
      "episodes.json",
      "{\"version\": 1, \"episodes\": [{\"id\": \"e1\", \"feed\": \"f1\", \"show\": \"One\", \"title\": \"T1\", \"file\": \"audio/e1.mp3\"},"
        + "{\"id\": \"e2\", \"feed\": \"f2\", \"show\": \"Two\", \"title\": \"T2\"}]}")
    try folder.write("audio/e1.mp3", "not really audio")
    let kit = ScoreSoundKit(cachedJoints: cache(["e2"], SoundCalls()))
    XCTAssertEqual(run(ScoreExtras(sounds: { _, _ in kit })), 0)
    let output = printed.joined(separator: "\n")
    XCTAssertTrue(output.contains("1 of 2 episodes have no MP3 file (e2)"), output)
    XCTAssertTrue(output.contains("joints.json"), output)
    XCTAssertFalse(output.contains("e1,"), output)
  }

  func testAKitWithNoCachedEpisodeKeepsTheOldNoteAndLeavesTheRowsOut() throws {
    try fill()
    let kit = ScoreSoundKit(cachedJoints: cache([], SoundCalls()))
    XCTAssertEqual(run(ScoreExtras(sounds: { _, _ in kit })), 0)
    XCTAssertEqual(rowNames(), ["Word rules", "Plus promo rules", "Plus repeated words", "Plus per-show settings"])
    XCTAssertTrue(printed.joined(separator: "\n").contains("No episode has an MP3 file in the teaching folder"))
  }
}
