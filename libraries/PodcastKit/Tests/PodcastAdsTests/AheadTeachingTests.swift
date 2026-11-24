import XCTest

@testable import PodcastAds

/// How the phone takes `ahead-ads.json` in with the other files of the Mac, which of its own
/// episodes the marks name, and what the Mac's settings say about the finder.
final class AheadTeachingTests: XCTestCase {
  private var folder: URL!
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  override func setUpWithError() throws {
    folder = try temporaryFolder().appendingPathComponent("taught", isDirectory: true)
  }
  override func tearDown() { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }

  private func marks(marked: Double? = nil) -> Data {
    let at = marked ?? now.timeIntervalSince1970 - 3600
    return Data(
      #"{"version": 1, "writtenAt": 1, "episodes": [{"feed": "https://a.test/rss", "guid": "g1", "title": "One", "marked": \#(at), "ads": [{"kind": "ad", "confidence": "high", "start": 5, "end": 35, "startWords": "one two three four five six seven eight", "endWords": "nine ten eleven twelve thirteen fourteen fifteen sixteen"}]}]}"#
        .utf8)
  }

  // MARK: The file among the others

  func testTheFileIsKeptWithTheOtherFilesAndLoadedWithThem() throws {
    XCTAssertTrue(TeachingFiles.install(name: AheadFile.fileName, data: marks(), folder: folder))
    let files = TeachingFiles.load(folder: folder)
    XCTAssertEqual(files.ahead.episodes.count, 1)
    XCTAssertNotNil(files.ahead.entry(guid: "g1", feed: "", title: "", now: now))
    XCTAssertEqual(TeachingFiles().ahead, AheadFile())
    XCTAssertEqual(TeachingFiles.load(folder: try temporaryFolder()).ahead, AheadFile())
  }

  func testAFileThatIsNotTheMacsFileIsRefusedAndTheOldOneStays() throws {
    XCTAssertTrue(TeachingFiles.install(name: AheadFile.fileName, data: marks(), folder: folder))
    for bad in [
      Data("not json".utf8), Data(#"{"version": 2, "episodes": []}"#.utf8),
      Data(#"{"version": 1}"#.utf8), Data(#"{"version": 1, "episodes": {}}"#.utf8),
    ] {
      XCTAssertFalse(TeachingFiles.install(name: AheadFile.fileName, data: bad, folder: folder))
    }
    var big = marks()
    big.append(Data(repeating: 32, count: TeachingFiles.maxBytes))
    XCTAssertFalse(TeachingFiles.install(name: AheadFile.fileName, data: big, folder: folder))
    XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(AheadFile.fileName)), marks())
  }

  func testADamagedFileOnDiskIsNoFileAndTheOtherFilesStillLoad() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("{{".utf8).write(to: folder.appendingPathComponent(AheadFile.fileName))
    let files = TeachingFiles.load(folder: folder)
    XCTAssertEqual(files.ahead, AheadFile())
    XCTAssertEqual(files.tuning, ShowTuning())
  }

  // MARK: Which episode of the app is which entry

  func testTheTableOfEpisodesIsReadKeptAndReadBack() throws {
    let text = #"{"e1": {"feed": "https://a.test/rss", "guid": "g1", "title": "One"}, "e2": {"feed": "f", "guid": "", "title": "Two"}}"#
    let table = try XCTUnwrap(AheadEpisodes.parse(text))
    XCTAssertEqual(table["e1"], AheadEpisodes.Facts(feed: "https://a.test/rss", guid: "g1", title: "One"))
    XCTAssertEqual(table["e2"]?.guid, "")
    XCTAssertEqual(AheadEpisodes.load(from: folder), [:])
    try AheadEpisodes.save(table, to: folder)
    XCTAssertEqual(AheadEpisodes.load(from: folder), table)
  }

  func testAnEntryOfTheTableWithAWrongFieldIsLeftOutAndAWrongTextIsNil() throws {
    let text = #"{"e1": {"feed": "f", "guid": 3, "title": "One"}, "": {"feed": "f", "guid": "g", "title": "t"}, "e3": {"feed": "f", "guid": "g", "title": "t"}}"#
    XCTAssertEqual(try XCTUnwrap(AheadEpisodes.parse(text)).keys.sorted(), ["e3"])
    XCTAssertNil(AheadEpisodes.parse("[1]"))
    XCTAssertNil(AheadEpisodes.parse("nope"))
  }

  func testADamagedTableOnDiskIsEmpty() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("{{".utf8).write(to: folder.appendingPathComponent(AheadEpisodes.fileName))
    XCTAssertEqual(AheadEpisodes.load(from: folder), [:])
  }

  func testTheTableIsKeptWithinItsLimit() {
    var parts: [String] = []
    for number in 0..<(AheadEpisodes.most + 50) {
      parts.append(#""e\#(number)": {"feed": "f", "guid": "g\#(number)", "title": "t"}"#)
    }
    let table = AheadEpisodes.parse("{" + parts.joined(separator: ", ") + "}")
    XCTAssertEqual(table?.count, AheadEpisodes.most)
  }

  func testTheEntryOfAnEpisodeComesFromTheTableAndTheFile() throws {
    var files = TeachingFiles()
    files.ahead = AheadFile(data: marks())
    let table = ["e1": AheadEpisodes.Facts(feed: "a.test/rss", guid: "g1", title: "One")]
    XCTAssertNotNil(files.aheadEntry(episode: "e1", table: table, now: now))
    XCTAssertNil(files.aheadEntry(episode: "e2", table: table, now: now))
    XCTAssertNil(TeachingFiles().aheadEntry(episode: "e1", table: table, now: now))
    // Marked more than 14 days ago: nothing.
    files.ahead = AheadFile(data: marks(marked: now.timeIntervalSince1970 - 15 * 86_400))
    XCTAssertNil(files.aheadEntry(episode: "e1", table: table, now: now))
  }

  // MARK: The settings

  func testTheFinderHasAPlaceInTheSettingsAndSkipsByDefault() {
    XCTAssertEqual(ShowTuning.ahead, "ahead")
    XCTAssertTrue(ShowTuning.finderNames.contains("ahead"))
    XCTAssertEqual(ShowTuning().level(forFinder: "ahead", show: "any"), .skip)
    XCTAssertEqual(ShowTuning.currentVersion, 1)
    let ad = FoundAd(
      start: 10, end: 40, kind: .ad, advertiser: "", confidence: .sure, firstWords: "", source: "ahead")
    XCTAssertEqual(ShowTuning().apply(to: [ad], show: "any").skip, [ad])
  }

  func testTheMacCanSetTheFinderToAskOrOffForAShow() {
    let text = #"{"version": 1, "default": {"finders": {"ahead": "skip"}}, "shows": [{"feed": "a", "finders": {"ahead": "ask"}}, {"feed": "b", "finders": {"ahead": "off"}}]}"#
    let tuning = ShowTuning(text: text)
    XCTAssertEqual(tuning.level(forFinder: "ahead", show: "a"), .ask)
    XCTAssertEqual(tuning.level(forFinder: "ahead", show: "b"), .off)
    XCTAssertEqual(tuning.level(forFinder: "ahead", show: "c"), .skip)
  }

  func testTheGuardKnowsTheFinderByTheSameName() {
    var guardFile = FinderGuard(appBuild: "1")
    guardFile.begin(finder: ShowTuning.ahead, episode: "e1")
    guardFile.recover()
    XCTAssertEqual(guardFile.mode(finder: ShowTuning.ahead, show: "s", episode: "e1", now: now), .off)
    XCTAssertEqual(guardFile.mode(finder: ShowTuning.ahead, show: "s", episode: "e2", now: now), .skip)
  }
}
