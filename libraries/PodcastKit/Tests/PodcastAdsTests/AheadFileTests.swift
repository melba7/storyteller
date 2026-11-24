import XCTest

@testable import PodcastAds

/// `ahead-ads.json`: the Mac's marks for the next episodes, how the phone reads the file, and how
/// it finds the entry of one of its own episodes.
final class AheadFileTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private let day = 86_400.0

  private func ad(_ kind: String = "ad", _ confidence: String = "high") -> String {
    #"{"kind": "\#(kind)", "confidence": "\#(confidence)", "start": 50, "end": 80, "startWords": "one two three four five six seven eight", "endWords": "nine ten eleven twelve thirteen fourteen fifteen sixteen"}"#
  }

  private func episode(
    guid: String = "g1", title: String = "Episode One", feed: String = "https://Show.test/rss/",
    marked: Double, ads: [String]? = nil
  ) -> String {
    #"{"feed": "\#(feed)", "guid": "\#(guid)", "title": "\#(title)", "marked": \#(marked), "ads": [\#((ads ?? [ad()]).joined(separator: ", "))]}"#
  }

  private func file(_ episodes: [String], version: Int = 1) -> Data {
    Data(
      #"{"version": \#(version), "writtenAt": 1799990000, "episodes": [\#(episodes.joined(separator: ", "))]}"#
        .utf8)
  }

  private var fresh: Double { now.timeIntervalSince1970 - 2 * day }

  // MARK: Reading

  func testAGoodFileReadsEveryFieldOfEveryAd() throws {
    let read = AheadFile(data: file([episode(marked: fresh)]))
    XCTAssertEqual(read.episodes.count, 1)
    let entry = try XCTUnwrap(read.episodes.first)
    XCTAssertEqual(entry.guid, "g1")
    XCTAssertEqual(entry.feed, "https://Show.test/rss/")
    XCTAssertEqual(entry.title, "Episode One")
    XCTAssertEqual(entry.marked, fresh)
    let mark = try XCTUnwrap(entry.ads.first)
    XCTAssertEqual(mark.kind, .ad)
    XCTAssertEqual(mark.confidence, .high)
    XCTAssertEqual(mark.start, 50)
    XCTAssertEqual(mark.end, 80)
    XCTAssertEqual(mark.startWords, "one two three four five six seven eight")
    XCTAssertEqual(AheadFile.fileName, "ahead-ads.json")
  }

  func testTheThreeKindsOfTheMacAreTheThreeKindsOfThePhone() {
    let read = AheadFile(
      data: file([episode(marked: fresh, ads: [ad("ad"), ad("promo"), ad("ownPlug")])]))
    XCTAssertEqual(read.episodes.first?.ads.map(\.kind), [.ad, .promo, .ownPlug])
  }

  func testAnAdOfAnotherKindOrWithAWrongFieldIsLeftOutAndTheRestStays() {
    let broken = #"{"kind": "ad", "confidence": "high", "start": "soon", "end": 80, "startWords": "a", "endWords": "b"}"#
    let read = AheadFile(
      data: file([
        episode(marked: fresh, ads: [ad("credits"), broken, ad("promo", "low"), ad("ad", "certain")])
      ]))
    XCTAssertEqual(read.episodes.first?.ads.count, 1)
    XCTAssertEqual(read.episodes.first?.ads.first?.kind, .promo)
    XCTAssertEqual(read.episodes.first?.ads.first?.confidence, .low)
  }

  func testAnEpisodeWithAWrongFieldIsLeftOutAndTheRestStays() {
    let broken = #"{"feed": 3, "guid": "g2", "title": "x", "marked": 1, "ads": []}"#
    let read = AheadFile(data: file([broken, episode(guid: "g3", marked: fresh)]))
    XCTAssertEqual(read.episodes.map(\.guid), ["g3"])
  }

  func testADamagedFileReadsAsNoFile() {
    XCTAssertEqual(AheadFile(data: Data("not json".utf8)), AheadFile())
    XCTAssertEqual(AheadFile(data: Data(#"{"version": 1, "episodes": "no"}"#.utf8)), AheadFile())
    XCTAssertEqual(AheadFile(data: Data(#"[1, 2]"#.utf8)), AheadFile())
    XCTAssertEqual(AheadFile(data: Data()), AheadFile())
    XCTAssertEqual(AheadFile(), AheadFile(episodes: []))
  }

  func testAFileOfAnotherVersionReadsAsNoFile() {
    XCTAssertEqual(AheadFile(data: file([episode(marked: fresh)], version: 2)), AheadFile())
    XCTAssertEqual(AheadFile(data: Data(#"{"episodes": []}"#.utf8)), AheadFile())
  }

  func testAFileOverTheSharedLimitReadsAsNoFile() {
    var big = file([episode(marked: fresh)])
    big.append(Data(repeating: 32, count: TeachingFiles.maxBytes))
    XCTAssertEqual(AheadFile.maxBytes, TeachingFiles.maxBytes)
    XCTAssertEqual(AheadFile(data: big), AheadFile())
  }

  func testAFileOnDiskIsReadAndAMissingOneIsNoFile() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent(AheadFile.fileName)
    XCTAssertEqual(AheadFile.load(from: url), AheadFile())
    try file([episode(marked: fresh)]).write(to: url)
    XCTAssertEqual(AheadFile.load(from: url).episodes.count, 1)
  }

  func testTheTextTheFileIsWrittenInReadsBackTheSame() throws {
    let entry = AheadEntry(
      feed: "f", guid: "g", title: "t", marked: 5,
      ads: [
        AheadMark(
          kind: .ownPlug, confidence: .medium, start: 1, end: 31, startWords: "a b", endWords: "c d")
      ])
    let made = AheadFile(writtenAt: 9, episodes: [entry])
    XCTAssertEqual(AheadFile(data: try XCTUnwrap(made.encoded())), made)
  }

  // MARK: Finding the entry of an episode

  func testTheEpisodeIsFoundByItsGuid() {
    let read = AheadFile(
      data: file([episode(guid: "g1", title: "A", marked: fresh), episode(guid: "g2", title: "B", marked: fresh)]))
    XCTAssertEqual(read.entry(guid: "g2", feed: "other", title: "other", now: now)?.title, "B")
    XCTAssertNil(read.entry(guid: "g9", feed: "https://show.test/rss", title: "A", now: now))
  }

  func testWithNoGuidOnTheEntryTheFeedAndTheTitleSayWhichEpisodeItIs() {
    let read = AheadFile(
      data: file([
        episode(guid: "", title: "Episode  ONE!", feed: "https://Show.test/rss/", marked: fresh)
      ]))
    // The feed key (no scheme, no www., no closing slash) and the title with case, punctuation and
    // spaces taken out.
    XCTAssertNotNil(
      read.entry(guid: "x", feed: "http://www.show.test/rss", title: "episode one", now: now))
    XCTAssertNil(read.entry(guid: "x", feed: "http://www.show.test/rss", title: "episode two", now: now))
    XCTAssertNil(read.entry(guid: "x", feed: "http://www.other.test/rss", title: "episode one", now: now))
  }

  func testWithNoGuidOnThePhonesEpisodeTheFeedAndTheTitleAreUsedToo() {
    let read = AheadFile(data: file([episode(guid: "g1", title: "Episode One", marked: fresh)]))
    XCTAssertNotNil(read.entry(guid: "", feed: "show.test/rss", title: "Episode One", now: now))
  }

  func testAnEntryWithAGuidIsNeverMatchedByItsTitleWhenTheGuidsDiffer() {
    let read = AheadFile(data: file([episode(guid: "g1", title: "Episode One", marked: fresh)]))
    XCTAssertNil(read.entry(guid: "g2", feed: "show.test/rss", title: "Episode One", now: now))
  }

  func testAnEmptyTitleNeverMatchesByTitle() {
    let read = AheadFile(data: file([episode(guid: "", title: "", marked: fresh)]))
    XCTAssertNil(read.entry(guid: "", feed: "show.test/rss", title: "", now: now))
  }

  // MARK: Stale entries

  func testAnEntryMarkedMoreThanFourteenDaysAgoIsIgnored() {
    let read = AheadFile(
      data: file([
        episode(guid: "old", marked: now.timeIntervalSince1970 - 14 * day - 60),
        episode(guid: "edge", marked: now.timeIntervalSince1970 - 14 * day + 60),
      ]))
    XCTAssertEqual(AheadFile.maxAgeDays, 14)
    XCTAssertNil(read.entry(guid: "old", feed: "f", title: "t", now: now))
    XCTAssertNotNil(read.entry(guid: "edge", feed: "f", title: "t", now: now))
  }

  func testAnEntryWithNoAdsIsNoEntry() {
    let read = AheadFile(data: file([episode(marked: fresh, ads: [])]))
    XCTAssertNil(read.entry(guid: "g1", feed: "f", title: "t", now: now))
  }

  func testOfTwoEntriesOfOneEpisodeTheNewerMarkingIsTaken() {
    let read = AheadFile(
      data: file([
        episode(title: "Old", marked: now.timeIntervalSince1970 - 5 * day),
        episode(title: "New", marked: now.timeIntervalSince1970 - 1 * day),
      ]))
    XCTAssertEqual(read.entry(guid: "g1", feed: "f", title: "t", now: now)?.title, "New")
  }
}
