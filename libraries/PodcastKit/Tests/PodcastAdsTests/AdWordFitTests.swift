import XCTest

@testable import PodcastAds

/// The fitter behind `podcast-teach fit`. The made-up problem in `fixture` and its exact optimum
/// (found with scikit-learn: c 0.5, every bucket kept) hold no private text.
final class AdWordFitTests: XCTestCase {
  private func examples(_ text: String) -> AdWordFit.Examples {
    switch AdWordFit.parse(Data(text.utf8)) {
    case .success(let found): return found
    case .failure(let problem): XCTFail(problem.message); return AdWordFit.Examples(buckets: 1)
    }
  }

  private func problem(_ text: String) -> String? {
    if case .failure(let found) = AdWordFit.parse(Data(text.utf8)) { return found.message }
    return nil
  }

  private func probabilities(_ result: AdWordFit.Result, _ buckets: [Int]) -> [Double] {
    var z = result.bias
    for bucket in buckets {
      guard let at = result.buckets.firstIndex(of: Int32(bucket)) else { continue }
      for c in 0..<5 { z[c] += result.weights[5 * at + c] }
    }
    let top = z.max()!
    let e = z.map { exp($0 - top) }
    return e.map { $0 / e.reduce(0, +) }
  }

  // MARK: The reference problem

  func testTheFitMatchesTheReferenceOptimum() {
    var settings = AdWordFit.Settings()
    settings.c = 0.5
    settings.minCount = 1
    settings.iterations = 500
    let result = AdWordFit.fit(examples(fixture), settings: settings)
    XCTAssertEqual(result.objective, 484.228126, accuracy: 484.228126 * 0.001)
    for (buckets, want) in probes {
      for (got, value) in zip(probabilities(result, buckets), want) { XCTAssertEqual(got, value, accuracy: 0.01) }
    }
  }

  func testTheFitIsTheSameEveryTime() {
    var settings = AdWordFit.Settings()
    settings.minCount = 1
    let first = AdWordFit.fit(examples(fixture), settings: settings)
    XCTAssertEqual(first, AdWordFit.fit(examples(fixture), settings: settings))
  }

  func testTheFitStopsAtTheNumberOfIterations() {
    var settings = AdWordFit.Settings()
    settings.minCount = 1
    settings.iterations = 3
    XCTAssertEqual(AdWordFit.fit(examples(fixture), settings: settings).iterations, 3)
  }

  private let probes: [([Int], [Double])] = [
    ([0, 5, 9], [0.13099, 0.17703, 0.02228, 0.0292, 0.6405]),
    ([1], [0.09012, 0.08586, 0.64379, 0.14194, 0.03828]),
    ([2, 3, 4, 7, 11, 30], [0.40931, 0.0539, 0.06477, 0.30966, 0.16236]),
    ([59], [0.24935, 0.16954, 0.20582, 0.19716, 0.17813]),
    ([], [0.25924, 0.17302, 0.24335, 0.20795, 0.11644]),
    ([10, 20, 30, 40, 50], [0.03252, 0.0124, 0.41497, 0.45745, 0.08266])
  ]

  // MARK: The rules

  func testABucketInFewerLinesThanMinCountIsIgnored() {
    let text = "buckets 10 classes 5\n0 1 2\n0 1 3\n1 1 2\n1 4\n"
    var settings = AdWordFit.Settings()
    settings.minCount = 3
    XCTAssertEqual(AdWordFit.fit(examples(text), settings: settings).buckets, [1])
    settings.minCount = 2
    XCTAssertEqual(AdWordFit.fit(examples(text), settings: settings).buckets, [1, 2])
    settings.minCount = 1
    XCTAssertEqual(AdWordFit.fit(examples(text), settings: settings).buckets, [1, 2, 3, 4])
  }

  func testClassWeightsAreTheRatioToPlainTalkWithACap() {
    let labels: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 3, 3, 3, 3, 3]
    XCTAssertEqual(AdWordFit.classWeights(labels, cap: 5), [1, 5, 5, 2, 5])
    XCTAssertEqual(AdWordFit.classWeights(labels, cap: 3), [1, 3, 3, 2, 3])
    XCTAssertEqual(AdWordFit.classWeights([1, 2], cap: 4), [1, 4, 4, 4, 4])
  }

  func testWithOnlyTheBiasTheWeightedClassesComeOutEqual() {
    // Four plain lines and two of every other class: with the weights 1 and 2 every class counts 4.
    var text = "buckets 4 classes 5\n"
    text += String(repeating: "0\n", count: 4)
    for c in 1...4 { text += String(repeating: "\(c)\n", count: 2) }
    var settings = AdWordFit.Settings()
    settings.minCount = 1
    let result = AdWordFit.fit(examples(text), settings: settings)
    XCTAssertEqual(result.buckets, [])
    for value in probabilities(result, []) { XCTAssertEqual(value, 0.2, accuracy: 1e-4) }
    XCTAssertEqual(result.objective, 4 * 5 * log(5.0), accuracy: 1e-3)
  }

  func testALineWithNoBucketsIsAnExample() {
    let found = examples("buckets 5 classes 5\n0\n1 2\n2 \n")
    XCTAssertEqual(found.labels, [0, 1, 2])
    XCTAssertEqual(found.starts, [0, 0, 1, 1])
    XCTAssertEqual(found.items, [2])
  }

  func testTheLastLineMayLackItsNewline() {
    XCTAssertEqual(examples("buckets 5 classes 5\n0 1\n1 2").count, 2)
  }

  // MARK: Bad input

  func testBadExamplesAreSaidInPlainWords() {
    XCTAssertNotNil(problem(""))
    XCTAssertNotNil(problem("buckets 5 classes 4\n0 1\n"))
    XCTAssertNotNil(problem("buckets x classes 5\n0 1\n"))
    XCTAssertNotNil(problem("buckets 0 classes 5\n0\n"))
    XCTAssertNotNil(problem("buckets 5 classes 5\n"))
    XCTAssertTrue(problem("buckets 5 classes 5\n5 1\n")!.contains("Line 2"))
    XCTAssertTrue(problem("buckets 5 classes 5\n0 1\n0 5\n")!.contains("Line 3"))
    XCTAssertNotNil(problem("buckets 5 classes 5\n0 1 1\n"))
    XCTAssertNotNil(problem("buckets 5 classes 5\n0 1\n\n1 2\n"))
    XCTAssertNotNil(problem("buckets 5 classes 5\n0 a\n"))
    XCTAssertNotNil(problem("buckets 5 classes 5\n0 -1\n"))
    XCTAssertNotNil(problem("buckets 5 classes 5\n0 99999999999999999999\n"))
  }

  private var fixture: String { AdWordFitFixture.text }
}
