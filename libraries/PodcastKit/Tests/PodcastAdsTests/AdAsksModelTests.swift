import XCTest

@testable import PodcastAds

/// `AdAsks` on the word model's own rows, and `pick` on candidates that a finder without a model
/// (the repeats) made itself.
final class AdAsksModelTests: XCTestCase {
  private func found(_ start: Double, _ end: Double, _ confidence: AdConfidence = .sure) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "Acme", confidence: confidence, firstWords: "")
  }

  // MARK: The word model's own rows

  /// A word model where "hi" lines are surely an ad, "mid" lines have a chance of about 0.55
  /// and any other line about 0.03 (the same weights as the word model's own tests).
  private var model: AdWordModel {
    func key(_ feature: String) -> String { String(AdWordModel.bucket(feature, buckets: 262144)) }
    let weights: [String: Any] = [
      key("#bias"): [5.0, 0.0, 0.0, 0.0, 0.0],
      key("u:hi"): [-7.0, 7.0, 0.0, 0.0, 0.0],
      key("u:mid"): [-2.5, 2.5, 0.0, 0.0, 0.0],
    ]
    let json: [String: Any] = [
      "version": 1, "buckets": 262144, "classes": AdWordModel.classes, "weights": weights,
    ]
    return AdWordModel(data: try! JSONSerialization.data(withJSONObject: json))!
  }

  private func modelLines(_ words: [String]) -> [NumberedLine] {
    words.enumerated().map {
      NumberedLine(number: $0.offset + 1, start: Double($0.offset) * 6, end: Double($0.offset) * 6 + 5, text: $0.element)
    }
  }

  func testTheWordModelsRowsGiveTheSameQuestionsAsTheirNumbers() {
    let words = ["plain", "plain", "mid", "mid", "mid", "mid", "plain", "hi", "hi", "hi", "hi", "plain"]
    let lines = modelLines(words)
    let asked = AdAsks.questions(
      model: model, lines: lines, duration: 100, outside: [], source: "word-model")
    XCTAssertEqual(asked.count, 1, "the mid run is asked; the hi run is an ad; plain is neither")
    XCTAssertEqual(asked.first?.start, 12)
    XCTAssertEqual(asked.first?.end, 35)
    XCTAssertEqual(asked.first?.source, "word-model")
    // The rows are the model's, and the ceiling is the model's own start threshold.
    XCTAssertEqual(
      asked,
      AdAsks.questions(
        lines: lines, rows: model.probabilities(lines: lines, duration: 100),
        below: model.thresholds.start, outside: [], source: "word-model"))
  }

  func testAHigherAskThresholdLeavesTheMidRunUnasked() {
    let lines = modelLines(["mid", "mid", "mid", "mid"])
    XCTAssertEqual(
      AdAsks.questions(model: model, lines: lines, duration: nil, from: 0.6, outside: [], source: "x"), [])
  }

  func testNoLinesAskNothing() {
    XCTAssertEqual(
      AdAsks.questions(model: model, lines: [], duration: nil, outside: [], source: "x"), [])
  }

  // MARK: Ready candidates

  private func candidate(_ start: Double, _ end: Double, _ chance: Double) -> AdAsks.Candidate {
    AdAsks.Candidate(
      ad: FoundAd(
        start: start, end: end, kind: .promo, advertiser: "", confidence: .unsure,
        firstWords: "standing plug", source: "repeat-words"),
      chance: chance)
  }

  func testPickTakesReadyCandidatesAndKeepsTheirNames() {
    let picked = AdAsks.pick(
      [candidate(100, 130, 0.5), candidate(0, 20, 0.9)], outside: [])
    XCTAssertEqual(picked.map(\.start), [0, 100], "the most likely first")
    XCTAssertEqual(picked.map(\.confidence), [.guess, .guess], "every question is a guess")
    XCTAssertEqual(picked.map(\.source), ["repeat-words", "repeat-words"])
    XCTAssertEqual(picked.map(\.kind), [.promo, .promo])
    XCTAssertEqual(picked.first?.firstWords, "standing plug")
  }

  func testPickKeepsAtMostThree() {
    let many = (0..<6).map { candidate(Double($0) * 100, Double($0) * 100 + 30, 0.4 + Double($0) / 100) }
    XCTAssertEqual(AdAsks.pick(many, outside: []).map(\.start), [500, 400, 300])
  }

  func testPickDropsWhatOverlapsAFoundAdOrAMoreLikelyCandidate() {
    let picked = AdAsks.pick(
      [
        candidate(0, 30, 0.8),  // over a found ad
        candidate(100, 130, 0.5),
        candidate(120, 150, 0.7),  // over the one above and more likely: it wins
        candidate(200, 230, 0.3),
      ], outside: [found(20, 40)])
    XCTAssertEqual(picked.map(\.start), [120, 200])
  }

  func testPickDropsWhatIsTooShortTooLongOrNotANumber() {
    let picked = AdAsks.pick(
      [
        candidate(0, 9, 0.9),  // under ten seconds
        candidate(100, 500, 0.9),  // over the longest ad
        candidate(600, 630, .nan),
        candidate(700, 730, .infinity),
        candidate(.nan, 830, 0.9),
        candidate(900, 800, 0.9),  // ends before it starts
        candidate(1000, 1030, 0.4),
      ], outside: [])
    XCTAssertEqual(picked.map(\.start), [1000])
    XCTAssertEqual(AdAsks.pick([], outside: []), [])
  }
}
