import XCTest

@testable import PodcastAds

final class AdMeaningModelTests: XCTestCase {
  private func model(_ data: Data = Made.file()) -> AdMeaningModel { AdMeaningModel(data: data)! }

  // MARK: The file

  func testAFileRoundTrips() throws {
    let first = model()
    XCTAssertEqual(first.dimension, 4)
    XCTAssertEqual(first.revision, 7)
    XCTAssertEqual(first.language, "en")
    XCTAssertEqual(first.probes.count, 2)
    let again = try XCTUnwrap(AdMeaningModel(data: first.fileData(trained: ["episodes": 3])))
    XCTAssertEqual(again, first)
    // Writing the same model twice gives the same bytes (sorted keys), so a rerun is no change.
    XCTAssertEqual(first.fileData(trained: [:]), again.fileData(trained: [:]))
  }

  func testLoadReadsAFileAndRefusesAMissingOne() throws {
    let folder = try temporaryFolder()
    let url = folder.appendingPathComponent(AdMeaningModel.fileName)
    XCTAssertNil(AdMeaningModel.load(from: url))
    try Made.file().write(to: url)
    XCTAssertNotNil(AdMeaningModel.load(from: url))
  }

  func testDamagedFilesAreRefused() {
    XCTAssertNil(AdMeaningModel(data: Data()))
    XCTAssertNil(AdMeaningModel(data: Data("not json".utf8)))
    XCTAssertNil(AdMeaningModel(data: Made.file().prefix(100)))
    XCTAssertNil(AdMeaningModel(data: Made.file { $0["version"] = 2 }))
    XCTAssertNil(AdMeaningModel(data: Made.file { $0["language"] = "fr" }))
    XCTAssertNil(AdMeaningModel(data: Made.file { $0["classes"] = ["none", "sponsor"] }))
    XCTAssertNil(AdMeaningModel(data: Made.file { $0["dimension"] = 0 }))
    XCTAssertNil(AdMeaningModel(data: Made.file { $0["dimension"] = 100_000_000 }))
    XCTAssertNil(AdMeaningModel(data: Made.file { $0["dimension"] = 3 }))  // weights are for 4
    XCTAssertNil(AdMeaningModel(data: Made.file { $0["weights"] = "not base64 !!" }))
    XCTAssertNil(AdMeaningModel(data: Made.file { $0["weights"] = Data(count: 79).base64EncodedString() }))
    XCTAssertNil(AdMeaningModel(data: Made.file { $0["weights"] = Data(count: 81).base64EncodedString() }))
    XCTAssertNil(AdMeaningModel(data: Made.file { $0["biases"] = [0.0, 0.0] }))
    XCTAssertNil(AdMeaningModel(data: Made.file { $0["thresholds"] = ["start": 0.3] }))
    XCTAssertNil(AdMeaningModel(data: Made.file { $0["thresholds"] = ["start": 0.6, "stay": 0.7] }))
    XCTAssertNil(AdMeaningModel(data: Made.file { $0.removeValue(forKey: "probes") }))
    XCTAssertNil(AdMeaningModel(data: Made.file(probes: [(Made.probeOne, [0.5, 0.5, 0.5, 0.5])])))
    XCTAssertNil(AdMeaningModel(data: Made.file(probes: [(Made.probeOne, [1, 0, 0]), (Made.probeTwo, [0, 1, 0, 0])])))
    XCTAssertNil(AdMeaningModel(data: Made.file(probes: [(Made.probeOne, [0, 0, 0, 0]), (Made.probeTwo, [0, 1, 0, 0])])))
  }

  func testAFileOverFiveMegabytesIsRefused() {
    var padded = Made.file()
    XCTAssertNotNil(AdMeaningModel(data: padded))
    padded.append(Data(repeating: 0x20, count: AdMeaningModel.maxBytes))
    XCTAssertGreaterThan(padded.count, 5_000_000)
    XCTAssertNil(AdMeaningModel(data: padded))
  }

  func testWeightsThatAreNotNumbersAreRefused() {
    func file(_ values: [Float]) -> Data { Made.file(weights: values) }
    var rows = [Float](repeating: 0.5, count: 20)
    XCTAssertNotNil(AdMeaningModel(data: file(rows)))
    rows[7] = .nan
    XCTAssertNil(AdMeaningModel(data: file(rows)))
    rows[7] = .infinity
    XCTAssertNil(AdMeaningModel(data: file(rows)))
    rows[7] = -.infinity
    XCTAssertNil(AdMeaningModel(data: file(rows)))
    rows[7] = 2_000_000  // finite but absurd
    XCTAssertNil(AdMeaningModel(data: file(rows)))
    // A bias or a probe number that is too big for a number is not a number either.
    let text = String(decoding: Made.file(biases: [7777, 0, 0, 0, 0]), as: UTF8.self)
    XCTAssertTrue(text.contains("7777"))
    XCTAssertNil(AdMeaningModel(data: Data(text.replacingOccurrences(of: "7777", with: "1e999").utf8)))
    XCTAssertNil(AdMeaningModel(data: Made.file(biases: [2_000_000, 0, 0, 0, 0])))
    XCTAssertNil(AdMeaningModel(data: Made.file(probes: [(Made.probeOne, [1e30, 0, 0, 0]), (Made.probeTwo, [0, 1, 0, 0])])))
  }

  func testAModelWithNothingLearnedIsRefused() {
    XCTAssertNil(AdMeaningModel(data: Made.file(weights: [Float](repeating: 0, count: 20))))
  }

  // MARK: The layer is on or off

  func testAMatchingEmbedderTurnsTheLayerOn() {
    XCTAssertEqual(model().state(for: Made.embedder()), .ready)
  }

  func testAWrongDimensionOrRevisionTurnsTheLayerOff() {
    let wrongDimension = MadeEmbedder(dimension: 5, revision: 7, table: Made.table)
    guard case .off(let why) = model().state(for: wrongDimension) else { return XCTFail("should be off") }
    XCTAssertTrue(why.contains("5") && why.contains("4"), why)
    guard case .off(let other) = model().state(for: Made.embedder(revision: 8)) else {
      return XCTFail("should be off")
    }
    XCTAssertTrue(other.lowercased().contains("revision"), other)
    // Nothing is embedded when the layer is off before it starts.
    let embedder = Made.embedder(revision: 8)
    let run = model().probabilities(lines: Made.lines([Made.ask]), duration: nil, embedder: embedder)
    XCTAssertEqual(run.rows, [])
    XCTAssertEqual(embedder.calls, [])
  }

  func testTheProbeCheckStopsAtZeroPointZeroTwo() {
    // Moving two numbers of a probe by `shift` each moves the unit vector by about shift * 1.41.
    func embedder(shift: Double) -> MadeEmbedder {
      var table = Made.table
      table[Made.probeOne] = [0.5 + shift, 0.5 - shift, 0.5, 0.5]
      return MadeEmbedder(dimension: 4, revision: 7, table: table)
    }
    // About 0.014 away is inside the limit, about 0.025 away is outside it, so a limit of 0.01
    // or of 0.06 would each fail one of these.
    XCTAssertEqual(model().state(for: embedder(shift: 0.01)), .ready)
    guard case .off(let why) = model().state(for: embedder(shift: 0.018)) else {
      return XCTFail("should be off")
    }
    XCTAssertTrue(why.lowercased().contains("probe"), why)
    XCTAssertEqual(AdMeaningModel.probeLimit, 0.02)
    let run = model().probabilities(
      lines: Made.lines([Made.ask]), duration: nil, embedder: embedder(shift: 0.018))
    XCTAssertEqual(run.state, .off(why))
    XCTAssertEqual(run.rows, [])
  }

  func testAProbeThatCannotBeEmbeddedTurnsTheLayerOff() {
    let embedder = Made.embedder()
    embedder.set(Made.probeTwo, to: nil)
    guard case .off = model().state(for: embedder) else { return XCTFail("should be off") }
    embedder.set(Made.probeTwo, to: [1, 0, 0])  // the wrong length
    guard case .off = model().state(for: embedder) else { return XCTFail("should be off") }
    embedder.set(Made.probeTwo, to: [0, 0, 0, 0])  // no direction
    guard case .off = model().state(for: embedder) else { return XCTFail("should be off") }
    embedder.set(Made.probeTwo, to: [.nan, 0, 0, 0])
    guard case .off = model().state(for: embedder) else { return XCTFail("should be off") }
  }

  // MARK: Rows

  func testRowsAreTheSoftmaxOfTheWeights() throws {
    let lines = Made.lines([Made.ask, Made.talk, "a line nobody embedded"])
    let run = model().probabilities(lines: lines, duration: 100, embedder: Made.embedder())
    XCTAssertEqual(run.state, .ready)
    XCTAssertEqual(run.rows.count, 3)
    for row in run.rows {
      XCTAssertEqual(row.count, 5)
      XCTAssertEqual(row.reduce(0, +), 1, accuracy: 1e-9)
    }
    // ask is [1, 0.1, 0, 0] / its length: host_ask gets 5 * 0.995 and none gets 0.
    let length = (1.0 + 0.01).squareRoot()
    let scores = [0, 0, 0, 5 * 1 / length, 0]
    let total = scores.map { exp($0) }.reduce(0, +)
    for (got, score) in zip(run.rows[0], scores) { XCTAssertEqual(got, exp(score) / total, accuracy: 1e-6) }
    XCTAssertGreaterThan(run.rows[0][3], 0.9)
    XCTAssertGreaterThan(run.rows[1][0], 0.9)
    // A line the embedder has no vector for is plain talk, not a guess.
    XCTAssertEqual(run.rows[2], [1, 0, 0, 0, 0])
  }

  func testAnEmptyTranscriptHasNoRowsAndNoSpans() {
    let embedder = Made.embedder()
    let run = model().probabilities(lines: [], duration: nil, embedder: embedder)
    XCTAssertEqual(run.state, .ready)
    XCTAssertEqual(run.rows, [])
    XCTAssertNil(run.secondsPerLine)
    XCTAssertEqual(model().spans(lines: [], duration: nil, embedder: embedder), [])
  }

  // MARK: One decoder for both models

  /// The word model's own reference example (the same weights and lines as AdWordModelTests,
  /// whose expected spans are the oracle here): its rows are what the meaning model must decode
  /// to the same spans.
  private static let referenceModel: AdWordModel = {
    let weights: [String: Any] = [
      "3916": [-1.0, 0.0, 1.0, 0.0, 0.0], "14330": [-0.5, 0.5, 0.0, 0.0, 0.0],
      "44798": [-0.5, 0.0, 0.5, 0.0, 0.0], "49919": [-2.0, 2.0, 0.0, 0.0, 0.0],
      "122389": [-3.0, 3.0, 0.0, 0.0, 0.0], "153606": [0.2, 0.3, 0.0, 0.0, 0.0],
      "161629": [-1.0, 2.0, 0.0, 0.0, 0.0], "161948": [-1.0, 1.0, 0.0, 0.0, 0.0],
      "168660": [-0.5, 0.0, 0.5, 0.0, 0.0], "211303": [5.0, 0.0, 0.0, 0.0, 0.0],
      "242859": [-4.0, 0.0, 3.0, 0.0, 0.0],
    ]
    let json: [String: Any] = [
      "version": 1, "buckets": 262144, "classes": AdWordModel.classes, "weights": weights,
    ]
    return AdWordModel(data: try! JSONSerialization.data(withJSONObject: json))!
  }()

  private static let referenceLines: [NumberedLine] = [
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

  func testBothModelsDecodeTheSameRowsToTheSameSpans() throws {
    let word = Self.referenceModel
    let lines = Self.referenceLines
    let rows = word.probabilities(lines: lines, duration: 150)
    let wordSpans = word.spans(lines: lines, duration: 150)
    XCTAssertEqual(wordSpans.count, 2)
    // The decoder on its own gives exactly what the word model gives.
    XCTAssertEqual(AdWordModel.decode(rows: rows, lines: lines, thresholds: word.thresholds), wordSpans)

    // A meaning model that gives these very rows: line i has its own direction (number i of
    // nine) and the weights for that number are the logs of the row.
    var weights = [Float](repeating: 0, count: 5 * 9)
    for (i, row) in rows.enumerated() { for c in 0..<5 { weights[c * 9 + i] = Float(log(row[c])) } }
    var table: [String: [Double]] = [:]
    for (i, line) in lines.enumerated() { table[line.text] = (0..<9).map { $0 == i ? 1.0 : 0.0 } }
    table[Made.probeOne] = [1, 0, 0, 0, 0, 0, 0, 0, 0]
    table[Made.probeTwo] = [0, 1, 0, 0, 0, 0, 0, 0, 0]
    let meaning = model(
      Made.file(
        dimension: 9, weights: weights,
        probes: [(Made.probeOne, table[Made.probeOne]!), (Made.probeTwo, table[Made.probeTwo]!)]))
    let embedder = MadeEmbedder(dimension: 9, revision: 7, table: table)
    let found = meaning.spans(lines: lines, duration: 150, embedder: embedder)
    XCTAssertEqual(found.count, wordSpans.count)
    for (got, want) in zip(found, wordSpans) {
      XCTAssertEqual(got.firstLine, want.firstLine)
      XCTAssertEqual(got.lastLine, want.lastLine)
      XCTAssertEqual(got.sort, want.sort)
      XCTAssertEqual(got.sure, want.sure)
      XCTAssertEqual(got.score, want.score, accuracy: 1e-5)
    }
  }

  func testTheDecoderIgnoresRowsThatDoNotMatchTheLines() {
    let lines = Made.lines([Made.ask, Made.talk])
    // One row for two lines, and it is an ad row: without the check it would open a span.
    XCTAssertEqual(AdWordModel.decode(rows: [[0, 1, 0, 0, 0]], lines: lines, thresholds: .init()), [])
    // Two rows of two numbers: without the check the decoder would read a third number.
    XCTAssertEqual(AdWordModel.decode(rows: [[0, 1], [0, 1]], lines: lines, thresholds: .init()), [])
    // The same rows at the right size do open a span.
    let right = AdWordModel.decode(
      rows: [[0, 1, 0, 0, 0], [0, 1, 0, 0, 0]], lines: lines, thresholds: .init())
    XCTAssertEqual(right.count, 1)
  }

  func testTheMeaningModelOffersItsOwnStartThresholdForQuestions() {
    XCTAssertEqual(model().askBelow, 0.6)
    let strict = model(Made.file { $0["thresholds"] = ["start": 0.7, "stay": 0.4, "sure": 0.9] })
    XCTAssertEqual(strict.askBelow, 0.7)
  }

  // MARK: The time guard

  func testTheTimeGuardGivesUpOnASlowPhone() {
    let clock = FakeClock()
    let embedder = Made.embedder()
    embedder.onCall { clock.advance(1.0 / 32) }  // 31.25 ms a line
    let lines = Made.lines((0..<60).map { $0 % 2 == 0 ? Made.ask : Made.talk })
    let run = model().probabilities(lines: lines, duration: nil, embedder: embedder, clock: clock.now)
    guard case .off(let why) = run.state else { return XCTFail("should give up") }
    XCTAssertTrue(why.contains("31"), why)
    XCTAssertEqual(run.rows, [])
    XCTAssertEqual(try XCTUnwrap(run.secondsPerLine), 1.0 / 32, accuracy: 1e-9)
    // It stopped after the 50 timed lines (and the two probes before them).
    XCTAssertEqual(embedder.calls.count, 2 + 50)
  }

  func testTheTimeGuardKeepsAFastPhone() {
    let clock = FakeClock()
    let embedder = Made.embedder()
    embedder.onCall { clock.advance(1.0 / 64) }  // 15.6 ms a line
    let lines = Made.lines((0..<60).map { $0 % 2 == 0 ? Made.ask : Made.talk })
    let run = model().probabilities(lines: lines, duration: nil, embedder: embedder, clock: clock.now)
    XCTAssertEqual(run.state, .ready)
    XCTAssertEqual(run.rows.count, 60)
    XCTAssertEqual(embedder.calls.count, 2 + 60)
  }

  func testAShortEpisodeIsTimedOverItsOwnLines() {
    let clock = FakeClock()
    let embedder = Made.embedder()
    embedder.onCall { clock.advance(1.0 / 32) }
    let run = model().probabilities(
      lines: Made.lines([Made.ask, Made.talk]), duration: nil, embedder: embedder, clock: clock.now)
    guard case .off = run.state else { return XCTFail("should give up") }
  }
}
