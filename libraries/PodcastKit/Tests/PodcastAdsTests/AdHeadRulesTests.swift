import XCTest

@testable import PodcastAds

final class AdHeadRulesTests: XCTestCase {
  /// Lines of ten seconds each, numbered from 1, from plain texts.
  private func lines(_ texts: [String]) -> [NumberedLine] {
    texts.enumerated().map {
      NumberedLine(number: $0.offset + 1, start: Double($0.offset) * 10, end: Double($0.offset) * 10 + 9, text: $0.element)
    }
  }

  func testALeadInWithAWebAddressAndAPromoCodeIsASureAdWithItsEdges() {
    let head = lines([
      "Welcome back to the show, today we talk about sleep.",
      "Before we start, this episode is brought to you by BetterHelp.",
      "Therapy that fits your life, with a counselor you pick yourself.",
      "Go to betterhelp.com slash sleepy to get started.",
      "Use code SLEEPY for ten percent off your first month.",
      "Okay, so let's get into the research.",
      "Dr Walker has studied sleep for thirty years.",
    ])
    let found = AdHeadRules.find(lines: head)
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found.first?.startLine, 2)
    XCTAssertEqual(found.first?.endLine, 5)
    XCTAssertEqual(found.first?.confidence, .sure)
    XCTAssertEqual(found.first?.kind, .ad)
    XCTAssertEqual(found.first?.advertiser, "BetterHelp")
  }

  func testAColdOpenThatOnlyNamesABrandIsNotAnAd() {
    let head = lines([
      "I bought a pair of Nike shoes last week and they fell apart.",
      "My friend works at Google and says the same about their phones.",
      "The nytimes.com reported on it yesterday.",
      "Anyway, welcome to the show.",
    ])
    XCTAssertEqual(AdHeadRules.find(lines: head), [])
  }

  func testALeadInWithNothingToBuyAfterItIsNotSure() {
    let head = lines([
      "This episode is brought to you by the letter Q.",
      "Which is a joke my kids tell.",
      "Anyway, on with the interview.",
    ])
    XCTAssertEqual(AdHeadRules.find(lines: head), [])
  }

  func testAWebAddressWithAPromoCodeAloneIsAnAd() {
    let head = lines([
      "Great to be here.",
      "Head over to squarespace.com slash show and use code SHOW for ten percent off.",
      "Anyway back to the story.",
    ])
    let found = AdHeadRules.find(lines: head)
    XCTAssertEqual(found.map(\.startLine), [2])
    XCTAssertEqual(found.map(\.endLine), [2])
  }

  func testASponsorNamedInTheNotesWithAnOfferNearItIsAnAd() {
    let head = lines([
      "Hello everyone.",
      "A quick word about Athletic Greens, I have it every morning.",
      "Right now you get a free trial at athleticgreens.com.",
      "Now the news.",
    ])
    XCTAssertEqual(AdHeadRules.find(lines: head, sponsors: []).count, 1)
    let named = lines([
      "Hello everyone.",
      "I have Athletic Greens every morning, and so does my brother.",
      "Now the news.",
    ])
    XCTAssertEqual(AdHeadRules.find(lines: named, sponsors: ["Athletic Greens"]), [])
  }

  func testAHostsOwnPlugIsLabelledAsOne() {
    let head = lines([
      "Quick note before we begin.",
      "If you like the show, support us at patreon.com slash ourshow.",
      "Use code FRIEND for a free trial month there.",
      "Now, the story.",
    ])
    XCTAssertEqual(AdHeadRules.find(lines: head).first?.kind, .ownPlug)
  }

  func testSponsorsAreReadFromTheNotes() {
    let notes = "<p>Thanks for listening. This episode is sponsored by BetterHelp and Squarespace.</p>\nSponsors: Athletic Greens, Ridge Wallet"
    XCTAssertEqual(
      Set(AdHeadRules.sponsors(inNotes: notes)),
      ["BetterHelp", "Squarespace", "Athletic Greens", "Ridge Wallet"])
  }

  func testTwoSeparateAdsStaySeparate() {
    let head = lines([
      "Today's sponsor is Ridge. Go to ridge.com slash walk.",
      "Plain talk one.", "Plain talk two.", "Plain talk three.", "Plain talk four.",
      "Plain talk five.",
      "This show is sponsored by Casper, use code NAP for percent off at casper.com.",
    ])
    XCTAssertEqual(AdHeadRules.find(lines: head).map(\.startLine), [1, 7])
  }

  func testAnAdTouchingLongerCreditsIsNotTakenOverByThem() {
    let ad = FoundAd(
      start: 100, end: 130, kind: .ad, advertiser: "A", confidence: .sure, firstWords: "")
    let credits = FoundAd(
      start: 130, end: 190, kind: .credits, advertiser: "", confidence: .sure, firstWords: "")
    XCTAssertEqual(AdHeadRules.merge([ad, credits]).map(\.kind), [.ad, .credits])
  }

  func testAdsFromTwoSourcesAreOneListWithoutDoubles() {
    func ad(_ start: Double, _ end: Double, _ name: String, _ sure: AdConfidence) -> FoundAd {
      FoundAd(start: start, end: end, kind: .ad, advertiser: name, confidence: sure, firstWords: "")
    }
    let merged = AdHeadRules.merge([
      ad(40, 70, "", .unsure), ad(0, 45, "Ridge", .sure), ad(120, 150, "Casper", .sure),
    ])
    XCTAssertEqual(merged.map(\.start), [0, 120])
    XCTAssertEqual(merged.first?.end, 70)
    XCTAssertEqual(merged.first?.confidence, .sure)
    XCTAssertEqual(merged.first?.advertiser, "Ridge")
  }

  func testALeadInAMinuteBeforeAWebAddressIsNotAnAd() {
    let head = lines([
      "This episode is sponsored by Acme, more on them later.",
      "Today my guest is a writer from Dublin.",
      "She spent ten years as a journalist before her first novel.",
      "We talk about her childhood by the sea.",
      "And about how her mother taught her to read.",
      "Then about the long road to her first publisher.",
      "Her book is out now, and she has a page at penguin.com.",
      "Welcome to the show.",
    ])
    XCTAssertEqual(AdHeadRules.find(lines: head), [])
  }

  func testALeadInWithSlowLinesBeforeItsCallToActionIsNotAnAd() {
    // Two lines apart, but 40 seconds of talk between them.
    let head = [
      NumberedLine(number: 1, start: 0, end: 10, text: "Today's sponsor is Acme, more on that soon."),
      NumberedLine(number: 2, start: 10, end: 45, text: "First a long story about my week away from the city."),
      NumberedLine(number: 3, start: 45, end: 50, text: "Find out more at acme.com."),
    ]
    XCTAssertEqual(AdHeadRules.find(lines: head), [])
  }

  func testTheBareWordCodeOrSlashAfterAnAddressIsNotAnOffer() {
    XCTAssertEqual(AdHeadRules.find(lines: lines(["The code is on github.com for anyone to read."])), [])
    XCTAssertEqual(AdHeadRules.find(lines: lines(["The source code lives at github.com, slash the repo."])), [])
  }

  func testAPromoCodeNextToACapitalisedOrQuotedWordIsAnOffer() {
    XCTAssertEqual(
      AdHeadRules.find(lines: lines(["Visit acme.com and take code SLEEPY at checkout."])).map(\.startLine), [1])
    XCTAssertEqual(
      AdHeadRules.find(lines: lines(["Visit acme.com and take the code \"sleepy\" at checkout."])).map(\.startLine), [1])
    XCTAssertEqual(
      AdHeadRules.find(lines: lines(["Visit acme.com, promo code sleepy at checkout."])).map(\.startLine), [1])
    XCTAssertEqual(
      AdHeadRules.find(lines: lines(["Visit acme.com slash sleepy for details."])).map(\.startLine), [1])
  }

  func testTheStepsOfAHeadAreThePhonesStepsUpToIt() {
    XCTAssertEqual(AdHeadRules.steps(upTo: 90), [15, 30, 60, 90])
    XCTAssertEqual(AdHeadRules.steps(upTo: 100), [15, 30, 60, 90, 100])
    XCTAssertEqual(AdHeadRules.steps(upTo: 10), [10])
    XCTAssertEqual(AdHeadRules.steps(upTo: 20), [15, 20])
    XCTAssertEqual(AdHeadRules.steps(upTo: 600), AdHeadRules.steps)
    XCTAssertEqual(AdHeadRules.steps, [15, 30, 60, 90, 120, 150, 180])
    XCTAssertEqual(AdHeadRules.modelSteps, [30, 60, 120, 180])
  }

  func testTheModelsFirstStepCountsOnlyItsSureAnswers() {
    let sure = range(2, 4)
    let unsure = range(6, 8, .unsure)
    let guess = range(9, 9, .guess)
    let answer = [sure, unsure, guess]
    XCTAssertEqual(AdHeadRules.counted(answer, atStep: 30), [sure])
    XCTAssertEqual(AdHeadRules.counted(answer, atStep: 15), [sure])
    XCTAssertEqual(AdHeadRules.counted(answer, atStep: 60), answer)
    XCTAssertEqual(AdHeadRules.counted(answer, atStep: 180), answer)
  }

  func testAShowThatOpensWithAnAdCountsUnsureAnswersAtEveryStep() {
    let sure = range(2, 4)
    let unsure = range(6, 8, .unsure)
    let guess = range(9, 9, .guess)
    let answer = [sure, unsure, guess]
    XCTAssertEqual(AdHeadRules.counted(answer, atStep: 30, opensWithAd: true), answer)
    XCTAssertEqual(AdHeadRules.counted(answer, atStep: 15, opensWithAd: true), answer)
    XCTAssertEqual(AdHeadRules.counted(answer, atStep: 30, opensWithAd: false), [sure])
  }

  func testTheFirstLookIsTheFirstStepAndTheUsualStepsGoOnAfterIt() {
    XCTAssertEqual(AdHeadRules.steps(firstLook: nil), AdHeadRules.steps)
    XCTAssertEqual(AdHeadRules.steps(firstLook: 50), [50, 90, 120, 150, 180])
    XCTAssertEqual(AdHeadRules.steps(firstLook: 45), [45, 60, 90, 120, 150, 180])
    XCTAssertEqual(AdHeadRules.steps(firstLook: 5), [15, 30, 60, 90, 120, 150, 180])
    XCTAssertEqual(AdHeadRules.steps(firstLook: 400), [90, 120, 150, 180])
  }

  func testTheFirstLookIsAModelStepToo() {
    XCTAssertEqual(AdHeadRules.modelSteps(firstLook: nil), AdHeadRules.modelSteps)
    XCTAssertEqual(AdHeadRules.modelSteps(firstLook: 50), [30, 50, 60, 120, 180])
    XCTAssertEqual(AdHeadRules.modelSteps(firstLook: 400), [30, 60, 90, 120, 180])
  }

  // MARK: A shorter carry-on and two signals (E4)

  func testPlainTalkAfterALinkEndsTheAdEvenWhenALaterLineHasAWebAddress() {
    let head = lines([
      "This episode is brought to you by Acme.",
      "Find out more at acme.com.",
      "Plain talk about the week.",
      "More plain talk about the week.",
      "Follow us at example.com.",
    ])
    let found = AdHeadRules.find(lines: head)
    XCTAssertEqual(found.map(\.startLine), [1])
    XCTAssertEqual(found.map(\.endLine), [2])
  }

  func testASignalLineRightAfterTheLinkIsStillCarried() {
    let head = lines([
      "Today's sponsor is Acme.",
      "Go to acme.com slash show.",
      "Use code SHOW at checkout.",
      "Plain talk about the week.",
    ])
    XCTAssertEqual(AdHeadRules.find(lines: head).map(\.endLine), [3])
  }

  func testALineWithAReturnCueEndsTheAdBeforeIt() {
    let head = lines([
      "Today's sponsor is Acme.",
      "Go to acme.com slash show.",
      "Welcome back, find us at example.com.",
    ])
    XCTAssertEqual(AdHeadRules.find(lines: head).map(\.endLine), [2])
  }

  func testASignalAfterALongPauseIsNotCarried() {
    let head = [
      NumberedLine(number: 1, start: 0, end: 8, text: "Brought to you by Acme, go to acme.com slash show."),
      NumberedLine(number: 2, start: 28, end: 33, text: "More at acme.com."),
    ]
    XCTAssertEqual(AdHeadRules.find(lines: head).map(\.endLine), [1])
    let close = [head[0], NumberedLine(number: 2, start: 18, end: 23, text: "More at acme.com.")]
    XCTAssertEqual(AdHeadRules.find(lines: close).map(\.endLine), [2])
  }

  func testAnOfferAloneInPlainTalkIsNotAnAd() {
    let head = lines([
      "We got it for a good price.",
      "That is twenty percent off the usual price.",
      "Anyway, back to my week.",
    ])
    XCTAssertEqual(AdHeadRules.find(lines: head), [])
    XCTAssertEqual(AdHeadRules.find(lines: lines(["Use code SLEEPY for a free trial."])), [])
  }

  func testAnOfferWithAWebAddressNearbyIsAnAd() {
    let head = lines([
      "Welcome to the show.",
      "That is twenty percent off the usual price.",
      "Just go to acme.com slash show.",
      "Now back to the story.",
    ])
    let found = AdHeadRules.find(lines: head)
    XCTAssertEqual(found.map(\.startLine), [2])
    XCTAssertEqual(found.map(\.endLine), [3])
  }

  func testAnOfferWithAWebAddressTwoLinesAwayMarksTheOfferLine() {
    let head = lines([
      "Welcome to the show.",
      "That is twenty percent off the usual price.",
      "Their formula is great.",
      "Visit acme.com.",
      "Now back to the story.",
    ])
    let found = AdHeadRules.find(lines: head)
    XCTAssertEqual(found.map(\.startLine), [2])
    XCTAssertEqual(found.map(\.endLine), [2])
    let far = lines([
      "We got it for a good price.",
      "That is twenty percent off the usual price.",
      "Their formula is great.",
      "They also make a second one.",
      "Visit acme.com.",
    ])
    XCTAssertEqual(AdHeadRules.find(lines: far), [])
  }

  func testASponsorFromTheNotesStillNeedsOnlyACallNearby() {
    let head = lines([
      "Hello everyone.",
      "A quick word about Athletic Greens.",
      "Try it at athleticgreens.com.",
      "Now the news.",
    ])
    XCTAssertEqual(AdHeadRules.find(lines: head, sponsors: ["Athletic Greens"]).map(\.startLine), [2])
  }
}
