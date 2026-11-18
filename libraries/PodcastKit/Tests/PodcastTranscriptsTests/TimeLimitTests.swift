import XCTest

@testable import PodcastTranscripts

final class TimeLimitTests: XCTestCase {
  func testAFastOperationGivesItsResult() async throws {
    let value = try await withTimeLimit(seconds: 5, message: "late") { 42 }
    XCTAssertEqual(value, 42)
  }

  func testAnOperationThatNeverReturnsEndsWithTheMessage() async {
    do {
      _ = try await withTimeLimit(seconds: 0.1, message: "took too long") { () async throws -> Int in
        // Ignores the cancel on purpose: the limit must not wait for it.
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
        return 1
      }
      XCTFail("should have timed out")
    } catch {
      XCTAssertEqual(error as? TranscriptError, .failed("took too long"))
    }
  }

  func testAnErrorFromTheOperationIsPassedOn() async {
    struct Boom: Error {}
    do {
      _ = try await withTimeLimit(seconds: 5, message: "late") { () async throws -> Int in throw Boom() }
      XCTFail("should have thrown")
    } catch {
      XCTAssertTrue(error is Boom)
    }
  }
}
