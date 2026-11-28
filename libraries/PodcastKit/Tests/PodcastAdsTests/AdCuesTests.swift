import XCTest

@testable import PodcastAds

/// `ad-cues.json`: reading it, matching a line's first words and keeping it with the other files.
final class AdCuesTests: XCTestCase {
  static let text = """
    {"version": 1, "writtenAt": 1, "episodes": 12,
     "starts": ["now a word", "this one is brought to"], "returns": ["and we are"],
     "shows": [{"feed": "https://one.test/rss", "starts": ["quick message from"], "returns": ["so anyway then"]},
               {"feed": "https://other.test/rss", "starts": ["other show start"], "returns": []}],
     "common": ["about", "with", "that"], "usual": ["today", "really"]}
    """

  private func cues(_ text: String = text, known: [String] = ["https://one.test/rss"]) -> AdCues {
    AdCues(data: Data(text.utf8), showOf: { known.contains($0) ? $0 : nil })
  }

  func testTheFileIsRead() {
    let read = cues()
    XCTAssertFalse(read.isEmpty)
    XCTAssertEqual(read.episodes, 12)
    XCTAssertEqual(
      [read.generalStarts, read.generalReturns, read.showStarts, read.showReturns, read.showCount],
      [2, 1, 1, 1, 1], "the show the reader does not know is left out")
    XCTAssertEqual([read.commonWords, read.usualWords], [3, 2])
    XCTAssertEqual(AdCues.fileName, "ad-cues.json")
  }

  func testNothingIsMatchedByDefault() {
    let none = AdCues()
    XCTAssertTrue(none.isEmpty)
    XCTAssertFalse(none.opens(["now", "a", "word"], show: "s"))
    XCTAssertFalse(none.returns(["and", "we", "are"], show: "s"))
  }

  func testALineMatchesByItsFirstThreeToSixWords() {
    let read = cues()
    XCTAssertTrue(read.opens(["now", "a", "word", "from", "x"], show: "s"), "the shortest prefix of three")
    XCTAssertTrue(read.opens(["this", "one", "is", "brought", "to", "you"], show: "s"), "a cue of five")
    XCTAssertFalse(read.opens(["this", "one", "is", "brought"], show: "s"), "four words are too few for a cue of five")
    XCTAssertFalse(read.opens(["well", "now", "a", "word"], show: "s"), "a cue is the start of the line")
    XCTAssertFalse(read.opens(["now", "a"], show: "s"))
    XCTAssertTrue(read.returns(["and", "we", "are", "back"], show: "s"))
    XCTAssertFalse(read.returns(["now", "a", "word"], show: "s"), "starts and returns are two lists")
  }

  func testAShowsOwnCuesCountOnlyOnThatShow() {
    let read = cues()
    let words = ["quick", "message", "from", "us"]
    XCTAssertTrue(read.opens(words, show: "https://one.test/rss"))
    XCTAssertFalse(read.opens(words, show: "https://other.test/rss"))
    XCTAssertTrue(read.returns(["so", "anyway", "then", "i"], show: "https://one.test/rss"))
    XCTAssertFalse(read.returns(["so", "anyway", "then", "i"], show: "x"))
  }

  func testContentAndRareWords() {
    let read = cues()
    XCTAssertTrue(read.isContent("tomato"))
    XCTAssertFalse(read.isContent("the"), "under four letters")
    XCTAssertFalse(read.isContent("about"), "common")
    XCTAssertTrue(read.isContent("today"))
    XCTAssertFalse(read.isRare("today"), "usual")
    XCTAssertTrue(read.isRare("tomato"))
    XCTAssertFalse(read.isRare("about"))
  }

  func testADamagedOrOtherFileReadsAsEmpty() {
    XCTAssertTrue(cues("not json").isEmpty)
    XCTAssertTrue(cues(Self.text.replacingOccurrences(of: "\"version\": 1", with: "\"version\": 2")).isEmpty)
    XCTAssertTrue(cues("[1, 2]").isEmpty)
    XCTAssertTrue(AdCues(data: Data(count: TeachingFiles.maxBytes + 1)).isEmpty)
    let big = Self.text + String(repeating: " ", count: TeachingFiles.maxBytes)
    XCTAssertTrue(AdCues(data: Data(big.utf8)).isEmpty)
  }

  func testAnEntryOfTheWrongShapeIsSkipped() {
    let read = cues(
      """
      {"version": 1, "starts": ["now a word", 5, null, ""], "returns": "oops",
       "shows": [7, {"feed": 3, "starts": ["a b c"]}, {"feed": "https://one.test/rss", "starts": ["x y z", {}]}],
       "common": ["about", false], "usual": {}}
      """)
    XCTAssertEqual(read.generalStarts, 1)
    XCTAssertEqual(read.generalReturns, 0)
    XCTAssertEqual(read.showStarts, 1)
    XCTAssertEqual(read.commonWords, 1)
    XCTAssertEqual(read.usualWords, 0)
  }

  func testTheShapeIsVersionOneWithTheLists() {
    XCTAssertTrue(AdCues.isShape(Data(Self.text.utf8)))
    XCTAssertFalse(AdCues.isShape(Data("nope".utf8)))
    XCTAssertFalse(AdCues.isShape(Data(#"{"version": 2, "starts": [], "returns": [], "shows": [], "common": [], "usual": []}"#.utf8)))
    XCTAssertFalse(AdCues.isShape(Data(#"{"version": 1, "starts": [], "returns": [], "shows": {}, "common": [], "usual": []}"#.utf8)))
    XCTAssertFalse(AdCues.isShape(Data(#"{"version": 1, "starts": []}"#.utf8)))
  }

  // MARK: The playbook's phrases

  private let withPhrases = """
    {"version": 1, "starts": [], "returns": [],
     "shows": [{"feed": "https://one.test/rss", "starts": [], "returns": [],
                "phrases": ["a word from", "After the  Break!", "single", "", 4, null]},
               {"feed": "https://other.test/rss", "phrases": ["other show phrase"]},
               {"feed": "https://third.test/rss", "starts": ["x y z"], "phrases": "oops"}],
     "common": [], "usual": []}
    """

  func testAShowsPhrasesAreReadAndAFileOfOnlyPhrasesIsNotEmpty() {
    let known = ["https://one.test/rss", "https://other.test/rss", "https://third.test/rss"]
    let read = cues(withPhrases, known: known)
    XCTAssertFalse(read.isEmpty)
    XCTAssertEqual(read.showPhrases, 3, "two of the first show (one word is too few) and one of the second")
    XCTAssertEqual(read.phraseShows, 2)
    XCTAssertEqual(read.showStarts, 1)
    XCTAssertTrue(AdCues.isShape(Data(withPhrases.utf8)))
    XCTAssertEqual(cues().showPhrases, 0, "a file without phrases has none")
    XCTAssertEqual(cues().phraseShows, 0)
  }

  func testALineMatchesAPhraseOfItsShowAsWholeWordsAnywhereInIt() {
    let read = cues(withPhrases, known: ["https://one.test/rss", "https://other.test/rss"])
    let one = "https://one.test/rss"
    XCTAssertTrue(read.playbookOpens(["and", "now", "a", "word", "from", "them"], show: one), "in the middle")
    XCTAssertTrue(read.playbookOpens(["a", "word", "from"], show: one), "the whole line")
    XCTAssertTrue(read.playbookOpens(AdWordModel.tokens("More after the break."), show: one), "re-made as words")
    XCTAssertFalse(read.playbookOpens(["a", "wordy", "from"], show: one), "whole words only")
    XCTAssertFalse(read.playbookOpens(["extra", "word", "from"], show: one))
    XCTAssertFalse(read.playbookOpens(["single"], show: one), "a phrase of one word is not kept")
    XCTAssertFalse(read.playbookOpens([], show: one))
    XCTAssertFalse(read.playbookOpens(["a", "word", "from"], show: "https://other.test/rss"), "another show's phrase")
    XCTAssertTrue(read.playbookOpens(["other", "show", "phrase"], show: "https://other.test/rss"))
    XCTAssertFalse(read.playbookOpens(["a", "word", "from"], show: "nobody"))
    XCTAssertFalse(read.opens(["a", "word", "from"], show: one), "a phrase is not a start cue")
    XCTAssertFalse(AdCues().playbookOpens(["a", "word", "from"], show: one))
  }

  // MARK: Among the other files

  func testTheFileIsKeptAndLoadedWithTheOtherFiles() throws {
    let folder = try temporaryFolder().appendingPathComponent("taught", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
    XCTAssertTrue(TeachingFiles().cues.isEmpty)
    XCTAssertTrue(TeachingFiles.load(folder: folder).cues.isEmpty)
    XCTAssertTrue(TeachingFiles.install(name: AdCues.fileName, data: Data(Self.text.utf8), folder: folder))
    XCTAssertFalse(TeachingFiles.install(name: AdCues.fileName, data: Data("bad".utf8), folder: folder))
    XCTAssertFalse(
      TeachingFiles.install(name: AdCues.fileName, data: Data(count: TeachingFiles.maxBytes + 1), folder: folder))
    let files = TeachingFiles.load(folder: folder)
    XCTAssertEqual(files.cues.generalStarts, 2)
    XCTAssertEqual(files.cues.showCount, 0, "no table of shows, so no feed is known")
  }
}
