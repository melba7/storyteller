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

  func testAGuessedNameIsOnlyFoundAsAWholeWord() {
    XCTAssertFalse(AdSignals.mentions("sometimes I wonder", name: "time", wholeWord: true))
    XCTAssertFalse(AdSignals.mentions("so many times", name: "time", wholeWord: true))
    XCTAssertFalse(AdSignals.mentions("the zoo moves at night", name: "Zoom", wholeWord: true))
    XCTAssertTrue(AdSignals.mentions("time", name: "time", wholeWord: true))
    XCTAssertTrue(AdSignals.mentions("go to time dot com", name: "time", wholeWord: true))
    XCTAssertTrue(AdSignals.mentions("go to time.com/pod", name: "time", wholeWord: true))
    XCTAssertTrue(AdSignals.mentions("we love Quokka's mattress", name: "Quokka", wholeWord: true))
    XCTAssertTrue(
      AdSignals.mentions("visit better help dot com slash show", name: "betterhelp", wholeWord: true))
    XCTAssertFalse(AdSignals.mentions("betterhelps dot com", name: "betterhelp", wholeWord: true))
    // The same text with a firm name keeps the looser rule: a plural or a longer word still says it.
    XCTAssertTrue(AdSignals.mentions("betterhelps dot com", name: "betterhelp"))
    XCTAssertTrue(AdSignals.mentions("sometimes I wonder", name: "time"))
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

  // MARK: The close of a produced spot (N7)

  func testSpotCuesAreTheLegalAndStoreCloseOfAProducedSpot() {
    for text in [
      "Terms and conditions apply", "terms apply.", "Restrictions apply", "See site for details",
      "see store for details", "Member FDIC", "You must be 21 or older", "For ages 18 and up",
      "Please gamble responsibly", "For a limited time only", "Download the Quokka app today",
      "Download the free Quokka app", "Available now at your local store",
      "available today on all platforms", "Wherever you get your podcasts",
      "wherever you listen to podcasts", "Streaming now on Netflix", "Only in theaters",
      "Call 1-800-555-0100", "Call 1 888 555 0100",
    ] {
      XCTAssertTrue(AdSignals.spotCue(text), text)
    }
    for text in [
      "plain talk number 3 here", "the terms of the deal were clear", "download the file",
      "we downloaded the Quokka app", "unlimited time", "available soon", "in the theatre",
      "call 555 0100",
    ] {
      XCTAssertFalse(AdSignals.spotCue(text), text)
    }
  }

  func testALineThatEndsWithATermsCueClosesTheSpot() {
    for text in [
      "Offer valid in select states, restrictions apply.", "Terms and conditions apply",
      "See site for details!", "Must be 21 or older.", "Member FDIC", "Please gamble responsibly.",
    ] {
      XCTAssertTrue(AdSignals.endsWithTermsCue(text), text)
    }
    for text in [
      "Terms and conditions apply, so read them before you sign anything in the shop",
      "Download the Quokka app today", "limited time only", "plain talk number 3 here",
    ] {
      XCTAssertFalse(AdSignals.endsWithTermsCue(text), text)
    }
  }

  func testALineAfterACloserIsCarriedOnlyWithAHardSignal() {
    let closer = "Offer valid in select states, restrictions apply."
    XCTAssertFalse(
      AdSignals.carriesOn("Thanks again to Quokka", advertiser: "Quokka", after: closer))
    XCTAssertTrue(
      AdSignals.carriesOn("Thanks again to Quokka", advertiser: "Quokka", after: "Quokka is great"))
    XCTAssertTrue(
      AdSignals.carriesOn("go to quokka dot com", advertiser: "Quokka", after: closer))
  }
}
