import XCTest

@testable import PodcastAds

/// What the phone says about the files the Mac taught it (`getTeachingState()`).
final class TeachingStateTests: XCTestCase {
  private var folder: URL!
  override func setUpWithError() throws { folder = try temporaryFolder() }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  /// A number of parsed JSON: a whole one comes as Int on Linux.
  private func num(_ value: Any?) -> Double? {
    if let whole = value as? Int { return Double(whole) }
    return value as? Double
  }

  private func parse(_ text: String) throws -> [String: Any] {
    try XCTUnwrap((try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any])
  }

  func testNothingInstalledSaysSoInTheContractsShape() throws {
    let json = try parse(TeachingState().json(model: nil, library: 0, habits: 0, sounds: 0))
    XCTAssertEqual(Set(json.keys), ["files", "model", "library", "habits", "sounds"])
    XCTAssertEqual((json["files"] as? [String: Any])?.count, 0)
    XCTAssertTrue(json["model"] is NSNull)
    XCTAssertEqual(json["library"] as? Int, 0)
    XCTAssertEqual(json["habits"] as? Int, 0)
    XCTAssertEqual(json["sounds"] as? Int, 0)
  }

  func testFilesWithTheirShaAndTimeAndTheModelsNumbers() throws {
    var state = TeachingState()
    state.record(name: "ad-model.json", sha256: "ab12", at: Date(timeIntervalSince1970: 1_700_000_100))
    state.record(name: "ad-sounds.json", sha256: "cd34", at: Date(timeIntervalSince1970: 1_700_000_200))
    let model = TeachingFiles.modelInfo(data: MacFixtures.modelData)
    let json = try parse(state.json(model: model, library: 5, habits: 3, sounds: 7))
    let files = try XCTUnwrap(json["files"] as? [String: [String: Any]])
    XCTAssertEqual(files["ad-model.json"]?["sha256"] as? String, "ab12")
    XCTAssertEqual(num(files["ad-model.json"]?["installedAt"]), 1_700_000_100_000)
    XCTAssertEqual(files["ad-sounds.json"]?["sha256"] as? String, "cd34")
    let numbers = try XCTUnwrap(json["model"] as? [String: Any])
    XCTAssertEqual(Set(numbers.keys), ["writtenAt", "episodes", "precision", "recall"])
    XCTAssertEqual(num(numbers["writtenAt"]), 1_700_000_000_000)
    XCTAssertEqual(numbers["episodes"] as? Int, 12)
    XCTAssertEqual(num(numbers["recall"]), 0.8)
    XCTAssertEqual(json["library"] as? Int, 5)
    XCTAssertEqual(json["habits"] as? Int, 3)
    XCTAssertEqual(json["sounds"] as? Int, 7)
  }

  func testAModelWithMissingNumbersGivesNulls() throws {
    let info = TeachingFiles.ModelInfo(writtenAt: nil, episodes: 4, precision: nil, recall: 0.5)
    let json = try parse(TeachingState().json(model: info, library: 0, habits: 0, sounds: 0))
    let numbers = try XCTUnwrap(json["model"] as? [String: Any])
    XCTAssertTrue(numbers["writtenAt"] is NSNull)
    XCTAssertTrue(numbers["precision"] is NSNull)
    XCTAssertEqual(numbers["episodes"] as? Int, 4)
  }

  func testInstallingAgainReplacesTheRecord() {
    var state = TeachingState()
    state.record(name: "ad-model.json", sha256: "one", at: Date(timeIntervalSince1970: 10))
    state.record(name: "ad-model.json", sha256: "two", at: Date(timeIntervalSince1970: 20))
    XCTAssertEqual(state.files["ad-model.json"], TeachingState.Installed(sha256: "two", installedAt: 20_000))
    XCTAssertEqual(state.files.count, 1)
  }

  func testTheStateIsKeptInTheFolderAndComesBack() throws {
    XCTAssertEqual(TeachingState.load(from: folder), TeachingState())
    var state = TeachingState()
    state.record(name: "ad-library.json", sha256: "ee", at: Date(timeIntervalSince1970: 5))
    try state.save(to: folder.appendingPathComponent("made-now"))
    XCTAssertEqual(TeachingState.load(from: folder.appendingPathComponent("made-now")), state)
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: folder.appendingPathComponent("made-now/state.json").path))
  }

  func testADamagedStateFileIsAnEmptyState() throws {
    try Data("{ nope".utf8).write(to: folder.appendingPathComponent("state.json"))
    XCTAssertEqual(TeachingState.load(from: folder), TeachingState())
  }
}
