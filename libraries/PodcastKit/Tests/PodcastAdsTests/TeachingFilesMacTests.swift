import XCTest

@testable import PodcastAds

/// The folder of the phone's teaching files, filled with the files exactly as the Mac writes them.
final class TeachingFilesMacTests: XCTestCase {
  private var folder: URL!
  override func setUpWithError() throws {
    folder = try temporaryFolder().appendingPathComponent("taught", isDirectory: true)
  }
  override func tearDown() { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }

  private func installAll() {
    XCTAssertTrue(TeachingFiles.install(name: AdWordModel.fileName, data: MacFixtures.modelData, folder: folder))
    XCTAssertTrue(TeachingFiles.install(name: AdLibraryFile.fileName, data: MacFixtures.libraryData, folder: folder))
    XCTAssertTrue(TeachingFiles.install(name: ShowHabits.fileName, data: MacFixtures.habitsData, folder: folder))
  }

  func testTheMacsFilesAreInstalledAsTheyAre() {
    installAll()
    for (name, data) in [
      (AdWordModel.fileName, MacFixtures.modelData), (AdLibraryFile.fileName, MacFixtures.libraryData),
      (ShowHabits.fileName, MacFixtures.habitsData),
    ] {
      XCTAssertEqual(try? Data(contentsOf: folder.appendingPathComponent(name)), data, name)
    }
  }

  func testTheFilesReadThroughTheTableOfShows() {
    installAll()
    let table = [MacFixtures.showA: "a-id", MacFixtures.showB: "b-id"]
    let files = TeachingFiles.load(folder: folder, now: Date(), shows: table)
    XCTAssertNotNil(files.model)
    XCTAssertEqual(files.seeds.ads.count, 2)
    XCTAssertEqual(Set(files.seeds.ads.map(\.showId)), ["a-id", "b-id"])
    XCTAssertEqual(files.habits.shows.map(\.id), ["a-id", "b-id"])
    XCTAssertTrue(files.habits.usuallyOpensWithAd(show: "a-id"))
    XCTAssertTrue(files.habits.startsClean(show: "b-id") == false, "one episode says too little")
  }

  func testWithNoTableOnlyTheAdsOfEveryShowAreKnown() {
    installAll()
    let files = TeachingFiles.load(folder: folder, now: Date())
    XCTAssertEqual(files.seeds.ads.map(\.scope), ["all"])
    XCTAssertEqual(files.habits.shows, [])
    XCTAssertNotNil(files.model, "the model needs no table")
  }

  func testWhatIsNotTheMacsShapeIsRefused() {
    let version2 = Data(#"{"version": 2, "ads": [], "shows": []}"#.utf8)
    let noList = Data(#"{"version": 1}"#.utf8)
    let wrongList = Data(#"{"version": 1, "ads": {"a": 1}, "shows": "none"}"#.utf8)
    let notObject = Data("[1, 2]".utf8)
    let stringVersion = Data(#"{"version": "1", "ads": [], "shows": []}"#.utf8)
    for name in [AdLibraryFile.fileName, ShowHabits.fileName] {
      for data in [version2, noList, wrongList, notObject, stringVersion] {
        XCTAssertFalse(TeachingFiles.install(name: name, data: data, folder: folder), name)
      }
    }
    // A library is not a habits file and the other way round.
    XCTAssertFalse(
      TeachingFiles.install(name: ShowHabits.fileName, data: MacFixtures.libraryData, folder: folder))
    XCTAssertFalse(
      TeachingFiles.install(name: AdLibraryFile.fileName, data: MacFixtures.habitsData, folder: folder))
    XCTAssertFalse(TeachingFiles.install(name: AdWordModel.fileName, data: MacFixtures.libraryData, folder: folder))
    XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "nothing was written")
  }

  func testAnEmptyListIsAFileOfTheMac() {
    // The Mac writes these when nothing is marked yet.
    XCTAssertTrue(
      TeachingFiles.install(
        name: AdLibraryFile.fileName, data: Data(#"{"version": 1, "writtenAt": 1, "ads": []}"#.utf8),
        folder: folder))
  }

  func testTheModelsNumbersAreReadWhateverIsMissing() throws {
    let info = try XCTUnwrap(TeachingFiles.modelInfo(data: MacFixtures.modelData))
    XCTAssertEqual(info.writtenAt, 1_700_000_000_000)
    XCTAssertEqual(info.episodes, 12)
    XCTAssertEqual(info.precision ?? 0, 0.8889, accuracy: 1e-9)
    XCTAssertEqual(info.recall ?? 0, 0.8, accuracy: 1e-9)

    let part = Data(#"{"trained": {"episodes": 4, "heldOut": {"anyAd": {"precision": null, "recall": 0.5}}}}"#.utf8)
    let some = try XCTUnwrap(TeachingFiles.modelInfo(data: part))
    XCTAssertNil(some.writtenAt)
    XCTAssertEqual(some.episodes, 4)
    XCTAssertNil(some.precision)
    XCTAssertEqual(some.recall, 0.5)

    let bare = try XCTUnwrap(TeachingFiles.modelInfo(data: Data("{}".utf8)))
    XCTAssertEqual(bare, TeachingFiles.ModelInfo())
    let wrong = try XCTUnwrap(TeachingFiles.modelInfo(data: Data(#"{"trained": {"episodes": "x", "heldOut": 3}}"#.utf8)))
    XCTAssertEqual(wrong, TeachingFiles.ModelInfo())
    XCTAssertNil(TeachingFiles.modelInfo(data: Data("nope".utf8)))
    XCTAssertNil(TeachingFiles.modelInfo(data: Data("[]".utf8)))
  }

  func testTheInstalledModelsNumbers() {
    XCTAssertNil(TeachingFiles.modelInfo(in: folder))
    installAll()
    XCTAssertEqual(TeachingFiles.modelInfo(in: folder)?.episodes, 12)
  }
}
