import XCTest

@testable import PodcastAds

/// The steps of a stream's head scan, and the jump a remembered ad asks for.
final class HeadStepsTests: XCTestCase {
  /// The targets of every step until the scan is over, with `jumps` asked after the step in
  /// the same position (`reached` is the step's own target).
  private func run(_ steps: HeadSteps = HeadSteps(), jumps: [Int: Double] = [:]) -> [Double] {
    var steps = steps
    var targets: [Double] = []
    while let target = steps.target {
      targets.append(target)
      if let jump = jumps[targets.count - 1] { steps.jump(to: jump, reached: target) }
      steps.advance()
    }
    return targets
  }

  func testWithNoJumpTheStepsAreTheHeadRulesSteps() {
    XCTAssertEqual(run(), [15, 30, 60, 90, 120, 150, 180])
    XCTAssertEqual(run(), AdHeadRules.steps)
  }

  func testAJumpMakesTheNextStepEndThereAndTheStepsGoOnPastIt() {
    XCTAssertEqual(run(jumps: [0: 43]), [15, 43, 60, 90, 120, 150, 180])
    XCTAssertEqual(run(jumps: [0: 26]), [15, 26, 30, 60, 90, 120, 150, 180])
  }

  func testAJumpPastTheLastStepEndsTheScanThere() {
    XCTAssertEqual(run(jumps: [0: 400]), [15, 180])
    XCTAssertEqual(run(jumps: [1: 175]), [15, 30, 175, 180])
  }

  func testAJumpThatAddsNothingIsIgnored() {
    XCTAssertEqual(run(jumps: [1: 30.5]), AdHeadRules.steps)
    XCTAssertEqual(run(jumps: [1: 10]), AdHeadRules.steps)
  }

  func testTheFurthestOfTwoJumpsWinsAndEachJumpIsUsedOnce() {
    var steps = HeadSteps()
    steps.jump(to: 43, reached: 15)
    steps.jump(to: 70, reached: 15)
    steps.jump(to: 40, reached: 15)
    steps.advance()
    XCTAssertEqual(steps.target, 70)
    steps.advance()
    XCTAssertEqual(steps.target, 90)
  }

  func testStepsOfAShortHeadCanBeGiven() {
    XCTAssertEqual(run(HeadSteps(steps: [15, 30, 60])), [15, 30, 60])
    XCTAssertEqual(run(HeadSteps(steps: [15, 30, 60]), jumps: [0: 50]), [15, 50, 60])
    XCTAssertEqual(run(HeadSteps(steps: [])), [])
  }

  func testAdvancingPastTheEndStaysAtTheEnd() {
    var steps = HeadSteps(steps: [15])
    steps.advance()
    steps.advance()
    XCTAssertNil(steps.target)
  }
}
