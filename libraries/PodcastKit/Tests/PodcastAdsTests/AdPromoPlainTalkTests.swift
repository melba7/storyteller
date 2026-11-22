import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// Ordinary show talk that holds a promo cue word and a soft call ("go to", "visit") nearby must
/// give no promo: only a web address, a code or an offer, or cues from two groups, prove one.
final class AdPromoPlainTalkTests: XCTestCase {
  private func assertNoPromo(_ texts: [String], file: StaticString = #filePath, line: UInt = #line) {
    let transcript = makeTranscript(texts)
    let numbered = AdChunker.number(transcript.lines)
    XCTAssertEqual(AdPromoRules.find(lines: numbered), [], file: file, line: line)
    XCTAssertEqual(LocalAds(model: nil).ads(transcript: transcript), [], file: file, line: line)
  }

  func testANewsClipIsNotAPromo() {
    assertNoPromo([
      "The Senate takes up the bill this week.",
      "Here's a clip from the senator's speech on the floor yesterday.",
      "We are not going to go to a vote until the people of Ohio are heard.",
      "That was Senator Brown, speaking on Tuesday.",
      "Our reporter covered the hearing.",
    ])
  }

  func testBeingOnTourInAnInterviewIsNotAPromo() {
    assertNoPromo([
      "So what happened after the record came out?",
      "We were on tour in Japan when my father got sick.",
      "I had to go to the hospital in Osaka and sit with him for a week.",
      "That must have been so hard for you.",
      "It was the hardest month of my life.",
    ])
  }

  func testTalkOfALiveShowAndGoingToTheBathroomIsNotAPromo() {
    assertNoPromo([
      "Okay so last weekend was insane.",
      "We did a live show in Austin and the power went out halfway through.",
      "Somebody in the front row yelled go to the bathroom with your phone light.",
      "And honestly that was the best part of the night.",
      "Anyway, tell me about your week.",
    ])
  }

  func testNewsAboutMembersAndAVisitIsNotAPromo() {
    assertNoPromo([
      "The vote is expected on Thursday.",
      "Members have said privately that they will not support it.",
      "Visit any diner in Ohio and you will hear the same complaint.",
      "People are tired of the fighting.",
      "Let's turn to the economy.",
    ])
  }

  func testTalkOfSomeoneElsesAppIsNotAPromo() {
    assertNoPromo([
      "So I tried the new phones this week.",
      "To set it up you have to download the Google Home app first.",
      "Then go to settings and turn on the new mode, which is buried.",
      "It's a mess of a setup.",
      "Next, the laptops.",
    ])
  }

  func testEarlyAccessAndTheStorePageAreNotAPromo() {
    assertNoPromo([
      "Let's talk about the games we played.",
      "Hades two has been in early access for a year now.",
      "If you go to the store page you can see how much has changed.",
      "It's basically finished at this point.",
      "Next game.",
    ])
  }

  func testRecommendingATvShowIsNotAPromo() {
    assertNoPromo([
      "The new season dropped on Friday.",
      "If you haven't, check out the show, it's the best thing on TV right now.",
      "Go to the third episode, that's where it really takes off.",
      "The acting is just incredible.",
      "Okay, spoilers from here on.",
    ])
  }

  func testAGuestsBookAvailableInLibrariesIsNotAPromo() {
    assertNoPromo([
      "Your book has been a huge hit.",
      "Thank you, my book is available in every library in the country, which still amazes me.",
      "I visit libraries all the time and people tell me about it.",
      "What made you write it?",
      "It started with my grandmother.",
    ])
  }

  func testBuyingTicketsAtTheGateIsNotAPromo() {
    assertNoPromo([
      "So we wanted to see the final.",
      "We bought tickets at the gate for three times the price.",
      "Then we had to go to the other side of the stadium.",
      "And we missed the first goal.",
      "Classic.",
    ])
  }

  func testOneLongLineWithTourAndGoToIsNotAPromo() {
    assertNoPromo([
      "So how was the trip?",
      "We were on tour in Spain and I had to go to the hospital twice, it was a nightmare for the whole band.",
      "Oh no.",
      "Yeah.",
    ])
  }

  func testOurOwnTourWithOnlyASoftCallIsNotAPromo() {
    assertNoPromo([
      "Our tour starts this fall.",
      "Learn more on our site.",
      "Anyway, the budget vote.",
    ])
  }

  func testOurOwnTourWithAWebAddressIsAPromo() {
    let found = AdPromoRules.find(
      lines: AdChunker.number(
        makeTranscript([
          "Our tour starts this fall.", "Learn more at example.com slash tour.", "Anyway, the budget vote.",
        ]).lines))
    XCTAssertEqual(found.map(\.startLine), [1])
    XCTAssertEqual(found.first?.confidence, .sure)
  }

  // Two cue lines are proof only when they are different phrases and one of them asks for
  // something. People say "the live show" twice, or "our tour" and "the live show", in plain talk.

  func testTheSamePhraseTwiceIsNotAPromo() {
    assertNoPromo([
      "We did a live show in Austin last month.",
      "That live show was the best crowd we ever had.",
      "Anyway, back to the story.",
    ])
    assertNoPromo([
      "The game is in early access right now.",
      "Early access games are always a gamble.",
      "So what did you think?",
    ])
  }

  func testTwoWeakPhrasesAreNotAPromo() {
    assertNoPromo([
      "On our tour last year the bus broke down twice.",
      "The live show in Denver nearly did not happen.",
      "It was a mess.",
    ])
    assertNoPromo([
      "The studio gave early access to a few reviewers.",
      "They also promised bonus episodes of the making-of series.",
      "We will see.",
    ])
  }

  func testAStrongPhraseWithAnotherPhraseIsAPromo() {
    let found = AdPromoRules.find(
      lines: AdChunker.number(
        makeTranscript([
          "Our tour starts this fall.", "Get your tickets before they are gone.",
          "Anyway, the budget vote.",
        ]).lines))
    XCTAssertEqual(found.map(\.startLine), [1])
    XCTAssertEqual(found.map(\.endLine), [2])
    XCTAssertEqual(found.first?.confidence, .unsure)
  }

  func testEverydayWordsForTicketsAndMembershipAreNotAPromo() {
    assertNoPromo([
      "We went to see a live show at the Fillmore with my cousin.",
      "I had to buy tickets at the door because the site was down.",
      "It was worth it.",
    ])
    assertNoPromo([
      "My sister told me to become a member of the gym.",
      "Members get early access to the pool in the morning.",
      "I still said no.",
    ])
  }

  func testTalkAboutSomeoneElsesShowIsNotAPromo() {
    assertNoPromo([
      "I finally got to see the show live in New York.",
      "The live show is so much better than the film.",
      "You have to go.",
    ])
    assertNoPromo([
      "You should check out the series if you have not yet.",
      "It is a new series from the people who made the first one.",
      "Here's the trailer, it gives nothing away.",
    ])
  }

  func testAskingTheListenerStillProvesAPromo() {
    func found(_ texts: [String]) -> [AdRange] {
      AdPromoRules.find(lines: AdChunker.number(makeTranscript(texts).lines))
    }
    XCTAssertEqual(
      found(["Become a member today.", "Members get early access to every episode.", "Now, the news."])
        .map(\.confidence), [.unsure])
    XCTAssertEqual(
      found(["Check out our new series.", "It is a new series from this team.", "Now, the news."])
        .map(\.confidence), [.unsure])
    XCTAssertEqual(
      found(["Come see us live this fall.", "The live show has two new stories.", "Now, the news."])
        .map(\.confidence), [.unsure])
  }

  func testOneStrongPhraseAloneIsNotAPromo() {
    assertNoPromo([
      "My sister told me to become a member of the gym.",
      "I said no.",
      "Anyway.",
    ])
  }
}
