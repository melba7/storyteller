import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// A model span that changes its top class is split, and LocalAds keeps each piece's own kind.
final class AdModelSplitTests: XCTestCase {
  /// "theme" lines are intro or credits, "acme" lines a sponsor, "plug" lines a host ask; any
  /// other line is plain talk.
  private func model() -> AdWordModel {
    func key(_ feature: String) -> String { String(AdWordModel.bucket(feature, buckets: 262144)) }
    let json: [String: Any] = [
      "version": 1, "buckets": 262144, "classes": AdWordModel.classes,
      "weights": [
        key("#bias"): [4.0, 0, 0, 0, 0],
        key("u:theme"): [-4.0, 0, 0, 0, 6.0],
        key("u:acme"): [-4.0, 6.0, 0, 0, 0],
        key("u:plug"): [-4.0, 0, 0, 6.0, 0],
      ],
    ]
    return AdWordModel(data: try! JSONSerialization.data(withJSONObject: json))!
  }

  private func lines(_ words: [String]) -> [NumberedLine] {
    words.enumerated().map {
      NumberedLine(
        number: $0.offset + 1, start: Double($0.offset) * 10, end: Double($0.offset) * 10 + 9,
        text: $0.element)
    }
  }

  private let themeThenSponsor =
    ["plain", "plain"] + Array(repeating: "theme", count: 3) + Array(repeating: "acme", count: 4)
    + ["plain", "plain"]

  func testASpanIsSplitWhereTheTopClassChanges() {
    let found = model().spans(lines: lines(themeThenSponsor), duration: nil)
    XCTAssertEqual(found.map(\.sort), ["intro_credits", "sponsor"])
    XCTAssertEqual(found.map(\.firstLine), [3, 6])
    XCTAssertEqual(found.map(\.lastLine), [5, 9])
  }

  func testAWeakLineBridgedInsideASpanJoinsTheClassBeforeIt() {
    // "plain" in the middle is bridged (its smoothed score stays above the stay threshold).
    let words = Array(repeating: "acme", count: 3) + ["plain"] + Array(repeating: "acme", count: 3)
    let found = model().spans(lines: lines(["plain"] + words + ["plain"]), duration: nil)
    XCTAssertEqual(found.map(\.sort), ["sponsor"])
    XCTAssertEqual(found.map { [$0.firstLine, $0.lastLine] }, [[2, 8]])
  }

  func testCreditsThenASponsorAreTwoKindsNotOneSkippedAd() {
    let transcript = makeTranscript(themeThenSponsor)
    let ranges = LocalAds(model: model()).ranges(lines: AdChunker.number(transcript.lines))
    XCTAssertEqual(ranges.map(\.kind), [.credits, .ad])
    XCTAssertEqual(ranges.map(\.startLine), [3, 6])
    XCTAssertEqual(ranges.map(\.endLine), [5, 9])
  }

  func testWithCreditsOffTheIntroLinesAreNotSkipped() {
    let transcript = makeTranscript(themeThenSponsor)
    let ads = LocalAds(model: model()).ads(transcript: transcript)
    let file = AdsFile(
      sha256: "aa", detector: "local", detectorVersion: "", osVersion: "", duration: 200, ads: ads)
    let skipper = AdSkipper(file: file, settings: AdSkipSettings(skipCredits: false))
    XCTAssertTrue(skipper.ads.allSatisfy { $0.start >= 49 }, "\(skipper.ads)")
  }

  func testCreditsBeforeASponsorRuleLineStayCredits() {
    let sponsor = "This episode is brought to you by Acme, go to acme.com for twenty percent off."
    let texts =
      ["plain", "plain"] + Array(repeating: "theme", count: 3) + [sponsor, "plain", "plain", "plain"]
    let ranges = LocalAds(model: model()).ranges(lines: lines(texts))
    XCTAssertEqual(ranges.first { $0.kind == .credits }.map { [$0.startLine, $0.endLine] }, [3, 5])
    XCTAssertTrue(
      ranges.filter { $0.kind == .ad }.allSatisfy { $0.startLine >= 6 },
      "no ad may start inside the credits: \(ranges)")
  }

  func testAModelLineKeepsItsOwnKindNextToARuleLineOfAnotherKind() {
    let sponsor = "This episode is brought to you by Acme, go to acme.com for twenty percent off."
    let texts = ["plain", "plain"] + ["plug", "plug", "plug", sponsor] + ["plain", "plain", "plain"]
    let ranges = LocalAds(model: model()).ranges(lines: lines(texts))
    XCTAssertEqual(ranges.first { $0.kind == .ownPlug }.map { [$0.startLine, $0.endLine] }, [3, 5])
  }
}
