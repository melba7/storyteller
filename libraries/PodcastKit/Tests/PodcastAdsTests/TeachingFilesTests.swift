import XCTest

@testable import PodcastAds

/// The folder of files the Mac's teaching run gives the phone.
final class TeachingFilesTests: XCTestCase {
  private var folder: URL!
  override func setUpWithError() throws {
    // A folder that does not exist yet: install makes it.
    folder = try temporaryFolder().appendingPathComponent("taught", isDirectory: true)
  }
  override func tearDown() { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }

  private func modelData(weight: Double = 1) -> Data {
    let json: [String: Any] = [
      "version": 1, "buckets": 2048, "classes": AdWordModel.classes,
      "weights": ["5": [0.0, weight, 0.0, 0.0, 0.0]],
    ]
    return try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
  }

  private func encode<T: Encodable>(_ value: T) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try! encoder.encode(value)
  }

  private func libraryData() -> Data {
    let text = (1...30).map { "word\($0)" }.joined(separator: " ")
    let entry = AdLibraryFile.Entry(
      show: "s", scope: "show", sort: "sponsor", who: "Acme", text: text, length: 40, seen: 3)
    return encode(AdLibraryFile(ads: [entry]))
  }

  private func habitsData() -> Data {
    var habits = ShowHabits()
    habits.shows = [.init(id: "s", episodes: 5, opensWithAd: 5, openingEnds: 40)]
    return encode(habits)
  }

  private func disk(_ name: String) -> Data? {
    try? Data(contentsOf: folder.appendingPathComponent(name))
  }

  func testNothingTaughtYet() {
    let files = TeachingFiles()
    XCTAssertNil(files.model)
    XCTAssertEqual(files.seeds.ads, [])
    XCTAssertEqual(files.habits, ShowHabits())
    XCTAssertNil(files.local.model)
    let empty = TeachingFiles.load(folder: folder)
    XCTAssertNil(empty.model)
    XCTAssertEqual(empty.seeds.ads, [])
    XCTAssertEqual(empty.habits.shows, [])
  }

  func testInstalledFilesAreLoaded() {
    XCTAssertTrue(TeachingFiles.install(name: AdWordModel.fileName, data: modelData(), folder: folder))
    XCTAssertTrue(TeachingFiles.install(name: AdLibraryFile.fileName, data: libraryData(), folder: folder))
    XCTAssertTrue(TeachingFiles.install(name: ShowHabits.fileName, data: habitsData(), folder: folder))
    let files = TeachingFiles.load(folder: folder)
    XCTAssertNotNil(files.model)
    XCTAssertNotNil(files.local.model)
    XCTAssertEqual(files.seeds.ads.count, 1)
    XCTAssertTrue(files.habits.usuallyOpensWithAd(show: "s"))
  }

  func testAWrongNameIsRefused() {
    XCTAssertFalse(TeachingFiles.install(name: "other.json", data: modelData(), folder: folder))
    XCTAssertFalse(TeachingFiles.install(name: "../ad-model.json", data: modelData(), folder: folder))
    XCTAssertNil(disk("other.json"))
  }

  func testATooLargeFileIsRefusedAndTheOldOneStays() {
    XCTAssertTrue(TeachingFiles.install(name: AdWordModel.fileName, data: modelData(), folder: folder))
    var big = modelData(weight: 2)
    big.append(Data(repeating: 32, count: TeachingFiles.maxBytes))
    XCTAssertFalse(TeachingFiles.install(name: AdWordModel.fileName, data: big, folder: folder))
    XCTAssertEqual(disk(AdWordModel.fileName), modelData())
  }

  func testADamagedFileIsRefusedAndTheOldOneStays() {
    XCTAssertTrue(TeachingFiles.install(name: AdWordModel.fileName, data: modelData(), folder: folder))
    XCTAssertTrue(TeachingFiles.install(name: AdLibraryFile.fileName, data: libraryData(), folder: folder))
    XCTAssertTrue(TeachingFiles.install(name: ShowHabits.fileName, data: habitsData(), folder: folder))
    let damaged = Data("{ not json".utf8)
    for name in [AdWordModel.fileName, AdLibraryFile.fileName, ShowHabits.fileName] {
      XCTAssertFalse(TeachingFiles.install(name: name, data: damaged, folder: folder), name)
    }
    let newer = try! JSONEncoder().encode(AdLibraryFile(version: 2, ads: []))
    XCTAssertFalse(TeachingFiles.install(name: AdLibraryFile.fileName, data: newer, folder: folder))
    XCTAssertEqual(disk(AdWordModel.fileName), modelData())
    XCTAssertEqual(disk(AdLibraryFile.fileName), libraryData())
    XCTAssertEqual(disk(ShowHabits.fileName), habitsData())
  }

  func testAModelWithNoWeightsIsRefused() {
    let json: [String: Any] = [
      "version": 1, "buckets": 2048, "classes": AdWordModel.classes, "weights": [String: Any](),
    ]
    let data = try! JSONSerialization.data(withJSONObject: json)
    XCTAssertFalse(TeachingFiles.install(name: AdWordModel.fileName, data: data, folder: folder))
  }

  func testLoadNeverThrowsOnBadFilesOnDisk() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for name in [AdWordModel.fileName, AdLibraryFile.fileName, ShowHabits.fileName] {
      try Data("garbage".utf8).write(to: folder.appendingPathComponent(name))
    }
    let files = TeachingFiles.load(folder: folder)
    XCTAssertNil(files.model)
    XCTAssertEqual(files.seeds.ads, [])
    XCTAssertEqual(files.habits.shows, [])
  }
}
