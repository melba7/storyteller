import XCTest

@testable import PodcastAds

final class AdSignalsTests: XCTestCase {
  func testHardSignalsAreWebAddressesCodesAndOffers() {
    for text in [
      "go to betterhelp.com slash show", "that is acme dot com", "use code SHOW today",
      "twenty percent off", "start your free trial", "this is brought to you by Acme",
    ] {
      XCTAssertTrue(AdSignals.hardSignal(text), text)
    }
    for text in ["plain talk number 3 here", "we went to the store", "the code is hard to read"] {
      XCTAssertFalse(AdSignals.hardSignal(text), text)
    }
  }

  func testSoftCuesAreTheWordsAnAdCloses() {
    for text in [
      "Thanks again to Quokka", "thank you to our sponsor", "go to the site", "head to the store",
      "visit us", "check out the new line", "sign up today", "learn more", "Again, that's Quokka",
      "Again that's Quokka",
    ] {
      XCTAssertTrue(AdSignals.softCue(text), text)
    }
    for text in ["a visitor came by", "the signup form", "we talked about it"] {
      XCTAssertFalse(AdSignals.softCue(text), text)
    }
  }

  func testReturnCuesSayTheShowIsBack() {
    for text in [
      "Welcome back to the show", "And we're back", "we are back", "We’re back, everyone",
      "back to the conversation", "let's get back to it", "Now, back to the interview",
      "so where were we", "Welcome to Tech Talk", "I'm your host Sam", "on today's episode",
      "in this episode we ask", "my guest today is", "joining me now is",
    ] {
      XCTAssertTrue(AdSignals.returnCue(text), text)
    }
    for text in ["feedback welcome", "they went back to the store", "go to acme dot com"] {
      XCTAssertFalse(AdSignals.returnCue(text), text)
    }
  }

  func testBreakCuesBridgeTwoAdsOfOneBreak() {
    for text in [
      "We'll be right back", "after the break", "after this break", "a quick break", "one more",
      "a word from our friends", "support for this show comes from", "Sponsors",
      "also brought to you",
    ] {
      XCTAssertTrue(AdSignals.breakCue(text), text)
    }
    for text in ["plain talk number 3 here", "they came right backstage", "the one moreover"] {
      XCTAssertFalse(AdSignals.breakCue(text), text)
    }
  }

  func testTheCuesIgnoreCaseAndOnlyMatchWholeWords() {
    XCTAssertTrue(AdSignals.returnCue("WELCOME BACK"))
    XCTAssertFalse(AdSignals.returnCue("unwelcome backlash"))
    XCTAssertFalse(AdSignals.softCue("revisit"))
  }

  func testALineIsCarriedWhenItSellsAndTheShowIsNotBack() {
    XCTAssertTrue(AdSignals.carriesOn("go to acme dot com", advertiser: "Quokka"))
    XCTAssertTrue(AdSignals.carriesOn("Quokka makes it simple", advertiser: "Quokka"))
    XCTAssertTrue(
      AdSignals.carriesOn(
        "I really think you should check out what Quokka is doing for sleep", advertiser: "Quokka"))
    let talk = "Quokka shares fell four percent after the company reported earnings"
    XCTAssertFalse(AdSignals.carriesOn(talk, advertiser: "Quokka"))
    XCTAssertFalse(AdSignals.carriesOn("We had a good week", advertiser: "Quokka"))
    XCTAssertFalse(AdSignals.carriesOn("Welcome back, go to acme.com", advertiser: "Acme"))
  }

  func testAnUnusableAdvertiserNeverMatches() {
    XCTAssertFalse(AdSignals.namesAdvertiser("the sponsor said so", advertiser: "sponsor"))
    XCTAssertFalse(AdSignals.namesAdvertiser("anything", advertiser: ""))
    XCTAssertTrue(AdSignals.namesAdvertiser("we love QUOKKA", advertiser: "Quokka"))
  }

  // MARK: A name, whatever the spaces and the word "dot" (N2)

  func testANameIsFoundWhateverTheSpacesAndTheWordDot() {
    XCTAssertTrue(AdSignals.mentions("visit better help dot com slash show", name: "betterhelp"))
    XCTAssertTrue(AdSignals.mentions("Better Help makes therapy simple", name: "BetterHelp"))
    XCTAssertTrue(AdSignals.mentions("go to betterhelp.com slash show", name: "Better Help"))
    XCTAssertTrue(AdSignals.mentions("athletic greens dot com", name: "Athletic Greens"))
    XCTAssertTrue(AdSignals.mentions("athleticgreens dot com", name: "Athletic Greens"))
    XCTAssertTrue(AdSignals.mentions("we love Quokka's mattress", name: "Quokka"))
    XCTAssertTrue(AdSignals.mentions("try QUOKKA today", name: "quokka"))
    XCTAssertTrue(AdSignals.mentions("better-help is great", name: "better-help"))
    XCTAssertTrue(AdSignals.mentions("go to better help dot com", name: "better-help"))
  }

  func testWordsThatOnlyRunTogetherByChanceAreNotAName() {
    XCTAssertFalse(AdSignals.mentions("a bitter help to nobody", name: "betterhelp"))
    XCTAssertFalse(AdSignals.mentions("the zoo moves at night", name: "Zoom"))
    XCTAssertFalse(AdSignals.mentions("the mat is wet", name: "them"))
  }

  func testAnUnusableNameIsNeverMentioned() {
    XCTAssertFalse(AdSignals.mentions("the sponsor said so", name: "sponsor"))
    XCTAssertFalse(AdSignals.mentions("anything", name: ""))
    XCTAssertFalse(AdSignals.mentions("anything at all", name: "  "))
  }

  func testTheAdvertiserIsNamedWhateverTheSpaces() {
    XCTAssertTrue(AdSignals.namesAdvertiser("visit better help dot com", advertiser: "BetterHelp"))
    XCTAssertTrue(AdSignals.carriesOn("Better Help makes it simple", advertiser: "BetterHelp"))
  }
}
