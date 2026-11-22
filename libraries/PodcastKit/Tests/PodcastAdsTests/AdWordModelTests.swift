import XCTest

@testable import PodcastAds

final class AdWordModelTests: XCTestCase {
  // MARK: Helpers

  private let five = ["none", "sponsor", "network_promo", "host_ask", "intro_credits"]

  /// A model file as JSON data. `extra` adds or replaces top-level keys.
  private func file(
    weights: [String: Any], buckets: Int = 262144, extra: [String: Any] = [:]
  ) -> Data {
    var json: [String: Any] = [
      "version": 1, "buckets": buckets, "classes": five, "weights": weights,
    ]
    for (key, value) in extra { json[key] = value }
    return try! JSONSerialization.data(withJSONObject: json)
  }

  private func model(weights: [String: Any], extra: [String: Any] = [:]) -> AdWordModel {
    AdWordModel(data: file(weights: weights, extra: extra))!
  }

  /// The weights of the reference example, keyed by bucket number.
  private let referenceWeights: [String: Any] = [
    "3916": [-1.0, 0.0, 1.0, 0.0, 0.0], "14330": [-0.5, 0.5, 0.0, 0.0, 0.0],
    "44798": [-0.5, 0.0, 0.5, 0.0, 0.0], "49919": [-2.0, 2.0, 0.0, 0.0, 0.0],
    "122389": [-3.0, 3.0, 0.0, 0.0, 0.0], "153606": [0.2, 0.3, 0.0, 0.0, 0.0],
    "161629": [-1.0, 2.0, 0.0, 0.0, 0.0], "161948": [-1.0, 1.0, 0.0, 0.0, 0.0],
    "168660": [-0.5, 0.0, 0.5, 0.0, 0.0], "211303": [5.0, 0.0, 0.0, 0.0, 0.0],
    "242859": [-4.0, 0.0, 3.0, 0.0, 0.0],
  ]

  private let referenceLines: [NumberedLine] = [
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

  /// A model where "hi" lines are surely an ad (p about 1), "mid" lines are about 0.55 and
  /// any other line is about 0.03.
  private var levels: AdWordModel {
    func key(_ feature: String) -> String { String(AdWordModel.bucket(feature, buckets: 262144)) }
    return model(weights: [
      key("#bias"): [5.0, 0.0, 0.0, 0.0, 0.0],
      key("u:hi"): [-7.0, 7.0, 0.0, 0.0, 0.0],
      key("u:mid"): [-2.5, 2.5, 0.0, 0.0, 0.0],
    ])
  }

  /// One line per word, numbered from `first`, `step` seconds apart and `length` long.
  private func lines(
    _ words: [String], first: Int = 1, step: Double = 6, length: Double = 5
  ) -> [NumberedLine] {
    words.enumerated().map {
      NumberedLine(
        number: first + $0.offset, start: Double($0.offset) * step,
        end: Double($0.offset) * step + length, text: $0.element)
    }
  }

  private func spans(_ model: AdWordModel, _ words: [String], first: Int = 1, step: Double = 6, length: Double = 5)
    -> [AdWordModel.Span]
  {
    model.spans(lines: lines(words, first: first, step: step, length: length), duration: nil)
  }

  // MARK: Tokens, buckets

  func testTokensFollowTheReference() {
    XCTAssertEqual(
      AdWordModel.tokens("Use promo code SLEEPY20 at example.com/show!"),
      ["use", "promo", "code", "sleepy20", "at", "example", "com", "show"])
    XCTAssertEqual(
      AdWordModel.tokens("Don\u{2019}t miss it \u{2014} 'quoted' O'Brien's 2026 tour"),
      ["don't", "miss", "it", "quoted", "o'brien's", "0", "tour"])
    XCTAssertEqual(AdWordModel.tokens("  ...  "), [])
    XCTAssertEqual(AdWordModel.tokens("Caf\u{e9} 100% OFF"), ["caf", "0", "off"])
  }

  func testBucketsFollowTheReference() {
    let expected: [(String, Int)] = [
      ("#bias", 211303), ("u:promo", 122389), ("b:promo code", 161629), ("p:sponsor", 116655),
      ("n:back", 89566), ("#t0", 153606), ("#t1", 154009), ("#end", 119647), ("u:0", 51818),
    ]
    for (feature, bucket) in expected {
      XCTAssertEqual(AdWordModel.bucket(feature, buckets: 262144), bucket, feature)
    }
  }

  // MARK: Probabilities and spans

  func testProbabilitiesFollowTheReference() {
    let rows = model(weights: referenceWeights).probabilities(lines: referenceLines, duration: 150)
    let expected: [[Double]] = [
      [0.909083, 0.050021, 0.013632, 0.013632, 0.013632],
      [0.230597, 0.692751, 0.025551, 0.025551, 0.025551],
      [0.002226, 0.992308, 0.001822, 0.001822, 0.001822],
      [0.006006, 0.985048, 0.002982, 0.002982, 0.002982],
      [0.919043, 0.030671, 0.022722, 0.013782, 0.013782],
      [0.919043, 0.030671, 0.022722, 0.013782, 0.013782],
      [0.006478, 0.010681, 0.961478, 0.010681, 0.010681],
      [0.006478, 0.010681, 0.961478, 0.010681, 0.010681],
      [0.950893, 0.010563, 0.017416, 0.010563, 0.010563],
    ]
    XCTAssertEqual(rows.count, expected.count)
    for (row, want) in zip(rows, expected) {
      XCTAssertEqual(row.count, 5)
      for (got, value) in zip(row, want) { XCTAssertEqual(got, value, accuracy: 1e-5) }
    }
  }

  func testSpansFollowTheReference() {
    let found = model(weights: referenceWeights).spans(lines: referenceLines, duration: 150)
    XCTAssertEqual(found.count, 2)
    XCTAssertEqual([found[0].firstLine, found[0].lastLine], [2, 4])
    XCTAssertEqual(found[0].sort, "sponsor")
    XCTAssertEqual(found[0].score, 0.787764, accuracy: 1e-5)
    XCTAssertFalse(found[0].sure)
    XCTAssertEqual([found[1].firstLine, found[1].lastLine], [7, 8])
    XCTAssertEqual(found[1].sort, "network_promo")
    XCTAssertEqual(found[1].score, 0.761399, accuracy: 1e-5)
    XCTAssertFalse(found[1].sure)
  }

  func testSpansCarryTheLinesOwnNumbers() {
    let found = spans(levels, ["lo", "hi", "hi", "hi", "hi", "hi", "lo"], first: 40)
    XCTAssertEqual(found.map { [$0.firstLine, $0.lastLine] }, [[41, 45]])
  }

  func testASpanBridgesOneWeakLineButNotTwo() {
    let one = spans(levels, ["lo", "hi", "mid", "lo", "mid", "hi", "lo"])
    XCTAssertEqual(one.map { [$0.firstLine, $0.lastLine] }, [[2, 6]])
    let two = spans(levels, ["lo", "hi", "mid", "lo", "lo", "mid", "hi", "lo"])
    XCTAssertEqual(two.map { [$0.firstLine, $0.lastLine] }, [[2, 3]])
  }

  func testAShortSpanIsDroppedUnlessItsScoreIsAtLeastPointNine() {
    let weak = spans(levels, ["lo", "hi", "hi", "lo"], step: 3, length: 2)
    XCTAssertEqual(weak, [])
    let strong = spans(levels, ["lo", "hi", "hi", "hi", "hi", "hi", "lo"], step: 1, length: 1)
    XCTAssertEqual(strong.count, 1)
    XCTAssertEqual(strong[0].score, 0.902514, accuracy: 1e-5)
    XCTAssertFalse(strong[0].sure)
  }

  func testASpanIsSureOnlyWhenScoreAndLengthBothReachTheBar() {
    let words = ["lo", "hi", "hi", "hi", "hi", "hi", "lo"]
    XCTAssertTrue(spans(levels, words)[0].sure)
    // Ten seconds long: kept (at least 8) but too short to be sure.
    let short = spans(levels, words, step: 2, length: 2)
    XCTAssertEqual(short.count, 1)
    XCTAssertFalse(short[0].sure)
    // Long enough but the score (0.7578) is under 0.85.
    let weak = spans(levels, ["lo", "hi", "hi", "lo"])
    XCTAssertEqual(weak.count, 1)
    XCTAssertFalse(weak[0].sure)
  }

  func testThresholdsAreReadFromTheFile() {
    let words = ["lo", "hi", "hi", "lo"]
    let base = levels
    XCTAssertEqual(spans(base, words).count, 1)
    let strict = AdWordModel(
      data: file(
        weights: referenceWeights, extra: ["thresholds": ["start": 0.99, "stay": 0.5, "sure": 0.5]]))!
    XCTAssertEqual(strict.spans(lines: lines(words), duration: nil), [])
    // A model with sure at 0.7 calls the 0.7578 span sure.
    let key = { String(AdWordModel.bucket($0, buckets: 262144)) }
    let sure = model(
      weights: [
        key("#bias"): [5.0, 0.0, 0.0, 0.0, 0.0], key("u:hi"): [-7.0, 7.0, 0.0, 0.0, 0.0],
      ], extra: ["thresholds": ["sure": 0.7]])
    XCTAssertTrue(sure.spans(lines: lines(words, step: 12), duration: nil)[0].sure)
  }

  func testEmptyAndUntrainedInputs() {
    let m = model(weights: referenceWeights)
    XCTAssertEqual(m.probabilities(lines: [], duration: nil), [])
    XCTAssertEqual(m.spans(lines: [], duration: nil), [])
    // One weight bucket that none of the lines touch counts as an untrained model.
    let untouched = String(AdWordModel.bucket("u:zzzzqqq", buckets: 262144))
    let blank = model(weights: [untouched: [0.0, 0.0, 0.0, 0.0, 0.0]])
    let rows = blank.probabilities(lines: referenceLines, duration: 150)
    XCTAssertEqual(rows.count, 9)
    for row in rows { for value in row { XCTAssertEqual(value, 0.2, accuracy: 1e-12) } }
    // Equal probabilities mean an ad probability of 0.8 everywhere, so by the contract the whole
    // transcript is one span, and the earliest class wins the tie.
    let all = blank.spans(lines: referenceLines, duration: 150)
    XCTAssertEqual(all.count, 1)
    XCTAssertEqual([all[0].firstLine, all[0].lastLine], [1, 9])
    XCTAssertEqual(all[0].sort, "sponsor")
    XCTAssertEqual(all[0].score, 0.8, accuracy: 1e-12)
  }

  func testTheEndOfTheEpisodeIsAFeature() {
    let key = String(AdWordModel.bucket("#end", buckets: 262144))
    let m = model(weights: [key: [0.0, 4.0, 0.0, 0.0, 0.0]])
    let line = [NumberedLine(number: 1, start: 100, end: 105, text: "hello")]
    XCTAssertEqual(m.probabilities(lines: line, duration: 150)[0][1], exp(4) / (exp(4) + 4), accuracy: 1e-9)
    XCTAssertEqual(m.probabilities(lines: line, duration: nil)[0][1], 0.2, accuracy: 1e-12)
    XCTAssertEqual(m.probabilities(lines: line, duration: 300)[0][1], 0.2, accuracy: 1e-12)
  }

  // MARK: Loading

  func testALoadedFileIsAcceptedWithOptionalParts() {
    let data = file(
      weights: ["3916": [-1.0, 0.0, 1.0, 0.0, 0.0]],
      extra: ["trained": ["writtenAt": 1_795_000_000_000, "episodes": 180, "x": [1, 2]]])
    XCTAssertNotNil(AdWordModel(data: data))
    XCTAssertEqual(AdWordModel(data: data), AdWordModel(data: data))
    XCTAssertEqual(AdWordModel.fileName, "ad-model.json")
    XCTAssertEqual(AdWordModel.classes, five)
  }

  func testLoadFromAFile() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ad-model-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    XCTAssertNil(AdWordModel.load(from: url))
    try file(weights: referenceWeights).write(to: url)
    XCTAssertNotNil(AdWordModel.load(from: url))
  }

  func testTheLoaderRejectsWhatItCannotTrust() {
    let ok: [String: Any] = ["3916": [-1.0, 0.0, 1.0, 0.0, 0.0]]
    func bad(_ data: Data, _ why: String) { XCTAssertNil(AdWordModel(data: data), why) }
    bad(Data("not json".utf8), "not JSON")
    bad(Data("[1,2]".utf8), "not an object")
    bad(file(weights: ok, extra: ["version": 2]), "version 2")
    bad(file(weights: ok, extra: ["version": "1"]), "version as text")
    bad(file(weights: ok, extra: ["buckets": 1023]), "too few buckets")
    bad(file(weights: ok, extra: ["buckets": 4_194_305]), "too many buckets")
    bad(file(weights: ok, extra: ["buckets": 2048.5]), "buckets not whole")
    bad(file(weights: ok, extra: ["classes": Array(five.reversed())]), "classes in another order")
    bad(file(weights: ok, extra: ["classes": Array(five.dropLast())]), "four classes")
    bad(file(weights: [:]), "no weights would call every line an ad")
    bad(file(weights: ["x": [0, 0, 0, 0, 0]]), "key not a number")
    bad(file(weights: ["1.5": [0, 0, 0, 0, 0]]), "key not whole")
    bad(file(weights: ["-1": [0, 0, 0, 0, 0]]), "key negative")
    bad(file(weights: ["2048": [0, 0, 0, 0, 0]], buckets: 2048), "key outside buckets")
    bad(file(weights: ["5": [0, 0, 0, 0]]), "four numbers")
    bad(file(weights: ["5": [0, 0, 0, 0, 0, 0]]), "six numbers")
    bad(file(weights: ["5": [0, 0, 0, 0, "a"]]), "a word as weight")
    bad(file(weights: ["5": "text"]), "value not a list")
    bad(Data(#"{"version":1,"buckets":2048,"classes":["none","sponsor","network_promo","host_ask","intro_credits"],"weights":{"5":[0,0,0,0,1e999]}}"#.utf8), "infinite weight")
    bad(file(weights: ok, extra: ["thresholds": ["start": 1.5]]), "threshold above 1")
    bad(file(weights: ok, extra: ["thresholds": ["stay": -0.1]]), "threshold below 0")
    bad(file(weights: ok, extra: ["thresholds": ["sure": "high"]]), "threshold a word")
    bad(file(weights: ok, extra: ["thresholds": ["start": 0.5, "stay": 0.6]]), "stay above start")
    bad(file(weights: ok, extra: ["thresholds": 5]), "thresholds not an object")
    bad(file(weights: ok, extra: ["weights": 5]), "weights not an object")
  }

  func testTheDefaultThresholdsApplyWhenMissing() {
    let one: [String: Any] = ["7": [0.0, 0.0, 0.0, 0.0, 0.0]]
    // With the default stay of 0.4 a start of 0.5 is fine, and 0.3 is not allowed for stay > start.
    XCTAssertNotNil(AdWordModel(data: file(weights: one, extra: ["thresholds": ["start": 0.5]])))
    XCTAssertNil(AdWordModel(data: file(weights: one, extra: ["thresholds": ["start": 0.3]])))
  }
}
