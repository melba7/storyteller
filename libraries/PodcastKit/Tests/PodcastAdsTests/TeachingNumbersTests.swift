import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// Numbers read from the Mac's files must not be able to overflow or give NaN on the phone.
final class TeachingNumbersTests: XCTestCase {
  func testAModelWithHugeWeightsIsRefused() {
    let bias = String(AdWordModel.bucket("#bias", buckets: 262144))
    func data(_ weight: String) -> Data {
      Data(
        "{\"version\":1,\"buckets\":262144,\"classes\":[\"none\",\"sponsor\",\"network_promo\",\"host_ask\",\"intro_credits\"],\"weights\":{\"\(bias)\":[3,0,0,0,0],\"5\":[\(weight),0,0,0,0]}}"
          .utf8)
    }
    XCTAssertNotNil(AdWordModel(data: data("2.5")))
    XCTAssertNil(AdWordModel(data: data("1e300")))
    XCTAssertNil(AdWordModel(data: data("-1e300")))
  }

  func testHabitsWithHugeCountsSayNothingAndDoNotCrash() throws {
    let json = """
      {"version":1,"shows":[{"id":"a","episodes":9223372036854775807,"opensWithAd":9223372036854775807,"openingEnds":30}]}
      """
    let habits = try XCTUnwrap(ShowHabits(data: Data(json.utf8)))
    XCTAssertFalse(habits.usuallyOpensWithAd(show: "a"))
    XCTAssertFalse(habits.startsClean(show: "a"))
  }

  func testALibraryEntrySeenHugeIsKeptWithinABound() {
    let text = (0..<40).map { "word\($0)" }.joined(separator: " ")
    let json = """
      {"version":1,"ads":[{"show":"s","scope":"all","sort":"sponsor","who":"A","text":"\(text)","length":30,"seen":9223372036854775807}]}
      """
    var seeds = AdLibrary.seeds(from: Data(json.utf8), now: Date())
    XCTAssertEqual(seeds.ads.count, 1)
    XCTAssertLessThanOrEqual(seeds.ads[0].seen, 1_000_000)
    seeds.ads[0].seen += 1  // adding to it must not overflow
  }
}
