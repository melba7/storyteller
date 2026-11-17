import XCTest

@testable import PodcastPlayback

final class PlaybackSettingsTests: XCTestCase {
  func testTheDefaultsAreWhatThePlayerUsedBefore() {
    let settings = PlaybackSettings()
    XCTAssertEqual(settings.skipBack, Int(Skip.back))
    XCTAssertEqual(settings.skipForward, Int(Skip.ahead))
    XCTAssertEqual(settings.headphoneNext, .skip)
    XCTAssertEqual(settings.markPlayedWhenLeft, 0)
    XCTAssertFalse(settings.rewindAfterPause)
  }

  func testStoredValuesComeBackTheSame() {
    var settings = PlaybackSettings()
    settings.skipBack = 15
    settings.skipForward = 30
    settings.headphoneNext = .nextEpisode
    settings.markPlayedWhenLeft = 30
    settings.rewindAfterPause = true
    XCTAssertEqual(PlaybackSettings(values: settings.values), settings)
  }

  func testNumbersFromJavaScriptArriveAsDoublesAndAreKept() {
    // Expo hands JavaScript numbers to Swift as Double, also whole ones.
    let settings = PlaybackSettings(values: [
      "skipBack": 30.0, "skipForward": 15.0, "markPlayedWhenLeft": 60.0,
    ])
    XCTAssertEqual(settings.skipBack, 30)
    XCTAssertEqual(settings.skipForward, 15)
    XCTAssertEqual(settings.markPlayedWhenLeft, 60)
    XCTAssertEqual(PlaybackSettings(values: ["skipBack": 30.5]).skipBack, 10)
  }

  func testAnythingNotAChoiceKeepsTheDefault() {
    let settings = PlaybackSettings(values: [
      "skipBack": 7, "skipForward": "45", "headphoneNext": "teleport",
      "markPlayedWhenLeft": 25, "rewindAfterPause": "yes",
    ])
    XCTAssertEqual(settings, PlaybackSettings())
    XCTAssertEqual(PlaybackSettings(values: [:]), PlaybackSettings())
  }

  func testEveryListedChoiceIsAccepted() {
    for amount in PlaybackSettings.skipChoices {
      XCTAssertEqual(PlaybackSettings(values: ["skipBack": amount]).skipBack, amount)
      XCTAssertEqual(PlaybackSettings(values: ["skipForward": amount]).skipForward, amount)
    }
    for left in PlaybackSettings.markPlayedChoices {
      XCTAssertEqual(PlaybackSettings(values: ["markPlayedWhenLeft": left]).markPlayedWhenLeft, left)
    }
  }

  func testNextSkipsAheadByDefault() {
    XCTAssertEqual(PlaybackSettings().nextAction(queueHasNext: true), .skip(seconds: 45))
  }

  func testNextStartsTheNextEpisodeWhenAsked() {
    var settings = PlaybackSettings()
    settings.headphoneNext = .nextEpisode
    settings.skipForward = 30
    XCTAssertEqual(settings.nextAction(queueHasNext: true), .nextEpisode)
    // With nothing queued it still does something useful.
    XCTAssertEqual(settings.nextAction(queueHasNext: false), .skip(seconds: 30))
  }

  func testNextCanGoToTheNextChapter() {
    var settings = PlaybackSettings(values: ["headphoneNext": "nextChapter"])
    XCTAssertEqual(settings.headphoneNext, .nextChapter)
    XCTAssertEqual(settings.nextAction(queueHasNext: true, chapterAhead: true), .nextChapter)
    // In the last chapter, or with none, it skips ahead.
    settings.skipForward = 30
    XCTAssertEqual(settings.nextAction(queueHasNext: true, chapterAhead: false), .skip(seconds: 30))
    XCTAssertEqual(settings.nextAction(queueHasNext: true), .skip(seconds: 30))
    XCTAssertEqual(settings.values["headphoneNext"] as? String, "nextChapter")
  }

  func testPreviousIsTheSkipBackAmount() {
    var settings = PlaybackSettings()
    settings.skipBack = 5
    XCTAssertEqual(settings.previousSeconds, 5)
  }
}

final class RewindRuleTests: XCTestCase {
  func testNothingWhenOff() {
    XCTAssertEqual(RewindRule.seconds(pausedFor: 7200, enabled: false), 0)
  }

  func testShortPausesDoNotRewind() {
    XCTAssertEqual(RewindRule.seconds(pausedFor: 0, enabled: true), 0)
    XCTAssertEqual(RewindRule.seconds(pausedFor: 299.9, enabled: true), 0)
  }

  func testFiveMinutesGoesBackThree() {
    XCTAssertEqual(RewindRule.seconds(pausedFor: 300, enabled: true), 3)
    XCTAssertEqual(RewindRule.seconds(pausedFor: 3599, enabled: true), 3)
  }

  func testAnHourGoesBackTen() {
    XCTAssertEqual(RewindRule.seconds(pausedFor: 3600, enabled: true), 10)
    XCTAssertEqual(RewindRule.seconds(pausedFor: 86_400, enabled: true), 10)
  }

  func testNotANumberDoesNothing() {
    XCTAssertEqual(RewindRule.seconds(pausedFor: .nan, enabled: true), 0)
    XCTAssertEqual(RewindRule.seconds(pausedFor: -50, enabled: true), 0)
  }
}

final class PlayedEarlyTests: XCTestCase {
  func testTheSettingWidensTheWindow() {
    XCTAssertTrue(PlayedRule.isPlayed(position: 570, duration: 600, reachedEnd: false, within: 30))
    XCTAssertFalse(PlayedRule.isPlayed(position: 569, duration: 600, reachedEnd: false, within: 30))
  }

  func testOffKeepsTheFiveSecondRule() {
    XCTAssertTrue(PlayedRule.isPlayed(position: 595, duration: 600, reachedEnd: false, within: 0))
    XCTAssertFalse(PlayedRule.isPlayed(position: 594, duration: 600, reachedEnd: false, within: 0))
  }

  func testASmallerWindowNeverShrinksTheFiveSeconds() {
    XCTAssertTrue(PlayedRule.isPlayed(position: 596, duration: 600, reachedEnd: false, within: 2))
  }
}
