import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// Where a skip starts and ends around the words (ads review fixes).
final class AdLandingTests: XCTestCase {
  private func words(_ times: [(Double, Double)]) -> [TranscriptWord] {
    times.enumerated().map { TranscriptWord(text: "w\($0.offset)", start: $0.element.0, end: $0.element.1) }
  }

  /// One-second words from `from` up to `to`.
  private func seconds(_ from: Int, _ to: Int) -> [(Double, Double)] {
    (from..<to).map { (Double($0), Double($0 + 1)) }
  }

  // MARK: The start goes to zero only near the top of the episode

  func testAnAdWhoseFirstWordIsTheTranscriptsFirstAndComesLateLandsBeforeIt() {
    // Nothing is said until 40 s: theme music or a cold open lies before the ad.
    let spoken = words(seconds(40, 120))
    XCTAssertEqual(AdLanding.edges(start: 40, end: 80, words: spoken).start, 39.75, accuracy: 0.001)
    XCTAssertEqual(AdLanding.edges(start: 7, end: 80, words: words(seconds(7, 90))).start, 6.75, accuracy: 0.001)
  }

  func testAnAdWhoseFirstWordIsTheTranscriptsFirstStartsAtZeroWithinTheFirstSixSeconds() {
    XCTAssertEqual(AdLanding.edges(start: 3, end: 50, words: words(seconds(3, 90))).start, 0)
    XCTAssertEqual(AdLanding.edges(start: 6, end: 50, words: words(seconds(6, 90))).start, 0)
    XCTAssertEqual(
      AdLanding.edges(start: 6.5, end: 50, words: words(seconds(0, 6) + seconds(7, 90))).start, 6.75,
      accuracy: 0.001, "a word before it: a quarter second before the first word, not before that word ends")
    XCTAssertEqual(AdLanding.edges(start: 6.5, end: 50, words: words([(6.5, 7.5)] + seconds(8, 90))).start, 6.25)
  }
}
