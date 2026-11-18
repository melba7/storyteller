import XCTest

@testable import PodcastAds

final class SponsorNamesTests: XCTestCase {
  /// Lines of ten seconds each, numbered from 1, from plain texts.
  private func lines(_ texts: [String]) -> [NumberedLine] {
    texts.enumerated().map {
      NumberedLine(
        number: $0.offset + 1, start: Double($0.offset) * 10, end: Double($0.offset) * 10 + 9,
        text: $0.element)
    }
  }

  func testSponsorsAreAlsoTakenFromLinksWithAPath() {
    let notes =
      "Go to betterhelp.com/show for 10% off. Follow us at instagram.com/show and example.fm/live"
    XCTAssertEqual(
      AdHeadRules.sponsors(inNotes: notes, showLink: URL(string: "https://www.example.fm/")).map(\.text),
      ["betterhelp"])
  }

  func testALinkNamesTheSiteWhateverItsSubdomainAndScheme() {
    let notes = "Offers: https://www.quince.com/pod and get.ridge.com/walk and Shop.Zebra.io/x/y"
    XCTAssertEqual(AdHeadRules.sponsors(inNotes: notes).map(\.text), ["quince", "ridge", "zebra"])
  }

  func testACodeNextToAWebAddressNamesASponsorWithoutAPath() {
    XCTAssertEqual(
      AdHeadRules.sponsors(inNotes: "Use code POD at acme.com for ten percent off"), ["acme"])
    XCTAssertEqual(AdHeadRules.sponsors(inNotes: "Visit acme.com for ten percent off"), [])
  }

  func testSocialSitesPodcastAppsAndTheHostsOwnPlugsAreNotSponsors() {
    let notes = """
      Watch us at youtube.com/watch, listen on spotify.com/show or podcasts.apple.com/us/podcast/x. \
      Join patreon.com/ourshow and ko-fi.com/us. Ad choices: megaphone.fm/adchoices and \
      omnystudio.com/listener. Shorter: bit.ly/abc and amazon.com/dp/123.
      """
    XCTAssertEqual(AdHeadRules.sponsors(inNotes: notes), [])
  }

  func testANameUnderFourLettersFromALinkIsLeftOut() {
    XCTAssertEqual(
      AdHeadRules.sponsors(inNotes: "Try zip.com/pod and ridge.com/pod").map(\.text), ["ridge"])
  }

  func testASponsorInTheNotesAndItsLinkIsOneName() {
    let notes = "This episode is sponsored by BetterHelp. Go to betterhelp.com/show for 10% off."
    XCTAssertEqual(AdHeadRules.sponsors(inNotes: notes), ["BetterHelp"])
    let spaced = "Sponsors: Better Help\nGo to betterhelp.com/show."
    XCTAssertEqual(AdHeadRules.sponsors(inNotes: spaced), ["Better Help"])
  }

  func testASponsorNameSpeltWithSpacesAndDotIsFoundBySpeech() {
    let head = lines(["Better Help makes therapy simple", "visit better help dot com slash show"])
    let found = AdHeadRules.find(lines: head, sponsors: ["betterhelp"])
    XCTAssertEqual(found.map(\.startLine), [1])
    XCTAssertEqual(found.map(\.endLine), [2])
    XCTAssertEqual(found.first?.confidence, .sure)
    XCTAssertEqual(found.first?.advertiser, "betterhelp")
  }

  func testASponsorNamedWithNoCallWithinTwoLinesIsNoAd() {
    let head = lines([
      "Better Help makes therapy simple", "Plain talk one.", "Plain talk two.", "Visit acme.com.",
    ])
    XCTAssertEqual(AdHeadRules.find(lines: head, sponsors: ["betterhelp"]), [])
    XCTAssertEqual(
      AdHeadRules.find(lines: lines(["Better Help makes therapy simple", "Plain talk one."]),
        sponsors: ["betterhelp"]), [])
  }

  func testASitesNameIsTheLabelBeforeItsEnding() {
    XCTAssertEqual(SponsorNames.name(ofHost: "get.quince.com"), "quince")
    XCTAssertEqual(SponsorNames.name(ofHost: "WWW.BBC.CO.UK"), "bbc")
    XCTAssertEqual(SponsorNames.name(ofHost: "example.fm"), "example")
    XCTAssertNil(SponsorNames.name(ofHost: "localhost"))
  }

  // MARK: Names from links are only guesses (ads review fix)

  func testANameFromALinkIsNotFoundInsideAnOrdinaryWord() {
    let sponsors = AdHeadRules.sponsors(inNotes: "Sources: time.com/6123/x and nature.com/articles/x")
    XCTAssertEqual(sponsors.map(\.text), ["time", "nature"])
    let head = lines([
      "welcome to the show sometimes I wonder about all of it",
      "support the show at patreon.com/myshow",
    ])
    let found = AdHeadRules.find(lines: head, sponsors: sponsors)
    XCTAssertEqual(found.map(\.startLine), [2])
    XCTAssertEqual(found.map(\.kind), [.ownPlug])
  }

  func testANameFromALinkCountsOnlyOnALineThatSellsWithSomethingBesidesAnOwnPlug() {
    let sponsors = AdHeadRules.sponsors(inNotes: "Try acme.com/pod today")
    let head = lines(["we love Acme because it is great", "visit acme dot com"])
    XCTAssertEqual(AdHeadRules.find(lines: head, sponsors: sponsors).map(\.startLine), [2])
    // A firm name (written as "sponsored by Acme") still starts the ad at the line that names it.
    XCTAssertEqual(AdHeadRules.find(lines: head, sponsors: ["Acme"]).map(\.startLine), [1])
    let plug = lines(["we love Acme, so join our patreon dot com"])
    XCTAssertEqual(AdHeadRules.find(lines: plug, sponsors: sponsors), [])
  }

  func testANameFromALinkNeverExcusesAnOwnPlug() {
    let head = lines(["acme dot com slash pod", "and join us on patreon.com/myshow"])
    let guess = AdHeadRules.sponsors(inNotes: "Try acme.com/pod today")
    XCTAssertEqual(AdHeadRules.find(lines: head, sponsors: guess).map(\.kind), [.ownPlug])
    XCTAssertEqual(AdHeadRules.find(lines: head, sponsors: ["Acme"]).map(\.kind), [.ad])
  }

  func testOnlyAPlainLinkMakesAGuess() {
    let path = AdHeadRules.sponsors(inNotes: "Try acme.com/pod today")
    XCTAssertEqual(path, [SponsorName("acme", fromLink: true)])
    let code = AdHeadRules.sponsors(inNotes: "Use code POD at acme.com for ten percent off")
    XCTAssertEqual(code, [SponsorName("acme")])
    let both = AdHeadRules.sponsors(inNotes: "Try acme.com/pod. Use code POD at acme.com")
    XCTAssertEqual(both, [SponsorName("acme")])
    let said = AdHeadRules.sponsors(inNotes: "Sponsored by Acme. Try acme.com/pod today")
    XCTAssertEqual(said, [SponsorName("Acme")])
  }
}
