import XCTest

@testable import PodcastAudioMatch

/// How well "the strongest change within 10 seconds" lines up with the exactly placed edges of ad
/// spots, against random points, and the plan's go rule.
final class EdgeMeasureTests: XCTestCase {
  private func label(_ segments: [[String: Any]]) -> Data {
    (try? JSONSerialization.data(withJSONObject: ["segments": segments])) ?? Data()
  }

  private func segment(
    _ start: Double, _ end: Double, sort: String = "sponsor", confidence: String = "high",
    origin: String? = nil
  ) -> [String: Any] {
    var made: [String: Any] = ["sort": sort, "start": start, "end": end, "confidence": confidence]
    if let origin { made["origin"] = origin }
    return made
  }

  // MARK: Which borders are exact

  func testAnExactEdgeIsABorderThatTheSecondDownloadMoved() {
    let claude = label([segment(100, 200), segment(300, 400)])
    let snapped = label([segment(101.48, 200), segment(300, 398.12)])
    XCTAssertEqual(EdgeMeasure.exactEdges(snapped: snapped, claude: claude), [101.48, 398.12])
  }

  func testLabelsThatNothingMovedHaveNoExactEdge() {
    let claude = label([segment(100, 200), segment(300, 400)])
    XCTAssertEqual(EdgeMeasure.exactEdges(snapped: claude, claude: claude), [])
  }

  func testAStretchOnlyTheSecondDownloadFoundIsExactOnBothBorders() {
    let claude = label([segment(100, 200)])
    let snapped = label([
      segment(100, 200), segment(500, 560.25, confidence: "medium", origin: "copy"),
    ])
    XCTAssertEqual(EdgeMeasure.exactEdges(snapped: snapped, claude: claude), [500, 560.25])
  }

  func testWithoutClaudesLabelsOnlyTheStretchesTheCopiesAddedAreExact() {
    let snapped = label([
      segment(100, 200), segment(500, 560, confidence: "medium", origin: "copy"),
    ])
    XCTAssertEqual(EdgeMeasure.exactEdges(snapped: snapped, claude: nil), [500, 560])
    XCTAssertEqual(
      EdgeMeasure.exactEdges(snapped: snapped, claude: Data("nonsense".utf8)), [500, 560])
  }

  func testOnlyMarkedAdsOfHighOrMediumConfidenceCount() {
    let claude = label([segment(100, 200)])
    let snapped = label([
      segment(110, 210, confidence: "low"), segment(300, 360, sort: "weather"),
      segment(400, 460, confidence: "medium", origin: "copy"),
      segment(500, 560, sort: "host_ask", confidence: "medium", origin: "copy"),
      segment(600, 560, confidence: "high", origin: "copy"),
    ])
    XCTAssertEqual(EdgeMeasure.exactEdges(snapped: snapped, claude: claude), [400, 460, 500, 560])
  }

  func testTwoEdgesWithinHalfASecondCountOnce() {
    let snapped = label([
      segment(100, 150.2, origin: "copy"), segment(150.4, 200, origin: "copy"),
    ])
    XCTAssertEqual(EdgeMeasure.exactEdges(snapped: snapped, claude: nil), [100, 150.2, 200])
  }

  func testNothingUsableGivesNoEdges() {
    XCTAssertEqual(EdgeMeasure.exactEdges(snapped: nil, claude: nil), [])
    XCTAssertEqual(EdgeMeasure.exactEdges(snapped: Data("[]".utf8), claude: nil), [])
    XCTAssertEqual(EdgeMeasure.exactEdges(snapped: Data("{\"segments\": 4}".utf8), claude: nil), [])
    XCTAssertEqual(
      EdgeMeasure.exactEdges(
        snapped: label([
          ["sort": "sponsor", "start": "x", "end": 4, "confidence": "high", "origin": "copy"]
        ]),
        claude: nil), [])
  }

  // MARK: How well the strongest change lines up

  private let peaks = [
    EdgePeak(time: 100.4, strength: 9), EdgePeak(time: 205, strength: 8),
    EdgePeak(time: 306.5, strength: 7),
  ]

  func testTheSharesCountEachReachAndLeaveOutEdgesNearTheEndsOfTheFile() {
    let episode = EdgeEpisode(
      id: "a", seconds: 1000, peaks: peaks, edges: [100, 200, 300, 400, 5, 998, 2])
    let result = EdgeMeasure.measure([episode])
    XCTAssertEqual(result.episodes, 1)
    XCTAssertEqual(result.leftOut, 2)
    XCTAssertEqual(result.edges.points, 5)
    // 100 is 0.4 s from its peak, 200 is 5 s from its peak, 300 is 6.5 s, and 400 and 5 have none.
    XCTAssertEqual(result.edges.hits, [1, 1, 2])
    XCTAssertEqual(result.edges.share(0), 0.2, accuracy: 1e-9)
    XCTAssertEqual(result.edges.share(2), 0.4, accuracy: 1e-9)
    XCTAssertEqual(result.random.points, 5)
  }

  func testAnEpisodeWithNoEdgeIsNotCounted() {
    let result = EdgeMeasure.measure([
      EdgeEpisode(id: "a", seconds: 1000, peaks: peaks, edges: []),
      EdgeEpisode(id: "b", seconds: 1000, peaks: peaks, edges: [100]),
    ])
    XCTAssertEqual(result.episodes, 1)
    XCTAssertEqual(result.edges.points, 1)
    XCTAssertEqual(result.random.points, 1)
  }

  func testWithNoEdgeAtAllThereIsNoVerdict() {
    let result = EdgeMeasure.measure([EdgeEpisode(id: "a", seconds: 1000, peaks: peaks, edges: [])])
    XCTAssertEqual(result.edges.points, 0)
    XCTAssertEqual(result.edges.share(0), 0)
    XCTAssertEqual(result.verdict, .undecided)
  }

  func testRandomPointsAreTheSameForTheSameSeedAndStayInsideTheWindows() {
    var first = EdgeRandom(seed: 7)
    var second = EdgeRandom(seed: 7)
    var other = EdgeRandom(seed: 8)
    let points = EdgeMeasure.randomPoints(50, seconds: 100, using: &first)
    XCTAssertEqual(points, EdgeMeasure.randomPoints(50, seconds: 100, using: &second))
    XCTAssertNotEqual(points, EdgeMeasure.randomPoints(50, seconds: 100, using: &other))
    XCTAssertEqual(points.count, 50)
    XCTAssertTrue(points.allSatisfy { EdgeSound.fits($0, seconds: 100) })
    XCTAssertGreaterThan(Set(points).count, 40)
  }

  func testTheMeasureIsTheSameEveryTimeAndDoesNotDependOnTheOrderOfTheEpisodes() {
    let one = EdgeEpisode(id: "a", seconds: 600, peaks: peaks, edges: [100, 200])
    let two = EdgeEpisode(id: "b", seconds: 900, peaks: peaks, edges: [300])
    XCTAssertEqual(EdgeMeasure.measure([one, two]), EdgeMeasure.measure([two, one]))
    XCTAssertEqual(EdgeMeasure.measure([one, two]), EdgeMeasure.measure([one, two]))
  }

  // MARK: The go rule

  private func shares(_ points: Int, _ within: Int) -> EdgeShares {
    EdgeShares(points: points, hits: [within, within, within])
  }

  func testGoNeedsSeventyPercentOfEdgesAndAtMostTenPercentOfRandomPoints() {
    XCTAssertEqual(EdgeMeasure.verdict(edges: shares(10, 7), random: shares(10, 1)), .go)
    XCTAssertEqual(EdgeMeasure.verdict(edges: shares(10, 6), random: shares(10, 1)), .noGo)
    XCTAssertEqual(EdgeMeasure.verdict(edges: shares(10, 7), random: shares(10, 2)), .noGo)
    XCTAssertEqual(EdgeMeasure.verdict(edges: shares(300, 210), random: shares(300, 30)), .go)
    XCTAssertEqual(EdgeMeasure.verdict(edges: shares(300, 209), random: shares(300, 30)), .noGo)
    XCTAssertEqual(EdgeMeasure.verdict(edges: shares(300, 210), random: shares(300, 31)), .noGo)
    XCTAssertEqual(EdgeMeasure.verdict(edges: shares(0, 0), random: shares(0, 0)), .undecided)
  }
}
