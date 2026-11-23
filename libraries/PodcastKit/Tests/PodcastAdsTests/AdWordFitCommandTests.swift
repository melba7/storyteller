import XCTest

@testable import PodcastAds

/// The command `podcast-teach fit` as the tests can call it: files in, exit codes and plain messages out.
final class AdWordFitCommandTests: XCTestCase {
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

  func testTooManyBucketsAreRefusedWithExitTwoAndAPlainMessage() throws {
    let dir = folder()
    let input = dir.appendingPathComponent("many.txt").path
    let output = dir.appendingPathComponent("fit.json").path
    try "buckets 2147483647 classes 5\n0 1\n".write(toFile: input, atomically: true, encoding: .utf8)
    var errors: [String] = []
    XCTAssertEqual(AdWordFit.run([input, output], out: { _ in }, err: { errors.append($0) }), 2)
    XCTAssertEqual(errors.count, 1)
    XCTAssertTrue(errors[0].contains("16777216"), errors[0])
    XCTAssertFalse(FileManager.default.fileExists(atPath: output))
    // The largest allowed size is read.
    try "buckets 16777216 classes 5\n0 1\n".write(toFile: input, atomically: true, encoding: .utf8)
    if case .failure(let problem) = AdWordFit.parse(try Data(contentsOf: URL(fileURLWithPath: input))) {
      XCTFail(problem.message)
    }
  }

  private var fixture: String { AdWordFitFixture.text }
}
