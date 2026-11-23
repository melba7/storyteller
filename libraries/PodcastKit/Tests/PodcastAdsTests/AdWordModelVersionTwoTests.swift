import XCTest

@testable import PodcastAds

/// Version 2 of the word model file: the word pairs of the neighbouring lines as features, and the
/// decoder that keeps credits apart from ads. The numbers are pinned in `test_teach_features.py`
/// and `test_teach_spans.py` too, so the Mac and the phone agree.
final class AdWordModelVersionTwoTests: XCTestCase {
  private let size = 4_194_304

  private func key(_ feature: String) -> String { String(AdWordModel.bucket(feature, buckets: size)) }

  private func file(version: Int = 2, weights: [String: Any]? = nil, buckets: Int? = nil) -> Data {
    let table: [String: Any] =
      weights ?? [
        key("#bias"): [5.0, 0.0, 0.0, 0.0, 0.0], key("nb:promo code"): [-2.0, 2.0, 0.0, 0.0, 0.0],
        key("pb:promo code"): [-1.0, 0.0, 1.0, 0.0, 0.0], key("u:promo"): [-3.0, 3.0, 0.0, 0.0, 0.0],
        key("nb:brought to"): [-1.0, 1.0, 0.0, 0.0, 0.0],
      ]
    let json: [String: Any] = [
      "version": version, "buckets": buckets ?? size, "classes": AdWordModel.classes, "weights": table,
    ]
    return try! JSONSerialization.data(withJSONObject: json)
  }

  private let lines: [NumberedLine] = [
    (1, 0.0, 5.5, "Welcome to the show, I'm your host."),
    (2, 6.0, 11.5, "This episode is brought to you by Example Mattress."),
    (3, 12.0, 19.5, "Go to example.com/show and use promo code SHOW for 20 percent off."),
    (4, 20.0, 25.5, "That's example.com/show, promo code SHOW."),
    (5, 26.0, 32.5, "And we're back. Today we talk about rivers."),
    (6, 33.0, 36.0, "Rivers are long."),
    (7, 130.0, 136.5, "Come see us live in Chicago, tickets are on sale now."),
    (8, 137.0, 143.5, "Get your tickets at example.org/live."),
    (9, 144.0, 147.0, "Anyway, the river."),
  ].map { NumberedLine(number: $0.0, start: $0.1, end: $0.2, text: $0.3) }

  func testTheBucketsOfPairFeaturesFollowTheReference() {
    let expected: [(String, Int)] = [
      ("#bias", 3_357_031), ("u:promo", 1_170_965), ("nb:promo code", 2_033_433),
      ("pb:promo code", 2_349_595), ("nb:brought to", 3_728_355), ("pb:welcome to", 358_674),
    ]
    for (feature, bucket) in expected {
      XCTAssertEqual(AdWordModel.bucket(feature, buckets: size), bucket, feature)
    }
  }

  func testAVersionTwoFileIsReadAndVersionThreeIsNot() {
    XCTAssertEqual(AdWordModel(data: file())?.version, 2)
    let small = [String(AdWordModel.bucket("#bias", buckets: 262_144)): [5.0, 0.0, 0.0, 0.0, 0.0]]
    XCTAssertEqual(AdWordModel(data: file(version: 1, weights: small, buckets: 262_144))?.version, 1)
    XCTAssertNil(AdWordModel(data: file(version: 3)))
    XCTAssertNil(AdWordModel(data: file(version: 0)))
  }

  func testProbabilitiesFollowTheReference() {
    let rows = AdWordModel(data: file())!.probabilities(lines: lines, duration: 150)
    let expected: [[Double]] = [
      [0.242466, 0.659091, 0.032814, 0.032814, 0.032814],
      [0.659091, 0.242466, 0.032814, 0.032814, 0.032814],
      [0.006561, 0.973756, 0.006561, 0.006561, 0.006561],
      [0.098767, 0.729797, 0.098767, 0.036334, 0.036334],
      [0.905195, 0.016579, 0.045067, 0.016579, 0.016579],
      [0.905195, 0.016579, 0.045067, 0.016579, 0.016579],
      [0.973756, 0.006561, 0.006561, 0.006561, 0.006561],
      [0.973756, 0.006561, 0.006561, 0.006561, 0.006561],
      [0.973756, 0.006561, 0.006561, 0.006561, 0.006561],
    ]
    XCTAssertEqual(rows.count, expected.count)
    for (row, want) in zip(rows, expected) {
      for (got, value) in zip(row, want) { XCTAssertEqual(got, value, accuracy: 1e-5) }
    }
  }

  func testAVersionOneModelIgnoresThePairsOfItsNeighbours() {
    let same: [String: Any] = [
      String(AdWordModel.bucket("#bias", buckets: 262_144)): [5.0, 0.0, 0.0, 0.0, 0.0],
      String(AdWordModel.bucket("nb:promo code", buckets: 262_144)): [-2.0, 2.0, 0.0, 0.0, 0.0],
    ]
    let old = AdWordModel(data: file(version: 1, weights: same, buckets: 262_144))!
    for row in old.probabilities(lines: lines, duration: 150) {
      XCTAssertEqual(row[0], 5.0.expNormalised, accuracy: 1e-9)
    }
  }

  // MARK: The decoder

  private func row(_ s: Double = 0, _ n: Double = 0, _ h: Double = 0, c: Double = 0) -> [Double] {
    [((1 - s - n - h - c) * 10000).rounded() / 10000, s, n, h, c]
  }

  private var rows: [[Double]] {
    [
      row(c: 0.9), row(c: 0.9), row(), row(0.45), row(0.95), row(0.95), row(0.95), row(0, 0, 0.95),
      row(0, 0, 0.95), row(), row(c: 0.9), row(c: 0.9), row(0.5, c: 0.45), row(0.95), row(0.95),
      row(0.95), row(), row(), row(0.95), row(),
    ]
  }

  private func numbered(_ count: Int) -> [NumberedLine] {
    (0..<count).map {
      NumberedLine(number: $0 + 1, start: Double($0) * 6, end: Double($0) * 6 + 5, text: "")
    }
  }

  func testTheDecoderFollowsTheReference() {
    let found = AdWordModel.decodeTwo(rows: rows, lines: numbered(20), thresholds: .init())
    XCTAssertEqual(
      found.map { [$0.firstLine, $0.lastLine] }, [[1, 2], [4, 7], [8, 9], [11, 12], [13, 16]])
    XCTAssertEqual(
      found.map(\.sort), ["intro_credits", "sponsor", "host_ask", "intro_credits", "sponsor"])
    for (span, want) in zip(found, [0.7875, 0.796875, 0.83125, 0.73125, 0.746875]) {
      XCTAssertEqual(span.score, want, accuracy: 1e-9)
    }
    XCTAssertEqual(found.map(\.sure), [false, false, false, false, false])
  }

  func testTheVersionOneDecoderStillCountsCreditsAsAnAd() {
    let old = AdWordModel.decode(rows: rows, lines: numbered(20), thresholds: .init())
    XCTAssertNotEqual(old.map { [$0.firstLine, $0.lastLine] }, [[1, 2], [4, 7], [8, 9], [11, 12], [13, 16]])
  }

  func testCreditsAloneAreNotAnAd() {
    let found = AdWordModel.decodeTwo(rows: Array(repeating: row(c: 0.95), count: 6), lines: numbered(6), thresholds: .init())
    XCTAssertEqual(found.map(\.sort), ["intro_credits"])
  }

  func testAShortPartOfACutCreditsSpanIsDropped() {
    let found = AdWordModel.decodeTwo(
      rows: [row(c: 0.9), row(0.95), row(0.95), row(0.95)], lines: numbered(4), thresholds: .init())
    XCTAssertEqual(found.map(\.sort), ["sponsor"])
  }

  func testWideningStopsAtThePreviousSpan() {
    let input = Array(repeating: row(0.95), count: 3) + Array(repeating: row(), count: 2) + [row(0.45)]
      + Array(repeating: row(0.95), count: 3)
    let found = AdWordModel.decodeTwo(rows: input, lines: numbered(9), thresholds: .init())
    XCTAssertEqual(found.map { [$0.firstLine, $0.lastLine] }, [[1, 3], [6, 9]])
  }

  func testBadRowsGiveNoSpans() {
    XCTAssertEqual(AdWordModel.decodeTwo(rows: [[1, 0]], lines: numbered(1), thresholds: .init()), [])
    XCTAssertEqual(AdWordModel.decodeTwo(rows: rows, lines: numbered(3), thresholds: .init()), [])
  }

  // MARK: Questions

  func testQuestionsOfAVersionTwoModelDoNotAskAboutCredits() {
    func word(_ feature: String, _ row: [Double]) -> (String, Any) { (key(feature), row) }
    let table = Dictionary(
      uniqueKeysWithValues: [
        word("#bias", [5, 0, 0, 0, 0]), word("u:roll", [-2.5, 0, 0, 0, 2.5]),
        word("u:mid", [-2.5, 2.5, 0, 0, 0]),
      ])
    let model = AdWordModel(data: file(weights: table))!
    let words = ["plain", "plain", "roll", "roll", "roll", "roll", "plain", "plain", "plain", "mid", "mid", "mid", "mid", "plain"]
    let all = words.enumerated().map {
      NumberedLine(number: $0.offset + 1, start: Double($0.offset) * 6, end: Double($0.offset) * 6 + 5, text: $0.element)
    }
    let asked = AdAsks.questions(model: model, lines: all, duration: 100, outside: [], source: "word-model")
    XCTAssertEqual(asked.count, 1)
    XCTAssertEqual(asked.first?.start, 54)
  }
}

private extension Double {
  /// The probability of "none" for the scores [self, 0, 0, 0, 0].
  var expNormalised: Double { exp(self) / (exp(self) + 4) }
}
