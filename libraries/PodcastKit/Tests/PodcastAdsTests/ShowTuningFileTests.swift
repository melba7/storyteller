import XCTest

@testable import PodcastAds

/// Reading `show-settings.json`: the text the Mac's plan gives, every setting, names and levels
/// the phone does not know, and files that are damaged. A file that cannot be read gives the
/// built-in default, never a crash and never "everything off".
final class ShowTuningFileTests: XCTestCase {
  /// The file's shape as the plan writes it, word for word (the feed is the plan's placeholder).
  static let planText =
    #"{"version": 1, "writtenAt": 1700000000, "default": {"finders": {"own-sound": "skip", "repeat-sound": "ask", "repeat-words": "ask", "meaning": "skip"}, "joints": true, "steadyJoints": false, "ask": 0.35}, "shows": [{"feed": "<feed address>", "finders": {"repeat-words": "skip"}, "sorts": {"host_ask": "ask"}, "joints": false}]}"#

  private let table = MacFiles.table([FeedKey.key("<feed address>"): "show-1"])

  private func read(_ text: String?) -> ShowTuning { ShowTuning(text: text, showOf: table) }

  /// A file with only a default block.
  private func withDefault(_ block: String) -> ShowTuning {
    read(#"{"version": 1, "default": \#(block), "shows": []}"#)
  }

  // MARK: The plan's text

  func testTheTextOfThePlanReadsAsWritten() {
    let set = read(Self.planText)
    XCTAssertEqual(set.level(forFinder: "own-sound", show: "show-1"), .skip)
    XCTAssertEqual(set.level(forFinder: "repeat-sound", show: "show-1"), .ask)
    XCTAssertEqual(set.level(forFinder: "repeat-words", show: "show-1"), .skip, "the show's own")
    XCTAssertEqual(set.level(forFinder: "meaning", show: "show-1"), .skip)
    XCTAssertEqual(set.level(forSort: "host_ask", show: "show-1"), .ask)
    XCTAssertEqual(set.level(forSort: "sponsor", show: "show-1"), .skip)
    XCTAssertFalse(set.joints(show: "show-1"))
    XCTAssertFalse(set.steadyJoints(show: "show-1"))
    XCTAssertEqual(set.askThreshold, 0.35)
    // Another show gets the default block.
    XCTAssertEqual(set.level(forFinder: "repeat-words", show: "show-2"), .ask)
    XCTAssertEqual(set.level(forSort: "host_ask", show: "show-2"), .skip)
    XCTAssertTrue(set.joints(show: "show-2"))
  }

  func testTheTextOfThePlanIsTheBuiltInDefaultForAnyShowButTheOneItNames() {
    let set = read(Self.planText)
    let plain = ShowTuning()
    for name in ShowTuning.finderNames {
      XCTAssertEqual(set.level(forFinder: name, show: "other"), plain.level(forFinder: name, show: "other"))
    }
    XCTAssertEqual(set.joints(show: "other"), plain.joints(show: "other"))
    XCTAssertEqual(set.steadyJoints(show: "other"), plain.steadyJoints(show: "other"))
    XCTAssertEqual(set.askThreshold, plain.askThreshold)
  }

  func testWithoutATableTheFeedAddressIsTheShow() {
    let set = ShowTuning(text: Self.planText)
    XCTAssertEqual(set.level(forFinder: "repeat-words", show: "<feed address>"), .skip)
    XCTAssertEqual(set.level(forFinder: "repeat-words", show: "show-1"), .ask)
  }

  func testAShowIsFoundThroughTheFeedKeyWhateverTheSpellingOfItsAddress() {
    let text = #"{"version": 1, "shows": [{"feed": "http://WWW.Show-A.test/feed/", "finders": {"meaning": "off"}}]}"#
    let set = ShowTuning(text: text, showOf: MacFiles.table([FeedKey.key("https://show-a.test/feed"): "a"]))
    XCTAssertEqual(set.level(forFinder: "meaning", show: "a"), .off)
  }

  func testAShowTheTableDoesNotKnowIsLeftOut() {
    let set = ShowTuning(text: Self.planText, showOf: MacFiles.table([:]))
    XCTAssertEqual(set, ShowTuning(), "the default block is the built-in one and the only show is gone")
    XCTAssertEqual(set.level(forFinder: "repeat-words", show: "show-1"), .ask)
  }

  // MARK: Every setting

  func testEverySettingOfTheDefaultBlockIsRead() {
    let set = withDefault(
      #"{"finders": {"own-sound": "off", "repeat-sound": "skip", "repeat-words": "off", "meaning": "ask"}, "sorts": {"intro_credits": "off"}, "joints": false, "steadyJoints": true, "ask": 0.5}"#)
    XCTAssertEqual(set.level(forFinder: "own-sound", show: "x"), .off)
    XCTAssertEqual(set.level(forFinder: "repeat-sound", show: "x"), .skip)
    XCTAssertEqual(set.level(forFinder: "repeat-words", show: "x"), .off)
    XCTAssertEqual(set.level(forFinder: "meaning", show: "x"), .ask)
    XCTAssertEqual(set.level(forSort: "intro_credits", show: "x"), .off)
    XCTAssertEqual(set.level(forSort: "sponsor", show: "x"), .skip)
    XCTAssertFalse(set.joints(show: "x"))
    XCTAssertTrue(set.steadyJoints(show: "x"))
    XCTAssertEqual(set.askThreshold, 0.5)
  }

  func testEverySettingOfAShowEntryIsRead() {
    let text = """
      {"version": 1, "shows": [{"feed": "<feed address>",
        "finders": {"own-sound": "off", "repeat-sound": "skip", "repeat-words": "off", "meaning": "ask"},
        "sorts": {"sponsor": "ask", "network_promo": "off", "host_ask": "ask", "intro_credits": "off"},
        "joints": false, "steadyJoints": true}]}
      """
    let set = read(text)
    XCTAssertEqual(set.level(forFinder: "own-sound", show: "show-1"), .off)
    XCTAssertEqual(set.level(forFinder: "repeat-sound", show: "show-1"), .skip)
    XCTAssertEqual(set.level(forFinder: "repeat-words", show: "show-1"), .off)
    XCTAssertEqual(set.level(forFinder: "meaning", show: "show-1"), .ask)
    XCTAssertEqual(set.level(forSort: "sponsor", show: "show-1"), .ask)
    XCTAssertEqual(set.level(forSort: "network_promo", show: "show-1"), .off)
    XCTAssertEqual(set.level(forSort: "host_ask", show: "show-1"), .ask)
    XCTAssertEqual(set.level(forSort: "intro_credits", show: "show-1"), .off)
    XCTAssertFalse(set.joints(show: "show-1"))
    XCTAssertTrue(set.steadyJoints(show: "show-1"))
  }

  func testTheAskThresholdIsKeptBetweenTwoTenthsAndSixTenths() {
    XCTAssertEqual(withDefault(#"{"ask": 0.1}"#).askThreshold, 0.2)
    XCTAssertEqual(withDefault(#"{"ask": 0}"#).askThreshold, 0.2)
    XCTAssertEqual(withDefault(#"{"ask": -3}"#).askThreshold, 0.2)
    XCTAssertEqual(withDefault(#"{"ask": 0.9}"#).askThreshold, 0.6)
    XCTAssertEqual(withDefault(#"{"ask": 1e999}"#).askThreshold, 0.35, "not a number the phone can use")
    XCTAssertEqual(withDefault(#"{"ask": 0.2}"#).askThreshold, 0.2)
    XCTAssertEqual(withDefault(#"{"ask": 0.6}"#).askThreshold, 0.6)
    XCTAssertEqual(withDefault(#"{"ask": 0.45}"#).askThreshold, 0.45)
    XCTAssertEqual(withDefault(#"{"ask": "high"}"#).askThreshold, 0.35)
    XCTAssertEqual(withDefault(#"{"ask": null}"#).askThreshold, 0.35)
    XCTAssertEqual(withDefault(#"{"ask": true}"#).askThreshold, 0.35)
    XCTAssertEqual(withDefault("{}").askThreshold, 0.35)
  }

  func testAShowEntryHasNoThresholdOfItsOwn() {
    let text = #"{"version": 1, "default": {"ask": 0.4}, "shows": [{"feed": "<feed address>", "ask": 0.55}]}"#
    XCTAssertEqual(read(text).askThreshold, 0.4)
  }

  // MARK: Names and levels the phone does not know

  func testUnknownNamesAreIgnored() {
    let set = withDefault(
      #"{"finders": {"joints": "off", "tap": "off", "": "off", "Meaning": "off", "own-sound": "ask"}, "sorts": {"poetry": "off", "none": "off", "Sponsor": "off"}}"#)
    XCTAssertEqual(set.level(forFinder: "own-sound", show: "x"), .ask, "a known name beside them is read")
    XCTAssertEqual(set.level(forFinder: "meaning", show: "x"), .skip)
    XCTAssertEqual(set.level(forFinder: "joints", show: "x"), .skip)
    XCTAssertEqual(set.level(forFinder: "tap", show: "x"), .skip)
    XCTAssertEqual(set.level(forSort: "poetry", show: "x"), .skip)
    XCTAssertEqual(set.level(forSort: "none", show: "x"), .skip)
    XCTAssertEqual(set.level(forSort: "sponsor", show: "x"), .skip)
  }

  func testAnUnknownKeyBesideTheKnownOnesChangesNothing() {
    let extra = Self.planText.replacingOccurrences(
      of: #""joints": true,"#, with: #""joints": true, "colour": "blue", "extra": [1, 2],"#)
    XCTAssertEqual(read(extra), read(Self.planText))
  }

  func testALevelThatIsNotSkipAskOrOffIsIgnored() {
    let set = read(
      """
      {"version": 1,
       "default": {"finders": {"own-sound": "maybe", "repeat-sound": "SKIP", "repeat-words": 3, "meaning": null}},
       "shows": [{"feed": "<feed address>", "finders": {"own-sound": "yes", "meaning": ["off"]}, "sorts": {"host_ask": " ask"}}]}
      """)
    // The default block's bad levels leave the built-in default; the show's leave the default's.
    XCTAssertEqual(set.level(forFinder: "own-sound", show: "show-1"), .skip)
    XCTAssertEqual(set.level(forFinder: "repeat-sound", show: "show-1"), .ask)
    XCTAssertEqual(set.level(forFinder: "repeat-words", show: "show-1"), .ask)
    XCTAssertEqual(set.level(forFinder: "meaning", show: "show-1"), .skip)
    XCTAssertEqual(set.level(forSort: "host_ask", show: "show-1"), .skip)
  }

  func testAShowThatSaysNothingUseableIsTheDefault() {
    let text = #"{"version": 1, "shows": [{"feed": "<feed address>", "finders": "off", "sorts": 7, "joints": "no", "steadyJoints": 1}]}"#
    let set = read(text)
    XCTAssertEqual(set.level(forFinder: "meaning", show: "show-1"), .skip)
    XCTAssertTrue(set.joints(show: "show-1"))
    XCTAssertFalse(set.steadyJoints(show: "show-1"))
  }

  func testTwoEntriesForOneShowAreOneEntryTheLaterOneWinningKeyByKey() {
    let text = """
      {"version": 1, "shows": [
        {"feed": "<feed address>", "finders": {"meaning": "off", "own-sound": "ask"}, "joints": false},
        {"feed": "<feed address>", "finders": {"meaning": "ask"}}]}
      """
    let set = read(text)
    XCTAssertEqual(set.level(forFinder: "meaning", show: "show-1"), .ask)
    XCTAssertEqual(set.level(forFinder: "own-sound", show: "show-1"), .ask)
    XCTAssertFalse(set.joints(show: "show-1"))
  }

  func testOneBadShowEntryDoesNotSpoilTheOnesAfterIt() {
    let text = """
      {"version": 1, "shows": [7, "feed", null, {"finders": {"meaning": "off"}}, {"feed": 4},
        {"feed": "<feed address>", "finders": {"meaning": "off"}}]}
      """
    XCTAssertEqual(read(text).level(forFinder: "meaning", show: "show-1"), .off)
  }

  // MARK: Files that cannot be read

  func testAFileThatCannotBeReadIsTheBuiltInDefaultNotEverythingOff() {
    let broken: [String?] = [
      nil, "", "   ", "not json", "{", "[]", "7", "null", "\"text\"",
      #"{"version": 2, "default": {"finders": {"meaning": "off"}}}"#,
      #"{"version": "1", "default": {"finders": {"meaning": "off"}}}"#,
      #"{"version": 1.5, "default": {"finders": {"meaning": "off"}}}"#,
      #"{"default": {"finders": {"meaning": "off"}}}"#,
      #"{"version": null, "default": {"finders": {"meaning": "off"}}}"#,
      #"{"version": 1, "default": {"finders": {"meaning": "off"}"#,
      String(decoding: [0xFF, 0xFE, 0x00, 0x7B], as: UTF8.self),
    ]
    for text in broken {
      let set = read(text)
      XCTAssertEqual(set, ShowTuning(), "\(text ?? "nil")")
      XCTAssertEqual(set.level(forFinder: "own-sound", show: "a"), .skip)
      XCTAssertEqual(set.level(forFinder: "meaning", show: "a"), .skip)
    }
    XCTAssertEqual(ShowTuning(data: Data(), showOf: table), ShowTuning())
    XCTAssertEqual(ShowTuning(data: Data([0x00, 0xFF, 0x10]), showOf: table), ShowTuning())
  }

  func testAFileOverFiveMegabytesIsTheBuiltInDefault() {
    let body = #"{"version": 1, "default": {"finders": {"meaning": "off"}}, "shows": []}"#
    XCTAssertEqual(read(body).level(forFinder: "meaning", show: "a"), .off, "the same file when it is small")
    let padding = String(repeating: " ", count: ShowTuning.maxBytes)
    XCTAssertEqual(read(body + padding), ShowTuning())
    // Exactly at the limit it is still read.
    let exact = body + String(repeating: " ", count: ShowTuning.maxBytes - body.utf8.count)
    XCTAssertEqual(exact.utf8.count, ShowTuning.maxBytes)
    XCTAssertEqual(read(exact).level(forFinder: "meaning", show: "a"), .off)
  }

  func testAVeryDeepFileDoesNotCrash() {
    let deep = String(repeating: "[", count: 5000) + String(repeating: "]", count: 5000)
    XCTAssertEqual(read(#"{"version": 1, "default": \#(deep), "shows": \#(deep)}"#), ShowTuning())
  }
}
