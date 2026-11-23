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

  // MARK: The command

  private func folder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("fit-" + UUID().uuidString)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  func testTheCommandWritesTheResult() throws {
    let dir = folder()
    let input = dir.appendingPathComponent("examples.txt").path
    let output = dir.appendingPathComponent("fit.json").path
    try fixture.write(toFile: input, atomically: true, encoding: .utf8)
    var said: [String] = []
    let code = AdWordFit.run([input, output, "--c", "0.5", "--min-count", "1"], out: { said.append($0) }, err: { XCTFail($0) })
    XCTAssertEqual(code, 0)
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: output))) as! [String: Any]
    XCTAssertEqual((json["bias"] as! [Double]).count, 5)
    XCTAssertEqual((json["weights"] as! [String: [Double]]).count, 60)
    XCTAssertEqual(json["objective"] as! Double, 484.228126, accuracy: 1)
    XCTAssertGreaterThan(json["iterations"] as! Int, 0)
  }

  func testTheCommandSaysASetUpProblemAndExitsWithTwo() throws {
    let dir = folder()
    let good = dir.appendingPathComponent("good.txt").path
    let bad = dir.appendingPathComponent("bad.txt").path
    try "buckets 5 classes 5\n0 1\n".write(toFile: good, atomically: true, encoding: .utf8)
    try "buckets 5 classes 5\n9 1\n".write(toFile: bad, atomically: true, encoding: .utf8)
    let output = dir.appendingPathComponent("fit.json").path
    let attempts: [[String]] = [
      [], [good], [good, output, "--c", "0"], [good, output, "--min-count", "x"],
      [good, output, "--iterations", "0"], [good, output, "--class-cap", "0.5"],
      [good, output, "--nope"], [dir.appendingPathComponent("missing.txt").path, output], [bad, output],
      [good, dir.appendingPathComponent("no/such/folder/fit.json").path],
    ]
    for arguments in attempts {
      var errors: [String] = []
      XCTAssertEqual(AdWordFit.run(arguments, out: { _ in }, err: { errors.append($0) }), 2, "\(arguments)")
      XCTAssertEqual(errors.count, 1, "\(arguments)")
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: output))
  }

  private var fixture: String {
    """
    buckets 60 classes 5
    0 8 12 22 26 43
    2 2 6 20 23 25 32 50
    0 22 43 46
    3 8 21 23 47 55
    0 7 8 15 20 22 42 49 54 55 59
    2 6 7 10 26 32 34 57 59
    0 4 8 11 13 15 27 45 46 50 54
    3 6 14 18 23 26 43
    0 15 17 39 53 54 56 59
    0 7 13 25 30 44
    2 7 10 50
    3 11 29 36 56
    0 15 16 28 30 31 37 42 46 49
    0 10 15 22 47 52 56
    2 32 56 57 58
    0 12 26 29 30 32 44 49 54 58
    0 3 14 18 20 27 30 35 54 59
    0 45 47 49
    3 17 18 19 20 40 42 44 50 58
    1 9 23 47 55
    2 5 9 10 16 17 19 30 35 50 56 57
    1 6 16 27 35 48
    0 0 13 14 24 26 41 49 57
    0 2 3 7 12 25 27 31 33 40 46
    0 0 3 24 28 32 39 43 45 57
    0 2 5 24 33 57
    0 4 7 19 27 33 35 37 45 47 54
    3 11 17 30 52
    0 6 9 25 27 33 42 45 48 49 55
    4 6 22 24 25 33 38 39 40
    0 22 25 44 55
    0 3 9 20 30 48 49 52
    0 5 26 42 45 47 57
    3 17 23 29 33 34 39 49 51
    0 6 11 22 25 35
    0 14 17 19 21 25 30 34 59
    0 14 16 34 46 51 53 56
    0 18 19 29 41 53 56
    1 13 18 29 32 51
    0 9 16 25 27 28 40 46 48 49
    0 12 18 31 32 42 48
    0 3 8 10 14 26 29 35 43 49
    4 15 16 17 21 22 38 53
    2 4 9 12 20 37 53 57
    4 4 13 15 23 38
    1 8 9 11 23 42 48
    1 16 22 29 35 37 39 46 48 55
    2 3 4 13 15 20 26 29 54
    1 8 13 29 38
    0 10 13 16 52 56 57
    0 9 24 57
    0 1 7 9 16 27 45
    4 8 9 24 25 26 28 37 40 49
    2 19 35 40 53
    2 21 36 58
    0 2 6 8 16 18 19 53 57
    4 40 54 56
    2 11 23 34 36 39 40 45 46 47 53 57
    0 1 15 23 41 43
    0 4 5 7 20 25 31 45 51 57
    1 18 26 33 55 58
    0 11 22 40 43 51 53
    4 4 5 8 14 47 56
    0 12 41 47
    0 7 16 18 25 42 45 48 56
    3 2 5 9 11 16 20 30 33 34 50
    0 18 22 27 34 36 37 42 51 54 55
    0 10 12 38 44 56
    3 1 7 8 10 23 41
    2 12 13 16 29 42 43 51 54
    2 17 18 22 25 26 30 36
    0 11 16 36
    0 12 27 47
    3 4 7 16 23 30 31 33 34 37 55
    0 3 20 26 28 35 48 50 51 57
    4 4 14 15 22 29 31 33 45
    0 27 28 45 58
    4 0 9 10 23 44
    0 14 34 57
    0 19 34 35 36 41 45 46
    2 9 10 11 26 27 29 32 33 34 37 46
    0 8 18 24 32 44 49 50
    0 10 24 32 41
    0 6 14 23 36 40 49 55
    0 2 10 19 32 41 42 50 54
    3 4 29 55 56
    3 29 31 35 58
    1 8 21 35 41 45 48 52 58
    0 15 18 46 52
    0 9 27 28 32 36 39 52
    1 3 8 9 11 17 29 58
    0 2 7 13 16 21 22 24 27 35 36 44
    0 12 15 24 25 45 46 51
    4 3 8 15 18 23 26 29 44 58
    0 7 8 20 25 28 40 42 49 51 56
    0 2 5 6 7 9 12 19 42 49 54 58
    3 4 21 23 27 29 34 36 50 52 55
    1 9 36 37 40 48 50 55 59
    4 4 12 15 29 42 46 53 59
    4 22 24 29 39 40 56
    0 5 13 24 26 28 45
    4 8 9 25 44
    0 2 28 33
    0 13 14 16 18 25 30 31
    4 6 11 15 18 19 29 38 46 59
    1 2 17 18 24 29 38 39 44 54
    4 9 20 35 36 39 45 51
    3 4 18 33 58
    0 11 12 46 59
    0 2 28 36 47 57 59
    0 0 16 17 19 20 23 35 36 42 56
    3 4 8 44
    2 1 4 30 32
    0 0 12 14 23 26 35 42 53 54 57
    0 5 38 52 55
    2 1 6 13 50 59
    4 6 9 12 15
    0 5 10 19 20 31 39
    4 1 6 13 15 32 35 37 40 59
    0 0 7 12 31 36 38 49 53 55
    0 7 22 41 48
    0 2 10 13 15 19 27 38 41 51 58
    1 0 18 21 24 26 30 43 51 54 58
    0 30 36 41 42 52
    2 2 5 7 11 16 19 26 30 47 52 56
    4 3 6 26 30 34 39 43
    4 7 9 14 19 38 56
    0 34 37 43 52 53 57
    0 0 24 25 41 49 59
    1 23 29 32 58
    0 3 10 19 25 32 39
    0 22 32 43 46 52
    0 10 14 30 39 51 54 55
    0 17 27 34 39 43 44 45 48 51
    0 3 12 16 33 35 36 41 48 55
    0 4 15 21 25 32 49 56
    4 3 8 26 34 40 53 57 58
    0 3 10 12 16 25 37 52 58
    2 2 7 12 17 31 33 36 57
    0 43 48 54 55
    0 8 15 16 44
    0 6 12 15 22 25 34 39 41 57
    0 27 42 54 56 57
    0 18 24 27 37 53
    1 5 18 36 40 48 52
    2 1 16 59
    1 0 9 19 34 40 57
    2 28 32 33 35
    0 6 25 27 31 33 48
    2 4 19 25 37
    4 6 23 30 33 42 44 48
    0 15 31 43 48 49 59
    0 10 24 32 34 38 43 46 49 53 59
    0 10 17 27 28 38 56 57
    0 1 5 6 24 37 41 47 53 54 56
    3 2 4 6 11 18 25 29 31 32 46 54
    0 10 36 38 49 53 56
    1 0 4 7 22 24 26 34 48 57
    0 15 17 18 39 46 48 53
    1 7 21 26 35 45
    1 1 6 17 30 32 40 43 44 51
    0 2 5 14 17 27 35 46 52 59
    0 3 5 27 44 47 52 53
    0 11 12 15 17 19 24 35 37 39 53
    0 11 17 21 23 26 28 30 32 49 52 54
    0 5 17 24 27 44 46 49 52
    4 11 23 25 26 30 34 35
    2 17 20 24 26 36 53
    0 1 6 16 28 29 31 41 48 57
    3 17 20 49 50 58
    3 3 5 17 18 27 30 47 50
    4 7 9 16 17 18 28 29 40 53
    2 3 24 33 36 38 51 54
    3 5 28 29 30 38 47 58 59
    0 15 23 49 56
    0 0 4 5 7 12 44 55
    3 17 49 54
    0 0 14 15 20 23 39 53 56 57
    1 23 27 37 42 55 58
    4 5 8 21 22 23 37 40 43 57 59
    2 1 31 33 50
    0 3 7 14 19 21 22 45 47 49 54 59
    0 0 1 2 15 21 35 40 42 43 45 53
    1 22 29 30
    4 6 44 51
    0 2 7 11 14 32 41 49 53
    0 3 10 23 24 31 46 53 56
    4 14 20 26 44 51 52 56
    2 25 45 58
    0 6 10 24
    0 24 29 36 39 41 59
    0 21 24 28 35 45
    4 8 14 16 17 18 26 33 45 50 55
    0 10 20 37 53
    0 0 8 11 26 33 35 39 42 45 47 57
    1 6 15 19 22 38 40 42 47 52
    4 12 16 31 40 42
    0 5 19 48
    1 0 5 16 34 35 39 47
    0 13 26 28 43 48
    3 14 21 23 44
    2 13 37 43
    0 0 3 15 22 23 26 35 41 46
    0 0 19 31 38 41
    2 6 19 20 23 36 40 57
    2 1 3 29 33 37 50
    4 4 16 39 55
    0 0 6 7 15 18 21 37 39
    2 6 7 12 14 16 19 21 29 57
    1 8 17 21 22 29 34 39 46 47
    0 8 21 28 44 49 58
    0 0 49 59
    1 42 44 47 52 59
    0 13 22 39 45
    3 1 10 17 18 23 41 48 58
    0 6 11 13 14 15 21 25 27 39 40 47
    0 5 7 11 14 27 34 41 44 46
    4 5 6 32 38 48 49 50 56
    0 10 43 44 49
    3 17 31 39 40 49
    1 9 22 23 29 47 50
    1 21 27 35 40 51 59
    4 0 5 30
    0 5 43 45 46 47 51
    1 11 21 24 26 30 34 35 44 47
    1 18 23 59
    3 1 8 23 54 56 57
    4 6 11 25 26 38 46 49
    0 8 24 59
    4 1 8 9 27 33 38 40 43 54 59
    0 20 41 53
    0 17 27 39 44
    0 15 41 42
    4 0 6 14 27 29 32 40 51 59
    4 4 6 12 14 25 26 29
    0 3 14 26 31 40 44 51 57
    4 0 6 9 17 23 25 26 30 54
    2 16 18 20 28 31 32 38 40 59
    0 7 10 16 18 19 45 46 53 56
    1 1 7 9 12 17 21 24 35 48 52 55
    1 16 20 21 38 51 58
    1 0 8 36 37 38 50 51 56 59
    1 8 32 47
    0 13 18 24 27 30 38 41 52
    2 4 10 16 27 32 33 38 43 57 58
    0 11 12 29 40 41
    0 1 20 21 38 49
    2 12 16 26 28 32 37 48 53
    1 19 26 38 49 51 56
    3 17 47 59
    1 29 37 45 47 48 50 51 59
    0 8 15 20 28 35 36 38 44 46 49
    0 14 23 27 33 37 43 56 57
    0 0 2 4 9 16 22 24 25 40 49 52
    0 18 19 23 26 35
    0 3 5 13 16 22 37 51 53
    1 6 9 30 37 43 45 51 52
    0 3 19 22 24 25 35 46 58
    0 9 15 19 22 23 27 43
    1 8 11 27 29 30 43 47
    2 16 26 45 48 50
    0 9 15 21 33 35 39 41 52
    2 1 21 39 44
    2 2 5 7 20 34 38 46 47 50
    0 10 21 27 33
    3 14 18 20 31 33 39 41 42 47 58 59
    0 4 5 27 38 43 56
    0 14 16 21 22 26 31 39
    0 2 21 25 26 34 41 46
    0 0 12 44 58
    4 3 21 26 32 40
    2 9 11 25 50 56
    0 10 15 24 39 40 42 45 46 55
    4 4 13 18 23 26 30 41 42 56
    2 1 16 53
    0 2 11 13 16 24 31 38 55 59
    0 11 42 46 59
    1 0 4 12 34 43 50 52
    3 5 18 20 35
    0 10 14 21 27 29 43 46
    0 3 7 9 17 24 41 54
    4 3 6 7 32 46
    0 14 16 18 42
    0 25 27 30 40 41 47 49 51 58
    4 4 14 21 29 38 42 57
    4 7 16 35 56
    2 5 6 18 24 33 35 44 52 53 54
    0 11 32 49 52 54 56
    2 1 17 27 45
    0 0 4 15
    1 0 22 29 32 58
    3 9 20 41
    3 12 19 23 47 50 55
    4 6 21 24 37
    0 3 5 12 13 20 39 41 50 51 52 53
    0 0 2 6 11 20 39 55
    0 11 13 27 45 59
    0 0 17 19 52
    0 0 8 10 26 33 35 45 50 53 55
    0 3 14 18 23 33 58

    """
  }
}
