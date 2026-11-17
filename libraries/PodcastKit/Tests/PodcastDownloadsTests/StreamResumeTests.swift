import XCTest

@testable import PodcastDownloads

final class StreamResumeTests: XCTestCase {
  func testAStrongETagIsTheValidatorAndAWeakOneIsNot() {
    XCTAssertEqual(StreamResume.validator(etag: "\"abc\"", lastModified: "Tue, 1 Jan 2030"), "\"abc\"")
    XCTAssertEqual(
      StreamResume.validator(etag: "W/\"abc\"", lastModified: "Tue, 1 Jan 2030"), "Tue, 1 Jan 2030")
  }

  func testLastModifiedIsTheValidatorWhenThereIsNoETag() {
    XCTAssertEqual(StreamResume.validator(etag: nil, lastModified: "Tue, 1 Jan 2030"), "Tue, 1 Jan 2030")
    XCTAssertEqual(StreamResume.validator(etag: " ", lastModified: "Tue, 1 Jan 2030"), "Tue, 1 Jan 2030")
  }

  func testNoValidatorMeansTheFileCannotBeProvedTheSame() {
    XCTAssertNil(StreamResume.validator(etag: nil, lastModified: nil))
    XCTAssertNil(StreamResume.validator(etag: "W/\"abc\"", lastModified: ""))
  }

  func testTheContentRangeStartIsRead() {
    XCTAssertEqual(StreamResume.contentRangeStart("bytes 100-999/1000"), 100)
    XCTAssertEqual(StreamResume.contentRangeStart("bytes 0-9/*"), 0)
    XCTAssertEqual(StreamResume.contentRangeStart("Bytes 5-9/10"), 5)
    XCTAssertNil(StreamResume.contentRangeStart("bytes */1000"))
    XCTAssertNil(StreamResume.contentRangeStart("items 1-2/3"))
    XCTAssertNil(StreamResume.contentRangeStart(nil))
    XCTAssertNil(StreamResume.contentRangeStart("bytes x-9/10"))
  }

  func testOnlyA206StartingExactlyAtTheBytesOnDiskIsAccepted() {
    XCTAssertTrue(StreamResume.accepts(status: 206, contentRange: "bytes 500-999/1000", available: 500))
    // The whole file again (the validator no longer matched), or a different start.
    XCTAssertFalse(StreamResume.accepts(status: 200, contentRange: nil, available: 500))
    XCTAssertFalse(StreamResume.accepts(status: 206, contentRange: "bytes 400-999/1000", available: 500))
    XCTAssertFalse(StreamResume.accepts(status: 206, contentRange: nil, available: 500))
    XCTAssertFalse(StreamResume.accepts(status: 416, contentRange: "bytes */1000", available: 500))
  }

  func testTheRequestAsksForTheRestOfTheSameFile() {
    XCTAssertEqual(
      StreamResume.headers(available: 500, validator: "\"abc\""),
      ["Range": "bytes=500-", "If-Range": "\"abc\"", "Accept-Encoding": "identity"])
  }

  func testADroppedConnectionWithBytesAndAValidatorIsResumed() {
    let dropped = DownloadFailure(urlErrorCode: -1005, httpStatus: 200)
    XCTAssertTrue(StreamResume.shouldResume(dropped, available: 10, validator: "\"a\"", resumes: 0))
    XCTAssertTrue(
      StreamResume.shouldResume(
        DownloadFailure(urlErrorCode: -1009), available: 10, validator: "\"a\"", resumes: 0))
  }

  func testNothingIsResumedWithoutBytesAValidatorOrARealReason() {
    let dropped = DownloadFailure(urlErrorCode: -1005)
    XCTAssertFalse(StreamResume.shouldResume(dropped, available: 0, validator: "\"a\"", resumes: 0))
    XCTAssertFalse(StreamResume.shouldResume(dropped, available: 10, validator: nil, resumes: 0))
    XCTAssertFalse(
      StreamResume.shouldResume(dropped, available: 10, validator: "\"a\"", resumes: StreamResume.maxResumes))
    XCTAssertFalse(
      StreamResume.shouldResume(
        DownloadFailure(urlErrorCode: -1005, diskFull: true), available: 10, validator: "\"a\"",
        resumes: 0))
    XCTAssertFalse(
      StreamResume.shouldResume(
        DownloadFailure(urlErrorCode: -1005, httpStatus: 503), available: 10, validator: "\"a\"",
        resumes: 0))
    XCTAssertFalse(
      StreamResume.shouldResume(
        DownloadFailure(urlErrorCode: -1022), available: 10, validator: "\"a\"", resumes: 0))
    // The listener's own cancel is not a dropped connection.
    XCTAssertFalse(
      StreamResume.shouldResume(
        DownloadFailure(urlErrorCode: -999), available: 10, validator: "\"a\"", resumes: 0))
  }

  func testADataNotAllowedFailureIsResumedAsAConnectivityWait() {
    let blocked = DownloadFailure(urlErrorCode: -1020)
    XCTAssertTrue(StreamResume.isConnectivity(blocked))
    XCTAssertTrue(
      StreamResume.shouldResume(
        blocked, available: 10, validator: "\"a\"", resumes: StreamResume.maxResumes, waits: 3))
    XCTAssertFalse(
      StreamResume.shouldResume(
        blocked, available: 10, validator: "\"a\"", resumes: 0, waits: StreamResume.maxConnectivityWaits))
    XCTAssertFalse(StreamResume.shouldResume(blocked, available: 0, validator: "\"a\"", resumes: 0))
  }

  func testAWaitForTheNetworkIsGivenUpOnlyBeforeAnyBytesArrived() {
    XCTAssertTrue(StreamResume.givesUpWaiting(available: 0))
    XCTAssertFalse(StreamResume.givesUpWaiting(available: 1))
    XCTAssertFalse(StreamResume.givesUpWaiting(available: 5_000_000))
  }

  func testTheWaitBeforeAnotherTryGrowsAndStops() {
    XCTAssertEqual(StreamResume.delay(afterResumes: 0), 2)
    XCTAssertEqual(StreamResume.delay(afterResumes: 1), 4)
    XCTAssertEqual(StreamResume.delay(afterResumes: 2), 8)
    XCTAssertEqual(StreamResume.delay(afterResumes: 10), 30)
  }

  func testAMissingNetworkWaitsAndDoesNotUseUpTheResumes() {
    let offline = DownloadFailure(urlErrorCode: -1009)
    XCTAssertTrue(StreamResume.isConnectivity(offline))
    XCTAssertTrue(StreamResume.isConnectivity(DownloadFailure(urlErrorCode: -1020)))
    XCTAssertFalse(StreamResume.isConnectivity(DownloadFailure(urlErrorCode: -1005)))
    // Five used-up resumes do not stop a wait for the network.
    XCTAssertTrue(
      StreamResume.shouldResume(
        offline, available: 10, validator: "\"a\"", resumes: StreamResume.maxResumes, waits: 3))
    // A dropped connection is still capped by the resumes, not by the waits.
    XCTAssertFalse(
      StreamResume.shouldResume(
        DownloadFailure(urlErrorCode: -1005), available: 10, validator: "\"a\"",
        resumes: StreamResume.maxResumes, waits: 0))
  }

  func testTheWaitForTheNetworkHasACap() {
    XCTAssertFalse(
      StreamResume.shouldResume(
        DownloadFailure(urlErrorCode: -1009), available: 10, validator: "\"a\"", resumes: 0,
        waits: StreamResume.maxConnectivityWaits))
  }
}
