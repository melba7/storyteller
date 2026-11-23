import XCTest

@testable import PodcastAds

/// The two files of the Mac's teaching run that came after the first four: the meaning model
/// (`ad-meaning.json`) and the per-show settings (`show-settings.json`). They are installed and
/// loaded like the others: a damaged or too big file never replaces a good one, and a folder
/// without them loads as it always did.
final class TeachingFilesMeaningTests: XCTestCase {
  private var folder: URL!
  override func setUpWithError() throws {
    folder = try temporaryFolder().appendingPathComponent("taught", isDirectory: true)
  }
  override func tearDown() { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }

  /// One made meaning file for the whole test: `Made.file()` may list its keys in another order
  /// each time it is called, and a test compares the bytes on disk with what was installed.
  private let meaningData = Made.file()
  private let feedA = "https://show-a.test/feed"
  private let feedB = "https://show-b.test/rss"

  /// The settings as the Mac writes them: keys in order, one entry for show A (a feed the table
  /// knows) and one for a feed it does not.
  private func settingsData(askRepeatWords: String = "skip") -> Data {
    Data(
      """
      {"default": {"ask": 0.35, "finders": {"meaning": "ask"}, "joints": true, "steadyJoints": false},
       "shows": [{"feed": "\(feedA)", "finders": {"repeat-words": "\(askRepeatWords)"}},
                 {"feed": "https://unknown.test/feed", "joints": false}],
       "version": 1, "writtenAt": 1700000000}
      """.utf8)
  }

  private func disk(_ name: String) -> Data? {
    try? Data(contentsOf: folder.appendingPathComponent(name))
  }

  private func table() -> [String: String] { [FeedKey.key(feedA): "a-id", FeedKey.key(feedB): "b-id"] }

  // MARK: Nothing taught

  func testNothingTaughtGivesNoMeaningModelAndTheBuiltInSettings() {
    XCTAssertNil(TeachingFiles().meaning)
    XCTAssertEqual(TeachingFiles().tuning, ShowTuning())
    let empty = TeachingFiles.load(folder: folder)
    XCTAssertNil(empty.meaning)
    XCTAssertEqual(empty.tuning, ShowTuning())
  }

  // MARK: Install and load

  func testBothFilesAreInstalledAsTheyAreAndLoaded() throws {
    XCTAssertTrue(TeachingFiles.install(name: AdMeaningModel.fileName, data: meaningData, folder: folder))
    XCTAssertTrue(TeachingFiles.install(name: ShowTuning.fileName, data: settingsData(), folder: folder))
    XCTAssertEqual(disk(AdMeaningModel.fileName), meaningData)
    XCTAssertEqual(disk(ShowTuning.fileName), settingsData())

    let files = TeachingFiles.load(folder: folder, now: Date(), shows: table())
    XCTAssertEqual(files.meaning, AdMeaningModel(data: meaningData))
    XCTAssertEqual(files.meaning?.revision, 7)
    // The show is named by its feed in the file and by its id here; a show the table does not
    // know is left out, and the default block applies to every show.
    XCTAssertEqual(files.tuning.level(forFinder: "repeat-words", show: "a-id"), .skip)
    XCTAssertEqual(files.tuning.level(forFinder: "repeat-words", show: "b-id"), .ask)
    XCTAssertEqual(files.tuning.level(forFinder: "meaning", show: "b-id"), .ask)
    XCTAssertTrue(files.tuning.joints(show: "a-id"))
  }

  func testWithNoTableTheDefaultBlockStillApplies() {
    XCTAssertTrue(TeachingFiles.install(name: ShowTuning.fileName, data: settingsData(), folder: folder))
    let files = TeachingFiles.load(folder: folder, now: Date())
    XCTAssertEqual(files.tuning.level(forFinder: "meaning", show: "a-id"), .ask)
    XCTAssertEqual(files.tuning.level(forFinder: "repeat-words", show: "a-id"), .ask, "no entry for the show")
  }

  func testTheSixNamesAreTheOnesThePhoneInstalls() {
    let all: [(String, Data)] = [
      (AdWordModel.fileName, MacFixtures.modelData), (AdLibraryFile.fileName, MacFixtures.libraryData),
      (ShowHabits.fileName, MacFixtures.habitsData), (AdMeaningModel.fileName, meaningData),
      (ShowTuning.fileName, settingsData()),
    ]
    XCTAssertEqual(
      all.map(\.0),
      ["ad-model.json", "ad-library.json", "show-habits.json", "ad-meaning.json", "show-settings.json"])
    for (name, data) in all {
      XCTAssertTrue(TeachingFiles.install(name: name, data: data, folder: folder), name)
    }
    XCTAssertFalse(TeachingFiles.install(name: "ad-sounds.json", data: settingsData(), folder: folder))
    XCTAssertEqual(AdMeaningModel.maxBytes, TeachingFiles.maxBytes)
    XCTAssertEqual(ShowTuning.maxBytes, TeachingFiles.maxBytes)
  }

  func testSettingsWithNoShowsAreAFileOfTheMac() {
    // The Mac writes this when no show needs settings of its own.
    let plain = Data(#"{"version": 1, "writtenAt": 1, "default": {}, "shows": []}"#.utf8)
    XCTAssertTrue(TeachingFiles.install(name: ShowTuning.fileName, data: plain, folder: folder))
    XCTAssertEqual(TeachingFiles.load(folder: folder).tuning, ShowTuning())
  }

  // MARK: Refused files

  func testADamagedMeaningFileIsRefusedAndTheOldOneStays() {
    XCTAssertTrue(TeachingFiles.install(name: AdMeaningModel.fileName, data: meaningData, folder: folder))
    let damaged: [Data] = [
      Data("{ not json".utf8), Data(), Made.file { $0["version"] = 2 },
      Made.file { $0["language"] = "fr" }, Made.file { $0["dimension"] = 3 },
      Made.file { $0.removeValue(forKey: "probes") },
      Made.file(weights: [Float](repeating: 0, count: 20)),  // nothing learned
      MacFixtures.modelData,  // the word model is not the meaning model
      settingsData(),
    ]
    for data in damaged {
      XCTAssertFalse(TeachingFiles.install(name: AdMeaningModel.fileName, data: data, folder: folder))
    }
    XCTAssertEqual(disk(AdMeaningModel.fileName), meaningData)
    XCTAssertEqual(TeachingFiles.load(folder: folder).meaning, AdMeaningModel(data: meaningData))
  }

  func testADamagedSettingsFileIsRefusedAndTheOldOneStays() {
    XCTAssertTrue(TeachingFiles.install(name: ShowTuning.fileName, data: settingsData(), folder: folder))
    let damaged: [Data] = [
      Data("{ not json".utf8), Data(), Data("[1, 2]".utf8), Data(#"{"version": 1}"#.utf8),
      Data(#"{"version": 2, "shows": []}"#.utf8), Data(#"{"version": "1", "shows": []}"#.utf8),
      Data(#"{"version": 1, "shows": {"a": 1}}"#.utf8),
      meaningData,  // the meaning model is not the settings
      MacFixtures.libraryData,
    ]
    for data in damaged {
      XCTAssertFalse(TeachingFiles.install(name: ShowTuning.fileName, data: data, folder: folder))
    }
    XCTAssertEqual(disk(ShowTuning.fileName), settingsData())
  }

  func testATooBigFileIsRefusedAndTheOldOneStays() {
    XCTAssertTrue(TeachingFiles.install(name: AdMeaningModel.fileName, data: meaningData, folder: folder))
    XCTAssertTrue(TeachingFiles.install(name: ShowTuning.fileName, data: settingsData(), folder: folder))
    // Each is a good file with spaces after it, so only its size is wrong.
    let padding = Data(repeating: 32, count: TeachingFiles.maxBytes)
    var bigMeaning = Made.file { $0["trained"] = ["episodes": 9] }
    bigMeaning.append(padding)
    var bigSettings = settingsData(askRepeatWords: "off")
    bigSettings.append(padding)
    XCTAssertFalse(TeachingFiles.install(name: AdMeaningModel.fileName, data: bigMeaning, folder: folder))
    XCTAssertFalse(TeachingFiles.install(name: ShowTuning.fileName, data: bigSettings, folder: folder))
    XCTAssertEqual(disk(AdMeaningModel.fileName), meaningData)
    XCTAssertEqual(disk(ShowTuning.fileName), settingsData())
  }

  func testARefusedFileWritesNothingIntoAnEmptyFolder() {
    XCTAssertFalse(TeachingFiles.install(name: AdMeaningModel.fileName, data: Data("x".utf8), folder: folder))
    XCTAssertFalse(TeachingFiles.install(name: ShowTuning.fileName, data: Data("x".utf8), folder: folder))
    XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
  }

  // MARK: Loading

  func testBadFilesOnDiskGiveNoMeaningModelAndTheBuiltInSettings() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for name in [AdMeaningModel.fileName, ShowTuning.fileName] {
      try Data("garbage".utf8).write(to: folder.appendingPathComponent(name))
    }
    let files = TeachingFiles.load(folder: folder, now: Date(), shows: table())
    XCTAssertNil(files.meaning)
    XCTAssertEqual(files.tuning, ShowTuning())
  }

  func testAFileOnDiskOverTheLimitReadsAsNothing() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var big = meaningData
    big.append(Data(repeating: 32, count: TeachingFiles.maxBytes))
    try big.write(to: folder.appendingPathComponent(AdMeaningModel.fileName))
    var bigSettings = settingsData(askRepeatWords: "off")
    bigSettings.append(Data(repeating: 32, count: TeachingFiles.maxBytes))
    try bigSettings.write(to: folder.appendingPathComponent(ShowTuning.fileName))
    let files = TeachingFiles.load(folder: folder, now: Date(), shows: table())
    XCTAssertNil(files.meaning)
    XCTAssertEqual(files.tuning, ShowTuning())
  }

  func testAnOldInstallWithoutTheTwoFilesLoadsAsToday() {
    XCTAssertTrue(TeachingFiles.install(name: AdWordModel.fileName, data: MacFixtures.modelData, folder: folder))
    XCTAssertTrue(TeachingFiles.install(name: AdLibraryFile.fileName, data: MacFixtures.libraryData, folder: folder))
    XCTAssertTrue(TeachingFiles.install(name: ShowHabits.fileName, data: MacFixtures.habitsData, folder: folder))
    let files = TeachingFiles.load(folder: folder, now: Date(), shows: table())
    XCTAssertNotNil(files.model)
    XCTAssertEqual(files.seeds.ads.count, 2)
    XCTAssertFalse(files.habits.shows.isEmpty)
    XCTAssertNil(files.meaning)
    XCTAssertEqual(files.tuning, ShowTuning())
  }

  func testInstallingTheNewFilesChangesNothingAboutTheOldOnes() {
    XCTAssertTrue(TeachingFiles.install(name: AdWordModel.fileName, data: MacFixtures.modelData, folder: folder))
    let before = TeachingFiles.load(folder: folder, now: Date(timeIntervalSince1970: 0), shows: table())
    XCTAssertTrue(TeachingFiles.install(name: AdMeaningModel.fileName, data: meaningData, folder: folder))
    XCTAssertTrue(TeachingFiles.install(name: ShowTuning.fileName, data: settingsData(), folder: folder))
    let after = TeachingFiles.load(folder: folder, now: Date(timeIntervalSince1970: 0), shows: table())
    XCTAssertEqual(after.model, before.model)
    XCTAssertEqual(after.habits, before.habits)
    XCTAssertEqual(after.seeds.ads, before.seeds.ads)
  }
}
