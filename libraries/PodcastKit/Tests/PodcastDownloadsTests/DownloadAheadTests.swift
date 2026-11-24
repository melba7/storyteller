import XCTest

@testable import PodcastDownloads

final class DownloadAheadTests: XCTestCase {
  private func item(_ id: String, url: String? = nil, skipAds: Bool = true) -> DownloadAhead.Item {
    DownloadAhead.Item(id: id, url: url ?? "https://cdn.example.com/\(id).mp3", skipAds: skipAds)
  }

  private func entry(
    _ id: String, _ state: DownloadState = .queued, automatic: Bool = true, ahead: Bool = false
  ) -> DownloadEntry {
    DownloadEntry(
      episodeId: id, url: "https://cdn.example.com/\(id).mp3", fileExtension: "mp3", state: state,
      automatic: automatic, ahead: ahead)
  }

  private let filed = DownloadState.downloaded(
    file: "f.mp3", sha256: String(repeating: "a", count: 64), bytes: 10,
    date: Date(timeIntervalSince1970: 1_700_000_000))

  private func plan(
    _ upNext: [DownloadAhead.Item], playing: String? = "now", entries: [DownloadEntry] = [],
    started: Set<String> = [], onWiFi: Bool = true, lowData: Bool = false, phoneFull: Bool = false
  ) -> DownloadAhead.Plan {
    DownloadAhead.plan(
      upNext: upNext, playingId: playing, entries: entries, started: started, onWiFi: onWiFi,
      lowData: lowData, phoneFull: phoneFull)
  }

  private let four = ["a", "b", "c", "d"]

  // MARK: What starts

  func testTheNextTwoEpisodesStart() {
    XCTAssertEqual(plan(four.map { item($0) }).start, ["a", "b"])
    XCTAssertEqual(plan([item("a")]).start, ["a"])
    XCTAssertEqual(plan([]).start, [])
  }

  func testNothingStartsOffWiFi() {
    XCTAssertEqual(plan(four.map { item($0) }, onWiFi: false).start, [])
  }

  func testNothingStartsInLowDataMode() {
    XCTAssertEqual(plan(four.map { item($0) }, lowData: true).start, [])
    XCTAssertEqual(plan(four.map { item($0) }, lowData: false).start, ["a", "b"])
  }

  func testOnlyEpisodesOfShowsWithSkipAdsOnStart() {
    XCTAssertEqual(
      plan([item("a", skipAds: false), item("b"), item("c"), item("d")]).start, ["b", "c"])
    XCTAssertEqual(plan(four.map { item($0, skipAds: false) }).start, [])
  }

  func testAnEpisodeThatHasAnyDownloadIsLeftAlone() {
    let states: [(String, DownloadState)] = [
      ("waiting", .queued), ("moving", .downloading(bytes: 5, expected: 10)),
      ("filed", filed), ("failed", .failed(reason: "no")),
    ]
    for (name, state) in states {
      XCTAssertEqual(
        plan(four.map { item($0) }, entries: [entry("a", state)]).start, ["b", "c"], name)
    }
    // Also the listener's own download, and one the player is fetching as it plays.
    XCTAssertEqual(
      plan(four.map { item($0) }, entries: [entry("a", filed, automatic: false)]).start,
      ["b", "c"])
    var playThrough = entry("a", .downloading(bytes: 5, expected: nil), automatic: false)
    playThrough.playThrough = true
    XCTAssertEqual(plan(four.map { item($0) }, entries: [playThrough]).start, ["b", "c"])
  }

  func testWhatCannotBeFetchedIsSkippedAndTheNextOnesTakeItsPlace() {
    let bad = [
      item("file-0123"), item("../x"), item(""), item("preview:1"),
      item("ftp", url: "ftp://cdn.example.com/a.mp3"), item("none", url: "not a web address"),
      item("local", url: "file:///var/mobile/a.mp3"), item("nohost", url: "https:///a.mp3"),
    ]
    XCTAssertEqual(plan(bad + four.map { item($0) }).start, ["a", "b"])
    XCTAssertEqual(plan(bad).start, [])
  }

  func testTheEpisodeThatIsPlayingIsNeverFetchedAndAnEpisodeCountsOnce() {
    XCTAssertEqual(plan([item("now"), item("a"), item("a"), item("b")]).start, ["a", "b"])
    XCTAssertEqual(plan([item("a"), item("now")], playing: nil).start, ["a", "now"])
  }

  // MARK: Never more than two ahead

  func testNeverMoreThanTwoAheadAtOnce() {
    let queued = four.map { item($0) } + [item("e"), item("f")]
    // Two are ahead already, one filed and one still moving: no room for a third.
    let moving = DownloadState.downloading(bytes: 1, expected: 9)
    let two = [entry("a", filed, ahead: true), entry("b", moving, ahead: true)]
    XCTAssertEqual(plan(queued, entries: two).start, [])
    // One is ahead: room for one more, the first that has no download.
    XCTAssertEqual(plan(queued, entries: [entry("a", filed, ahead: true)]).start, ["b"])
    XCTAssertEqual(plan(queued, entries: [entry("b", .queued, ahead: true)]).start, ["a"])
  }

  func testOneThatLeftTheListDoesNotTakeUpRoom() {
    let queued = four.map { item($0) }
    // "x" is no longer in Up Next (it is dropped by this same plan), so it takes up no room.
    XCTAssertEqual(
      plan(queued, entries: [entry("x", filed, ahead: true), entry("b", filed, ahead: true)]).start,
      ["a"])
    XCTAssertEqual(
      plan(queued, entries: [entry("x", .failed(reason: "no"), ahead: true)]).start, ["a", "b"])
  }

  func testAFailedOneKeepsItsPlaceAmongTheTwoWhileItIsInUpNext() {
    let queued = four.map { item($0) }
    let no = DownloadState.failed(reason: "no")
    // One failed and one filed: no room left, so the third in line is not tried in its stead.
    XCTAssertEqual(
      plan(queued, entries: [entry("a", no, ahead: true), entry("b", filed, ahead: true)]).start,
      [])
    XCTAssertEqual(plan(queued, entries: [entry("a", no, ahead: true)]).start, ["b"])
    XCTAssertEqual(
      plan(queued, entries: [entry("a", no, ahead: true), entry("b", no, ahead: true)]).start, [])
    // The one that is playing is not in the two, failed or not.
    XCTAssertEqual(
      plan(queued, playing: "a", entries: [entry("a", no, ahead: true)]).start, ["b", "c"])
  }

  func testNothingStartsOnceThePhoneIsFull() {
    XCTAssertEqual(plan(four.map { item($0) }, phoneFull: true).start, [])
    let entries = [entry("a", filed, ahead: true), entry("b", filed, ahead: true)]
    let result = plan([item("c")], playing: "a", entries: entries, phoneFull: true)
    XCTAssertEqual(result, DownloadAhead.Plan(start: [], adopt: ["a"], drop: ["b"]))
  }

  func testAnAheadDownloadThatFailedForLackOfRoomSaysThePhoneIsFull() {
    let full = DownloadState.failed(reason: DownloadRecovery.phoneFullReason)
    XCTAssertTrue(DownloadAhead.phoneIsFull(in: [entry("a", full, ahead: true)]))
    XCTAssertTrue(DownloadAhead.phoneIsFull(in: [entry("a", filed), entry("b", full, ahead: true)]))
    // Other reasons, other states, and downloads that were never ahead do not say it.
    XCTAssertFalse(DownloadAhead.phoneIsFull(in: []))
    XCTAssertFalse(DownloadAhead.phoneIsFull(in: [entry("a", full)]))
    XCTAssertFalse(DownloadAhead.phoneIsFull(in: [entry("a", .failed(reason: "no"), ahead: true)]))
    XCTAssertFalse(DownloadAhead.phoneIsFull(in: [entry("a", filed, ahead: true)]))
    // The words come from the rule that makes them, not a copy.
    XCTAssertEqual(
      DownloadRecovery.decide(DownloadFailure(diskFull: true)),
      .fail(DownloadRecovery.phoneFullReason))
  }

  func testTheListenersOwnDownloadsDoNotUseUpTheRoom() {
    let own = [entry("a", filed, automatic: false), entry("b", filed, automatic: true)]
    XCTAssertEqual(plan(four.map { item($0) }, entries: own).start, ["c", "d"])
  }

  // MARK: Never started twice

  func testAnEpisodeStartedAheadBeforeIsNotStartedAgainAndKeepsItsPlace() {
    // Its file was deleted by the listener, so it has no entry. It is not fetched again, and it
    // still counts as one of the two, so the third episode in line is not fetched in its place.
    XCTAssertEqual(plan(four.map { item($0) }, started: ["a"]).start, ["b"])
    XCTAssertEqual(plan(four.map { item($0) }, started: ["a", "b"]).start, [])
    XCTAssertEqual(plan(four.map { item($0) }, started: ["b"]).start, ["a"])
  }

  func testAStartedEpisodeCountsOnceWithItsEntry() {
    let kept = [entry("a", filed, ahead: true)]
    XCTAssertEqual(plan(four.map { item($0) }, entries: kept, started: ["a"]).start, ["b"])
  }

  func testAStartedEpisodeThatLeftUpNextOrIsPlayingTakesUpNoRoom() {
    XCTAssertEqual(plan(four.map { item($0) }, started: ["x", "now"]).start, ["a", "b"])
    // It comes back later: it is still not fetched again.
    XCTAssertEqual(plan([item("x")] + four.map { item($0) }, started: ["x"]).start, ["a"])
  }

  // MARK: Ahead downloads that are played or no longer wanted

  func testAnAheadDownloadThatStartsPlayingIsNoLongerAhead() {
    let entries = [entry("a", filed, ahead: true), entry("b", filed, ahead: true)]
    let result = plan([item("b")], playing: "a", entries: entries)
    XCTAssertEqual(result.adopt, ["a"])
    XCTAssertEqual(result.drop, [])
    // A download that was never ahead is not touched.
    XCTAssertEqual(plan([], playing: "a", entries: [entry("a", filed)]).adopt, [])
  }

  func testAnAheadDownloadThatLeftUpNextIsDropped() {
    let entries = [
      entry("a", filed, ahead: true), entry("b", .downloading(bytes: 1, expected: 9), ahead: true),
      entry("c", .failed(reason: "no"), ahead: true), entry("d", filed, ahead: true),
    ]
    // Only "d" is still in Up Next; "a" is playing.
    let result = plan([item("d")], playing: "a", entries: entries)
    XCTAssertEqual(result.drop, ["b", "c"])
    XCTAssertEqual(plan([], playing: nil, entries: [entry("a", filed, ahead: true)]).drop, ["a"])
  }

  func testOnlyAheadDownloadsAreDropped() {
    let entries = [
      entry("a", filed, automatic: true), entry("b", filed, automatic: false),
      entry("c", .queued, automatic: true),
    ]
    XCTAssertEqual(plan([], entries: entries).drop, [])
  }

  func testDroppingAndAdoptingNeedNeitherWiFiNorSkipAds() {
    let entries = [entry("a", filed, ahead: true), entry("b", filed, ahead: true)]
    let result = plan([item("c", skipAds: false)], playing: "a", entries: entries, onWiFi: false)
    XCTAssertEqual(result, DownloadAhead.Plan(start: [], adopt: ["a"], drop: ["b"]))
  }

  func testLowDataModeStillHandsOverAndDrops() {
    let entries = [entry("a", filed, ahead: true), entry("b", filed, ahead: true)]
    let result = plan([item("c")], playing: "a", entries: entries, lowData: true)
    XCTAssertEqual(result, DownloadAhead.Plan(start: [], adopt: ["a"], drop: ["b"]))
  }

  func testAnAheadDownloadThatIsStillInUpNextIsKept() {
    let kept = [entry("a", filed, ahead: true)]
    let result = plan(four.map { item($0) }, playing: "z", entries: kept)
    XCTAssertEqual(result, DownloadAhead.Plan(start: ["b"], adopt: [], drop: []))
  }

  // MARK: When Wi-Fi comes back

  func testAnEpisodeQueuedAwayFromWiFiStartsOnceWiFiReturns() {
    var watch = DownloadAhead.NetworkWatch()
    let queued = four.map { item($0) }
    // Queued on the way home: the look at Up Next finds nothing it may start.
    XCTAssertFalse(watch.reported(onWiFi: false, lowData: false))
    XCTAssertEqual(plan(queued, onWiFi: false).start, [])
    // Home again: the report says to look, and the look starts the next two.
    XCTAssertTrue(watch.reported(onWiFi: true, lowData: false))
    XCTAssertEqual(plan(queued, onWiFi: true).start, ["a", "b"])
  }

  func testTheLookHappensOnceWhenWiFiReturnsNotOnEveryReport() {
    var watch = DownloadAhead.NetworkWatch()
    XCTAssertTrue(watch.reported(onWiFi: true, lowData: false))
    // The same network reported again (the phone does this when anything about it changes).
    XCTAssertFalse(watch.reported(onWiFi: true, lowData: false))
    XCTAssertFalse(watch.reported(onWiFi: true, lowData: false))
    // Gone and back: once more.
    XCTAssertFalse(watch.reported(onWiFi: false, lowData: false))
    XCTAssertTrue(watch.reported(onWiFi: true, lowData: false))
  }

  func testNothingIsLookedAtWhileTheNetworkStaysOneThatFetchesNothing() {
    var watch = DownloadAhead.NetworkWatch()
    // Mobile data, then none at all.
    XCTAssertFalse(watch.reported(onWiFi: false, lowData: false))
    XCTAssertFalse(watch.reported(onWiFi: false, lowData: true))
    XCTAssertFalse(watch.reported(onWiFi: false, lowData: false))
  }

  func testLowDataModeBeingTurnedOffCountsAsTheNetworkComingBack() {
    var watch = DownloadAhead.NetworkWatch()
    // On Wi-Fi in Low Data Mode, where nothing starts, so there is nothing to look at.
    XCTAssertFalse(watch.reported(onWiFi: true, lowData: true))
    XCTAssertEqual(plan(four.map { item($0) }, lowData: true).start, [])
    // Turned off: now there is.
    XCTAssertTrue(watch.reported(onWiFi: true, lowData: false))
    // Turned on again and off again: once more.
    XCTAssertFalse(watch.reported(onWiFi: true, lowData: true))
    XCTAssertTrue(watch.reported(onWiFi: true, lowData: false))
  }

  func testTheFirstReportOnWiFiAfterTheAppOpensIsALook() {
    // The network is not known until the first report, so an app that opens at home has only
    // looked at Up Next with no Wi-Fi so far.
    var watch = DownloadAhead.NetworkWatch()
    XCTAssertTrue(watch.reported(onWiFi: true, lowData: false))
    var away = DownloadAhead.NetworkWatch()
    XCTAssertFalse(away.reported(onWiFi: false, lowData: false))
  }
}
