import XCTest

@testable import PodcastAds

/// The phone reads the text the Mac's teach_settings.py writes. `macText` is the file that script
/// wrote (through `write_json`, keys in order) for a made scorecard with three shows and notes: the
/// "repeat-words" row was bad over all shows, the joints were bad on show C, "own-sound" was bad on
/// show A, the notes had the meaning model undone twice on show B, and steady files found more over
/// all shows but not on show B. Apple's what-if row passed the bar on show C only, so Apple's model
/// may skip there and asks everywhere else.
final class ShowTuningMacTests: XCTestCase {
  static let macText = """
    {
     "default": {
      "ask": 0.35,
      "finders": {
       "apple-model": "ask",
       "meaning": "skip",
       "own-sound": "skip",
       "repeat-sound": "ask",
       "repeat-words": "off"
      },
      "joints": true,
      "steadyJoints": true
     },
     "shows": [
      {
       "feed": "https://c.test/f",
       "finders": {
        "apple-model": "skip"
       },
       "joints": false
      },
      {
       "feed": "https://show-a.test/feed",
       "finders": {
        "own-sound": "ask"
       }
      },
      {
       "feed": "https://www.Show-B.test/rss/",
       "finders": {
        "meaning": "ask"
       },
       "steadyJoints": false
      }
     ],
     "version": 1,
     "writtenAt": 1700000000
    }
    """

  /// shows.json as the app keeps it: the feed key of each address and the app's show id. B's
  /// address is spelt another way than the Mac wrote it.
  private let table = MacFiles.table(
    TeachingShows.parse(
      #"{"https://show-a.test/feed": "a-id", "http://show-b.test/rss": "b-id", "https://c.test/f/": "c-id", "https://d.test/x": "d-id"}"#)
      ?? [:])

  private func read(_ text: String = macText) -> ShowTuning { ShowTuning(text: text, showOf: table) }

  func testTheFileTheMacWroteReadsAsTheMacMeantIt() {
    let set = read()
    // The default block: "repeat-words" is off for every show, steady files are on.
    for show in ["a-id", "b-id", "c-id", "d-id", "never-heard-of"] {
      XCTAssertEqual(set.level(forFinder: "repeat-words", show: show), .off, show)
      XCTAssertEqual(set.level(forFinder: "repeat-sound", show: show), .ask, show)
      XCTAssertEqual(set.level(forSort: "host_ask", show: show), .skip, show)
    }
    for show in ["a-id", "c-id", "d-id", "never-heard-of"] {
      XCTAssertTrue(set.steadyJoints(show: show), show)
    }
    XCTAssertEqual(set.askThreshold, 0.35)
    // The shows with a line of their own.
    XCTAssertEqual(set.level(forFinder: "own-sound", show: "a-id"), .ask)
    XCTAssertEqual(set.level(forFinder: "meaning", show: "a-id"), .skip)
    XCTAssertEqual(set.level(forFinder: "meaning", show: "b-id"), .ask, "found through the feed key")
    XCTAssertEqual(set.level(forFinder: "own-sound", show: "b-id"), .skip)
    XCTAssertFalse(set.steadyJoints(show: "b-id"), "its own steadyJoints key")
    XCTAssertTrue(set.joints(show: "b-id"))
    XCTAssertFalse(set.joints(show: "c-id"))
    XCTAssertTrue(set.joints(show: "a-id"))
    XCTAssertTrue(set.joints(show: "d-id"))
    XCTAssertEqual(set.level(forFinder: "own-sound", show: "c-id"), .skip)
    // Apple's model asks everywhere but on the show where the Mac's bar let it skip.
    for show in ["a-id", "b-id", "d-id", "never-heard-of"] {
      XCTAssertEqual(set.level(forFinder: "apple-model", show: show), .ask, show)
    }
    XCTAssertEqual(set.level(forFinder: "apple-model", show: "c-id"), .skip)
  }

  func testTheKeysTheMacWritesAreTheOnesThePhoneLooksFor() throws {
    let root = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(Self.macText.utf8)) as? [String: Any])
    XCTAssertEqual(Set(root.keys), ["version", "writtenAt", "default", "shows"])
    let block = try XCTUnwrap(root["default"] as? [String: Any])
    XCTAssertEqual(Set(block.keys), ["finders", "joints", "steadyJoints", "ask"])
    // The Mac does not choose the "ahead" finder yet, so it stays at the built-in level (skip).
    XCTAssertEqual(
      Set(try XCTUnwrap(block["finders"] as? [String: String]).keys),
      Set(ShowTuning.finderNames).subtracting(
        [ShowTuning.ahead, ShowTuning.openingLines, ShowTuning.filledHoles]))
    let shows = try XCTUnwrap(root["shows"] as? [[String: Any]])
    XCTAssertEqual(shows.count, 3)
    XCTAssertTrue(shows.allSatisfy { Set($0.keys).isSubset(of: ["feed", "finders", "sorts", "joints", "steadyJoints"]) })
    XCTAssertTrue(shows.allSatisfy { $0["feed"] is String })
  }

  func testTheMacsTextAndTheSameTextOnOneLineReadTheSame() throws {
    let data = try JSONSerialization.data(
      withJSONObject: try JSONSerialization.jsonObject(with: Data(Self.macText.utf8)))
    XCTAssertEqual(ShowTuning(data: data, showOf: table), read())
  }

  func testTheMacsSettingsSortAnEpisodesAds() {
    let set = read()
    func ad(_ start: Double, _ source: String) -> FoundAd {
      FoundAd(start: start, end: start + 30, kind: .ad, advertiser: "", confidence: .unsure, firstWords: "", source: source)
    }
    let ads = [ad(0, "own-sound"), ad(40, "repeat-words"), ad(80, "meaning"), ad(120, "repeat-sound")]
    let onA = set.apply(to: ads, show: "a-id")
    XCTAssertEqual(onA.skip.map(\.source), ["meaning"])
    XCTAssertEqual(onA.ask.map(\.source), ["own-sound", "repeat-sound"], "repeat-words is off")
    let onB = set.apply(to: ads, show: "b-id")
    XCTAssertEqual(onB.skip.map(\.source), ["own-sound"])
    XCTAssertEqual(onB.ask.map(\.source), ["meaning", "repeat-sound"])
  }
}
