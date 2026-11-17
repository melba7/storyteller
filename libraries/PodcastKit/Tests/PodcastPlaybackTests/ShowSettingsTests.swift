import XCTest

@testable import PodcastPlayback

final class ShowSettingsTests: XCTestCase {
  // MARK: The start

  func testAFreshEpisodeStartsAfterTheIntro() {
    XCTAssertEqual(ShowRules.start(savedPosition: 0, duration: 1800, played: false, intro: 30), 30)
  }

  func testAPlayedEpisodeStartsAfterTheIntroToo() {
    XCTAssertEqual(ShowRules.start(savedPosition: 900, duration: 1800, played: true, intro: 30), 30)
  }

  func testResumingPastTheIntroIsLeftAlone() {
    XCTAssertEqual(ShowRules.start(savedPosition: 600, duration: 1800, played: false, intro: 30), 600)
    XCTAssertEqual(ShowRules.start(savedPosition: 30, duration: 1800, played: false, intro: 30), 30)
  }

  func testResumingInsideTheIntroMovesToItsEnd() {
    XCTAssertEqual(ShowRules.start(savedPosition: 12, duration: 1800, played: false, intro: 30), 30)
  }

  func testNoIntroIsTheResumeRule() {
    XCTAssertEqual(ShowRules.start(savedPosition: 0, duration: 1800, played: false, intro: 0), 0)
    XCTAssertEqual(ShowRules.start(savedPosition: 500, duration: 1800, played: false, intro: 0), 500)
  }

  func testAnIntroLongerThanTheEpisodeDoesNothing() {
    XCTAssertEqual(ShowRules.start(savedPosition: 0, duration: 20, played: false, intro: 30), 0)
    XCTAssertEqual(ShowRules.start(savedPosition: 0, duration: 35, played: false, intro: 30), 0)
  }

  func testTheIntroIsKeptWithinOneTwentySeconds() {
    XCTAssertEqual(ShowRules.start(savedPosition: 0, duration: 3000, played: false, intro: 500), 120)
    XCTAssertEqual(ShowRules.clampedSkip(-4), 0)
    XCTAssertEqual(ShowRules.clampedSkip(.nan), 0)
  }

  func testAnUnknownLengthStillSkipsTheIntro() {
    XCTAssertEqual(ShowRules.start(savedPosition: 0, duration: nil, played: false, intro: 15), 15)
  }

  // MARK: The end

  func testTheOutroBeginsThatFarFromTheEnd() {
    XCTAssertEqual(ShowRules.outroStart(duration: 1800, outro: 45), 1755)
  }

  func testNoOutroOrNoLengthMeansNoEarlyEnd() {
    XCTAssertNil(ShowRules.outroStart(duration: 1800, outro: 0))
    XCTAssertNil(ShowRules.outroStart(duration: nil, outro: 30))
    XCTAssertNil(ShowRules.outroStart(duration: 0, outro: 30))
  }

  func testTheOutroIsClampedToTheEpisode() {
    // An outro longer than the episode cannot end it before the intro is over.
    XCTAssertEqual(ShowRules.outroStart(duration: 100, outro: 120, intro: 60), 65)
    XCTAssertEqual(ShowRules.outroStart(duration: 100, outro: 120), 5)
    XCTAssertNil(ShowRules.outroStart(duration: 40, outro: 30, intro: 120), "the end would be after the episode")
  }

  func testTheEpisodeEndsAtTheOutro() {
    XCTAssertFalse(ShowRules.shouldEnd(position: 1754.9, outroStart: 1755))
    XCTAssertTrue(ShowRules.shouldEnd(position: 1755, outroStart: 1755))
    XCTAssertFalse(ShowRules.shouldEnd(position: 99999, outroStart: nil))
  }

  // MARK: The speed

  func testTheShowsOwnSpeedBeatsThePlayers() {
    XCTAssertEqual(ShowRules.speed(show: 1.5, player: Speed.clamped(1.0)).value, 1.5)
    XCTAssertEqual(ShowRules.speed(show: 9, player: Speed.clamped(1.0)).value, 3.0)
  }

  func testWithoutAShowSpeedThePlayersIsUsed() {
    XCTAssertEqual(ShowRules.speed(show: nil, player: Speed.clamped(1.7)).value, 1.7)
    XCTAssertEqual(ShowRules.speed(show: .nan, player: Speed.clamped(1.7)).value, 1.7)
  }

  // MARK: The file

  func testTheFileRoundTripsAndKeepsEveryShow() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("show-settings-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: file) }
    let settings = [
      "a": ShowPlaybackSettings(introSeconds: 30, outroSeconds: 15, speed: 1.3, skipAds: true, skipPlugs: false),
      "b": ShowPlaybackSettings(),
    ]
    try ShowSettingsFile.save(settings, to: file)
    XCTAssertEqual(ShowSettingsFile.load(from: file), settings)
  }

  func testMissingKeysAreTheDefaultsAndABrokenFileIsEmpty() throws {
    let partial = try XCTUnwrap(ShowSettingsFile.decode(#"{"a":{"introSeconds":20},"b":{}}"#))
    XCTAssertEqual(partial["a"], ShowPlaybackSettings(introSeconds: 20))
    XCTAssertEqual(partial["b"], ShowPlaybackSettings())
    XCTAssertNil(partial["a"]?.skipAds, "null means follow the global switch")
    XCTAssertNil(ShowSettingsFile.decode("nope"))
    let missing = URL(fileURLWithPath: "/nowhere/show-settings.json")
    XCTAssertEqual(ShowSettingsFile.load(from: missing), [:])
  }

  // MARK: Up Next items

  func testAQueueFileFromBeforeShowIdsStillLoads() throws {
    let old = #"{"items":[{"id":"e1","url":"https://x.test/1.mp3","type":"audio/mpeg","title":"One","showTitle":"S","position":4}]}"#
    let queue = try JSONDecoder().decode(UpNextQueue.self, from: Data(old.utf8))
    XCTAssertEqual(queue.items.first?.id, "e1")
    XCTAssertNil(queue.items.first?.showId)
  }

  func testTheShowIdIsKeptInTheQueueFile() throws {
    let queue = UpNextQueue(items: [QueueItem(id: "e1", url: "https://x.test/1.mp3", title: "One", showId: "s1")])
    let data = try JSONEncoder().encode(queue)
    XCTAssertEqual(try JSONDecoder().decode(UpNextQueue.self, from: data).items.first?.showId, "s1")
  }
}
