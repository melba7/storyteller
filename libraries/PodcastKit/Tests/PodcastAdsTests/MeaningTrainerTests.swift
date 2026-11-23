import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

final class MeaningTrainerTests: XCTestCase {
  /// Made training vectors: `count` noisy copies of a direction, with a fixed little wobble so
  /// the examples differ, as unit vectors.
  private func examples(_ classIndex: Int, around centre: [Double], count: Int) -> [MeaningExample] {
    (0..<count).map { n in
      let wobble = Double((n * 7) % 5 - 2) * 0.03
      let raw = centre.enumerated().map { $0.element + ($0.offset == (n % 4) ? wobble : 0) }
      return MeaningExample(classIndex: classIndex, vector: MeaningVectors.unit(raw)!.map { Float($0) })
    }
  }

  private var twoClasses: [MeaningExample] {
    examples(3, around: [1, 0.1, 0, 0], count: 20) + examples(0, around: [0, 0.1, 1, 0], count: 40)
  }

  /// The model the trainer's numbers make.
  private func model(_ trained: MeaningTrainer.Trained) -> AdMeaningModel {
    AdMeaningModel(
      revision: 7, dimension: 4, weights: trained.weights, biases: trained.biases,
      probes: [
        AdMeaningModel.Probe(text: Made.probeOne, vector: [0.5, 0.5, 0.5, 0.5]),
        AdMeaningModel.Probe(text: Made.probeTwo, vector: [0.5, -0.5, 0.5, -0.5]),
      ])!
  }

  // MARK: Softmax with AdaGrad

  func testTheTrainerSeparatesTwoMadeClasses() throws {
    let trained = try XCTUnwrap(MeaningTrainer.train(examples: twoClasses, dimension: 4))
    XCTAssertEqual(trained.weights.count, 5 * 4)
    XCTAssertEqual(trained.biases.count, 5)
    XCTAssertTrue(trained.weights.allSatisfy(\.isFinite) && trained.biases.allSatisfy(\.isFinite))
    let learned = model(trained)
    // Every made sentence of the table lands in its class, including ones never trained on.
    let lines = Made.lines([Made.ask, Made.ask2, Made.talk, Made.talk2])
    let rows = learned.probabilities(lines: lines, duration: nil, embedder: Made.embedder()).rows
    XCTAssertEqual(rows.map { $0.firstIndex(of: $0.max()!)! }, [3, 3, 0, 0])
    XCTAssertGreaterThan(rows[0][3], 0.9)
    XCTAssertGreaterThan(rows[2][0], 0.9)
    // A vector between the two, nearer the favour, still goes to the favour.
    let between = learned.probabilities(vectors: [[0.8, 0.2, 0.3, 0]])
    XCTAssertEqual(between[0].firstIndex(of: between[0].max()!), 3)
  }

  func testTheTrainerIsDeterministic() throws {
    let first = try XCTUnwrap(MeaningTrainer.train(examples: twoClasses, dimension: 4, epochs: 3, seed: 5))
    let second = try XCTUnwrap(MeaningTrainer.train(examples: twoClasses, dimension: 4, epochs: 3, seed: 5))
    XCTAssertEqual(first, second)
    XCTAssertEqual(
      model(first).fileData(trained: [:]), model(second).fileData(trained: [:]))
    // Another seed shuffles the examples differently, which moves the numbers a little.
    let other = try XCTUnwrap(MeaningTrainer.train(examples: twoClasses, dimension: 4, epochs: 3, seed: 6))
    XCTAssertNotEqual(first.weights, other.weights)
  }

  func testTheTrainerReportsEachPass() throws {
    var said: [String] = []
    _ = MeaningTrainer.train(examples: twoClasses, dimension: 4, epochs: 2) { said.append($0) }
    XCTAssertEqual(said.count, 2)
    XCTAssertTrue(said[0].hasPrefix("Pass 1 of 2"), said[0])
  }

  func testTheTrainerIgnoresBadExamplesAndNeedsSomeGoodOnes() throws {
    XCTAssertNil(MeaningTrainer.train(examples: [], dimension: 4))
    XCTAssertNil(MeaningTrainer.train(examples: twoClasses, dimension: 0))
    XCTAssertNil(MeaningTrainer.train(examples: twoClasses, dimension: 4, epochs: 0))
    let bad = [
      MeaningExample(classIndex: 9, vector: [1, 0, 0, 0]),
      MeaningExample(classIndex: -1, vector: [1, 0, 0, 0]),
      MeaningExample(classIndex: 1, vector: [1, 0, 0]),
      MeaningExample(classIndex: 1, vector: [.nan, 0, 0, 0]),
      MeaningExample(classIndex: 1, vector: [.infinity, 0, 0, 0]),
    ]
    XCTAssertNil(MeaningTrainer.train(examples: bad, dimension: 4))
    // Bad ones among good ones change nothing.
    let clean = try XCTUnwrap(MeaningTrainer.train(examples: twoClasses, dimension: 4, epochs: 2))
    let mixed = try XCTUnwrap(MeaningTrainer.train(examples: twoClasses + bad, dimension: 4, epochs: 2))
    XCTAssertEqual(clean.weights.count, mixed.weights.count)
    XCTAssertTrue(mixed.weights.allSatisfy(\.isFinite))
  }

  func testAClassWithNoExamplesDoesNotBreakTheTrainer() throws {
    // Only "none" and "host_ask" appear; the other three classes have no example at all.
    let trained = try XCTUnwrap(MeaningTrainer.train(examples: twoClasses, dimension: 4))
    XCTAssertTrue(trained.weights.allSatisfy { $0.isFinite && abs($0) < 1000 })
    // One class only: every example is "none".
    let one = try XCTUnwrap(MeaningTrainer.train(examples: examples(0, around: [0, 0, 1, 0], count: 5), dimension: 4))
    XCTAssertTrue(one.weights.allSatisfy(\.isFinite))
  }

  // MARK: The class of each line

  private func episode(starts: [Double], truth: [TeachingTruth], maybe: [TeachingTruth] = []) -> TeachingEpisode {
    let lines = starts.enumerated().map { TranscriptLine(start: $0.element, end: $0.element + 9, text: "line \($0.offset)") }
    let identity = TranscriptIdentity(
      locale: "en-US", recogniser: "t", recogniserVersion: "1", osVersion: "", sha256: "")
    let transcript = Transcript(identity: identity, duration: (starts.last ?? 0) + 9, lines: lines, words: [])
    return TeachingEpisode(
      id: "e", feed: "f", show: "s", title: "t", transcript: transcript, truth: truth, maybe: maybe,
      onShelf: false)
  }

  func testLinesTakeTheClassOfTheStretchThatCoversThem() {
    let starts = [0.0, 10, 20, 30, 40, 50, 60]
    let found = MeaningTrainer.lineClasses(
      for: episode(
        starts: starts,
        truth: [
          TeachingTruth(start: 10, end: 30, sort: "host_ask"),
          // Overlaps the first one: the first strong stretch wins the shared line.
          TeachingTruth(start: 20, end: 50, sort: "sponsor"),
        ],
        maybe: [TeachingTruth(start: 50, end: 60, sort: "network_promo")]))
    // none, host_ask, host_ask, sponsor, sponsor, "only a weak mark" (left out), none.
    XCTAssertEqual(found, [0, 3, 3, 1, 1, nil, 0])
  }

  func testAWeakMarkUnderAStrongOneDoesNotLeaveALineOut() {
    let found = MeaningTrainer.lineClasses(
      for: episode(
        starts: [0, 10, 20],
        truth: [TeachingTruth(start: 0, end: 20, sort: "intro_credits")],
        maybe: [TeachingTruth(start: 0, end: 30, sort: "sponsor")]))
    XCTAssertEqual(found, [4, 4, nil])
  }

  func testTheTimesOfAMarkAreRoundedToATenthButTheLinesAreStillRight() {
    // The label file rounds a stretch's times to one decimal; the transcript's lines are not.
    let found = MeaningTrainer.lineClasses(
      for: episode(
        starts: [0.04, 10.07, 20.04, 30.06],
        truth: [TeachingTruth(start: 10.1, end: 30.1, sort: "network_promo")]))
    XCTAssertEqual(found, [0, 2, 2, 0])
  }

  // MARK: The check on the shelf

  private func held(
    _ texts: [String], classes: [Int?], id: String = "e", feed: String = "f"
  ) -> MeaningHeldEpisode {
    let lines = texts.enumerated().map {
      NumberedLine(number: $0.offset + 1, start: Double($0.offset) * 5, end: Double($0.offset) * 5 + 5, text: $0.element)
    }
    let embedder = Made.embedder()
    return MeaningHeldEpisode(
      id: id, feed: feed, lines: lines, classes: classes,
      vectors: lines.map { embedder.vector(for: $0.text).flatMap(MeaningVectors.unit) })
  }

  func testTheShelfNumbersAreInSecondsOfTheSpansThePhoneWouldCut() throws {
    let texts = (0..<12).map { (3...8).contains($0) ? Made.ask : Made.talk }
    let classes: [Int?] = (0..<12).map { (3...8).contains($0) ? 3 : 0 }
    let numbers = MeaningHeldOut.check(
      model: AdMeaningModel(data: Made.file())!,
      episodes: [held(texts, classes: classes), held(texts, classes: classes, id: "f", feed: "g")])
    XCTAssertEqual(numbers.episodes, 2)
    XCTAssertEqual(numbers.shows, 2)
    XCTAssertEqual(numbers.lines, 24)
    XCTAssertEqual(numbers.predictedAdSeconds, 60, accuracy: 1e-9)
    XCTAssertEqual(numbers.adSeconds, 60, accuracy: 1e-9)
    XCTAssertEqual(numbers.anyAd.precision, 1)
    XCTAssertEqual(numbers.anyAd.recall, 1)
    XCTAssertEqual(numbers.lineAnyAd.precision, 1)
    XCTAssertEqual(numbers.classes["host_ask"]?.recall, 1)
    // No sponsor line was guessed or marked: nothing to divide by, so null, not zero.
    XCTAssertNil(numbers.classes["sponsor"]?.precision)
    XCTAssertEqual(numbers.classes.keys.sorted(), ["host_ask", "intro_credits", "network_promo", "sponsor"])

    let json = numbers.json
    XCTAssertEqual(Set(json.keys), [
      "episodes", "shows", "lines", "predictedAdSeconds", "adSeconds", "anyAd", "lineAnyAd", "classes",
    ])
    let sponsor = ((json["classes"] as? [String: Any])?["sponsor"]) as? [String: Any]
    XCTAssertTrue(sponsor?["precision"] is NSNull)
    XCTAssertTrue(sponsor?["recall"] is NSNull)
    XCTAssertEqual((json["anyAd"] as? [String: Any])?["precision"] as? Double, 1)
    XCTAssertTrue(numbers.checkLines[0].hasPrefix("Check on 2 held-out episodes from 2 shows (24 lines)"))
  }

  func testAWrongSpanIsWrongSecondsAndALineWithNoMarkIsLeftOut() {
    // The model cuts lines 3 to 8 but the teacher marked only lines 3 to 5; line 6 is unsure.
    let texts = (0..<12).map { (3...8).contains($0) ? Made.ask : Made.talk }
    var classes: [Int?] = (0..<12).map { (3...5).contains($0) ? 3 : 0 }
    classes[6] = nil
    let numbers = MeaningHeldOut.check(
      model: AdMeaningModel(data: Made.file())!, episodes: [held(texts, classes: classes)])
    XCTAssertEqual(numbers.lines, 11)
    XCTAssertEqual(numbers.predictedAdSeconds, 30, accuracy: 1e-9)
    XCTAssertEqual(numbers.adSeconds, 15, accuracy: 1e-9)
    // Cut: 6 lines of 5 s. Right: lines 3 to 5, so 15 s. The unsure line counts as not an ad.
    XCTAssertEqual(try XCTUnwrap(numbers.anyAd.precision), 0.5, accuracy: 1e-9)
    XCTAssertEqual(numbers.anyAd.recall, 1)
  }

  func testAClassThatDoesNotExistIsLeftOutOfTheCheck() {
    let texts = [Made.ask, Made.talk, Made.talk2]
    let numbers = MeaningHeldOut.check(
      model: AdMeaningModel(data: Made.file())!, episodes: [held(texts, classes: [9, -1, 0])])
    XCTAssertEqual(numbers.lines, 1)  // only the line with a real class counts
  }

  func testNoEpisodesGiveNullsAndNoCrash() {
    let numbers = MeaningHeldOut.check(model: AdMeaningModel(data: Made.file())!, episodes: [])
    XCTAssertEqual(numbers.episodes, 0)
    XCTAssertNil(numbers.anyAd.precision)
    XCTAssertNil(numbers.anyAd.recall)
    XCTAssertEqual(numbers.predictedAdSeconds, 0)
  }
}
