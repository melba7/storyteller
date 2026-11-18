import XCTest

@testable import PodcastDownloads

final class StreamAnswerTests: XCTestCase {
  func testAnAskedRangeThatIsAllOnDiskIsAnsweredAndComplete() {
    let slice = StreamRules.answerable(offset: 100, length: 50, available: 1000, expected: 5000)
    XCTAssertEqual(slice, StreamSlice(offset: 100, length: 50, complete: true))
  }

  func testOnlyTheBytesThatArrivedAreAnsweredAndTheRestWaits() {
    let slice = StreamRules.answerable(offset: 100, length: 500, available: 300, expected: 5000)
    XCTAssertEqual(slice, StreamSlice(offset: 100, length: 200, complete: false))
  }

  func testNothingIsAnsweredWhileTheStartOfTheRangeIsNotThereYet() {
    let slice = StreamRules.answerable(offset: 400, length: 50, available: 300, expected: 5000)
    XCTAssertEqual(slice, StreamSlice(offset: 400, length: 0, complete: false))
  }

  func testARangeToTheEndIsCompleteOnlyWhenTheWholeFileIsThere() {
    let partway = StreamRules.answerable(offset: 0, length: nil, available: 900, expected: 1000)
    XCTAssertEqual(partway, StreamSlice(offset: 0, length: 900, complete: false))
    let whole = StreamRules.answerable(offset: 900, length: nil, available: 1000, expected: 1000)
    XCTAssertEqual(whole, StreamSlice(offset: 900, length: 100, complete: true))
  }

  func testARangeToTheEndOfAnUnknownLengthIsNeverComplete() {
    let slice = StreamRules.answerable(offset: 0, length: nil, available: 900, expected: nil)
    XCTAssertEqual(slice, StreamSlice(offset: 0, length: 900, complete: false))
  }

  func testAnAskedRangeWithAnUnknownLengthIsCompleteOnceItIsOnDisk() {
    let slice = StreamRules.answerable(offset: 0, length: 100, available: 900, expected: nil)
    XCTAssertEqual(slice, StreamSlice(offset: 0, length: 100, complete: true))
  }

  func testARangePastTheEndIsCutAtTheEnd() {
    let slice = StreamRules.answerable(offset: 900, length: 500, available: 1000, expected: 1000)
    XCTAssertEqual(slice, StreamSlice(offset: 900, length: 100, complete: true))
  }

  func testAnOffsetAtOrPastTheEndIsAnsweredEmptyAndComplete() {
    for offset: Int64 in [1000, 1500] {
      let slice = StreamRules.answerable(offset: offset, length: 10, available: 1000, expected: 1000)
      XCTAssertEqual(slice.length, 0)
      XCTAssertTrue(slice.complete)
    }
  }

  func testAnEmptyRequestIsComplete() {
    XCTAssertTrue(StreamRules.answerable(offset: 5, length: 0, available: 0, expected: nil).complete)
  }

  func testANegativeOffsetStartsAtZero() {
    let slice = StreamRules.answerable(offset: -4, length: 10, available: 100, expected: 100)
    XCTAssertEqual(slice, StreamSlice(offset: 0, length: 10, complete: true))
  }

  func testNothingOnDiskAnswersNothing() {
    let slice = StreamRules.answerable(offset: 0, length: nil, available: 0, expected: 1000)
    XCTAssertEqual(slice, StreamSlice(offset: 0, length: 0, complete: false))
  }
}

final class StreamContentTypeTests: XCTestCase {
  private func uti(_ mime: String?, enclosure: String? = nil, _ address: String = "https://x.example/a") -> String {
    StreamContentType.uti(responseType: mime, enclosureType: enclosure, url: URL(string: address))
  }

  func testTheResponsesTypeDecides() {
    XCTAssertEqual(uti("audio/mpeg"), "public.mp3")
    XCTAssertEqual(uti("audio/mp4"), "public.mpeg-4-audio")
    XCTAssertEqual(uti("audio/x-m4a"), "com.apple.m4a-audio")
    XCTAssertEqual(uti("audio/aac"), "public.aac-audio")
    XCTAssertEqual(uti("Audio/MPEG; charset=binary"), "public.mp3")
  }

  func testAnUnhelpfulResponseTypeFallsToTheFeedsTypeThenTheAddress() {
    XCTAssertEqual(uti("application/octet-stream", enclosure: "audio/x-m4a"), "com.apple.m4a-audio")
    XCTAssertEqual(uti(nil, enclosure: "audio/aac"), "public.aac-audio")
    XCTAssertEqual(uti("binary/octet-stream", "https://x.example/ep.m4a?t=1"), "com.apple.m4a-audio")
    XCTAssertEqual(uti(nil, "https://x.example/ep.aac"), "public.aac-audio")
  }

  func testTheResponseBeatsTheFeedWhenBothAreKnown() {
    XCTAssertEqual(uti("audio/mpeg", enclosure: "audio/x-m4a"), "public.mp3")
  }

  func testMp3IsTheDefault() {
    XCTAssertEqual(uti(nil), "public.mp3")
    XCTAssertEqual(uti("text/html", enclosure: "", "https://x.example/download.php"), "public.mp3")
  }
}

final class StreamThroughDownloadTests: XCTestCase {
  private func use(
    asked: Bool = true, id: String = "ep-1", hasDownload: Bool = false, wifiOnly: Bool = false,
    onWiFi: Bool = false
  ) -> Bool {
    StreamThroughDownload.shouldUse(
      asked: asked, episodeId: id, hasDownload: hasDownload, wifiOnly: wifiOnly, onWiFi: onWiFi)
  }

  func testPlaysThroughTheDownloadWhenAskedAndNothingIsDownloaded() {
    XCTAssertTrue(use())
  }

  func testAnAutomaticDownloadGivesWayWhetherOrNotBytesHaveArrived() {
    let waiting = DownloadEntry(
      episodeId: "a", url: "https://x/a.mp3", fileExtension: "mp3", state: .queued, automatic: true)
    XCTAssertTrue(StreamThroughDownload.givesWay(waiting))
    var started = waiting
    started.state = .downloading(bytes: 0, expected: nil)
    XCTAssertTrue(StreamThroughDownload.givesWay(started))
    // Part of the file is on disk, but a plain stream would skip no ad, so it still gives way.
    started.state = .downloading(bytes: 5, expected: 10)
    XCTAssertTrue(StreamThroughDownload.givesWay(started))
  }

  func testADownloadThatIsFiledOrFailedDoesNotGiveWay() {
    var entry = DownloadEntry(
      episodeId: "a", url: "https://x/a.mp3", fileExtension: "mp3", state: .queued, automatic: true)
    entry.state = .downloaded(file: "a.mp3", sha256: "x", bytes: 10, date: Date())
    XCTAssertFalse(StreamThroughDownload.givesWay(entry))
    entry.state = .failed(reason: "no")
    XCTAssertFalse(StreamThroughDownload.givesWay(entry))
  }

  func testADownloadTheListenerAskedForDoesNotGiveWay() {
    var manual = DownloadEntry(
      episodeId: "a", url: "https://x/a.mp3", fileExtension: "mp3", state: .queued,
      automatic: false)
    XCTAssertFalse(StreamThroughDownload.givesWay(manual))
    manual.state = .downloading(bytes: 5, expected: 10)
    XCTAssertFalse(StreamThroughDownload.givesWay(manual))
  }

  func testNotWhenNotAsked() {
    XCTAssertFalse(use(asked: false))
  }

  func testNotWhenTheEpisodeAlreadyHasADownloadOrOneOnItsWay() {
    XCTAssertFalse(use(hasDownload: true))
  }

  func testNotForAnAddedFileOrAPreview() {
    XCTAssertFalse(use(id: "file-3"))
    XCTAssertFalse(use(id: "preview:show:1"))
    XCTAssertFalse(use(id: ""))
  }

  func testWifiOnlyNeedsWifiNow() {
    XCTAssertFalse(use(wifiOnly: true, onWiFi: false))
    XCTAssertTrue(use(wifiOnly: true, onWiFi: true))
    XCTAssertTrue(use(wifiOnly: false, onWiFi: false))
  }
}

final class StreamSchemeTests: XCTestCase {
  func testTheSchemeIsReplacedAndTheRestKept() {
    let https = StreamScheme.customURL(for: URL(string: "https://cdn.example.com/a/ep.mp3?x=1")!)
    XCTAssertEqual(https?.absoluteString, "lofistreams://cdn.example.com/a/ep.mp3?x=1")
    let http = StreamScheme.customURL(for: URL(string: "http://cdn.example.com/ep.mp3")!)
    XCTAssertEqual(http?.absoluteString, "lofistream://cdn.example.com/ep.mp3")
  }

  func testAnythingButHttpHasNoCustomAddress() {
    XCTAssertNil(StreamScheme.customURL(for: URL(string: "file:///tmp/a.mp3")!))
  }
}
