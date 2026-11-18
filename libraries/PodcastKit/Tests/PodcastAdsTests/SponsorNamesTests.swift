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
      AdHeadRules.sponsors(inNotes: notes, showLink: URL(string: "https://www.example.fm/")),
      ["betterhelp"])
  }

  func testALinkNamesTheSiteWhateverItsSubdomainAndScheme() {
    let notes = "Offers: https://www.quince.com/pod and get.ridge.com/walk and Shop.Zebra.io/x/y"
    XCTAssertEqual(AdHeadRules.sponsors(inNotes: notes), ["quince", "ridge", "zebra"])
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
    XCTAssertEqual(AdHeadRules.sponsors(inNotes: "Try zip.com/pod and ridge.com/pod"), ["ridge"])
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
}
