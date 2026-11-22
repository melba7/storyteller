import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// The local finders on a transcript that is still being made.
final class LocalAdsPartialTests: XCTestCase {
  private let sponsor =
    "This show is sponsored by Casper. Use code NAP for percent off at casper.com."

  /// The words of `text`, a third of a second each, from `start`.
  private func words(_ text: String, from start: Double) -> [TranscriptWord] {
    text.split(separator: " ").enumerated().map {
      TranscriptWord(
        text: String($0.element), start: start + Double($0.offset) * 0.3,
        end: start + Double($0.offset) * 0.3 + 0.25)
    }
  }

  private func partial(_ words: [TranscriptWord], reached: Double) -> PartialTranscript {
    PartialTranscript(
      identity: TranscriptIdentity(
        locale: "en-US", recogniser: "Fake", recogniserVersion: "1", osVersion: "26.0", sha256: "aa"),
      duration: 3600, reached: reached, words: words)
  }

  private var talk: [TranscriptWord] {
    words("Welcome back to the show everybody. Today we talk about gardens.", from: 0)
  }

  func testAnAdInTheWordsSoFarIsFound() {
    let all = talk + words(sponsor, from: 20) + words("And now back to gardens.", from: 40)
    let found = LocalAds(model: nil).ads(partial: partial(all, reached: 50))
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found.first?.kind, .ad)
    XCTAssertEqual(found.first?.advertiser, "Casper")
    XCTAssertEqual(found.first?.start ?? 0, 20, accuracy: 0.5)
  }

  func testOnlyTheFirstSecondsAreLookedAtWithALimit() {
    let all = talk + words(sponsor, from: 200) + words("And now back to gardens.", from: 220)
    let found = LocalAds(model: nil).ads(partial: partial(all, reached: 230), limit: 180)
    XCTAssertEqual(found, [])
    XCTAssertEqual(LocalAds(model: nil).ads(partial: partial(all, reached: 230)).count, 1)
  }

  func testAnAdThatBeginsBeforeTheLimitAndGoesOnIsCutAtTheLimit() {
    let all = talk + words(sponsor, from: 175)
    let found = LocalAds(model: nil).ads(partial: partial(all, reached: 230), limit: 180)
    for ad in found { XCTAssertLessThanOrEqual(ad.end, 180.01) }
  }

  func testNoWordsNoAds() {
    XCTAssertEqual(LocalAds().ads(partial: partial([], reached: 0)), [])
  }
}
