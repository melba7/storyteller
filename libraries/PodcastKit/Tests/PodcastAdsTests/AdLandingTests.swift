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

  // MARK: The end keeps off a word that starts just before it

  func testAWordThatStartsJustBeforeTheAdsEndIsTheShowsAndIsNotClipped() {
    // The ad's last word runs 58.0 to 59.0, and the show's first word starts at 58.95: Apple's
    // word ends run on into the next word. The end lands a quarter second before that word.
    let spoken = words(seconds(0, 58) + [(58.0, 59.0), (58.95, 59.4), (59.4, 60.0)] + seconds(60, 80))
    XCTAssertEqual(AdLanding.edges(start: 20, end: 59, words: spoken).end, 58.7, accuracy: 0.001)
    // Within the tolerance a start counts as at the end, as it does for a start (0.01 s).
    let at = words(seconds(0, 58) + [(58.0, 59.0), (58.995, 59.4), (59.4, 60.0)] + seconds(60, 80))
    XCTAssertEqual(AdLanding.edges(start: 20, end: 59, words: at).end, 58.745, accuracy: 0.001)
  }

  func testAWordThatStartsWellBeforeTheAdsEndIsTheAds() {
    // The word 58.8 to 59.4 is the ad's last word: the end lands before the one after it.
    let spoken = words(seconds(0, 58) + [(58.0, 58.8), (58.8, 59.4), (59.4, 60.0)] + seconds(60, 80))
    XCTAssertEqual(AdLanding.edges(start: 20, end: 59, words: spoken).end, 59.15, accuracy: 0.001)
  }
}
