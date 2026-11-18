import XCTest

@testable import PodcastTranscripts

final class QueueOrderTests: XCTestCase {
  func testTheFirstIsNextWhenNothingIsUrgent() {
    XCTAssertEqual(QueueOrder.next(waiting: ["a", "b"], urgent: nil), "a")
  }

  func testTheUrgentOneIsNextWhenItIsWaiting() {
    XCTAssertEqual(QueueOrder.next(waiting: ["a", "b", "c"], urgent: "c"), "c")
  }

  func testTheFirstIsNextWhenTheUrgentOneIsNotWaiting() {
    XCTAssertEqual(QueueOrder.next(waiting: ["a", "b"], urgent: "z"), "a")
  }

  func testNothingIsNextWhenNothingWaits() {
    XCTAssertNil(QueueOrder.next(waiting: [], urgent: "z"))
  }

  func testAPausedEpisodeGoesToTheFront() {
    XCTAssertEqual(QueueOrder.insertIndex(waiting: ["a", "b"], urgent: nil), 0)
  }

  func testAPausedEpisodeGoesBehindTheUrgentOneWhenItIsWaiting() {
    XCTAssertEqual(QueueOrder.insertIndex(waiting: ["a", "u", "b"], urgent: "u"), 2)
  }

  func testAPausedEpisodeGoesToTheFrontWhenTheUrgentOneIsNotWaiting() {
    XCTAssertEqual(QueueOrder.insertIndex(waiting: ["a", "b"], urgent: "u"), 0)
  }

  func testTheEpisodeAtWorkStopsForAnotherUrgentOneThatWaits() {
    XCTAssertTrue(QueueOrder.shouldStop(working: "a", waiting: ["u"], urgent: "u"))
  }

  func testTheUrgentEpisodeItselfDoesNotStop() {
    XCTAssertFalse(QueueOrder.shouldStop(working: "u", waiting: ["u"], urgent: "u"))
    XCTAssertFalse(QueueOrder.shouldStop(working: "u", waiting: [], urgent: "u"))
  }

  func testNothingStopsWhenTheUrgentOneIsNotWaitingOrThereIsNone() {
    XCTAssertFalse(QueueOrder.shouldStop(working: "a", waiting: ["b"], urgent: "u"))
    XCTAssertFalse(QueueOrder.shouldStop(working: "a", waiting: ["b"], urgent: nil))
  }
}
