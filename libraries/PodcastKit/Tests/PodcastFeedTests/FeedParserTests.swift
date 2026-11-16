import XCTest

@testable import PodcastFeed

final class FeedParserTests: XCTestCase {
  private func feed(_ items: String, channelExtra: String = "") -> Data {
    Data(
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
           xmlns:content="http://purl.org/rss/1.0/modules/content/">
        <channel>
          <title>The Test Show</title>
          \(channelExtra)
          \(items)
        </channel>
      </rss>
      """.utf8)
  }

  private func item(_ inner: String) -> String {
    "<item>\(inner)<enclosure url=\"https://cdn.example.com/a.mp3\" length=\"123\" type=\"audio/mpeg\"/></item>"
  }

  // MARK: Show

  func testReadsTheShowWithItunesTags() throws {
    let data = feed(
      "",
      channelExtra: """
        <link>https://example.com/show</link>
        <language>en-us</language>
        <description>Plain &amp; simple.</description>
        <itunes:author>Ada Host</itunes:author>
        <itunes:image href="https://example.com/art.jpg"/>
        """)
    let parsed = try FeedParser.parse(data)
    XCTAssertEqual(parsed.title, "The Test Show")
    XCTAssertEqual(parsed.author, "Ada Host")
    XCTAssertEqual(parsed.description, "Plain & simple.")
    XCTAssertEqual(parsed.imageURL, URL(string: "https://example.com/art.jpg"))
    XCTAssertEqual(parsed.link, URL(string: "https://example.com/show"))
    XCTAssertEqual(parsed.language, "en-us")
    XCTAssertTrue(parsed.episodes.isEmpty)
  }

  func testFallsBackToTheImageElementAndSummary() throws {
    let data = feed(
      "",
      channelExtra: """
        <image><url>https://example.com/plain.png</url><title>x</title></image>
        <itunes:summary>From the summary.</itunes:summary>
        """)
    let parsed = try FeedParser.parse(data)
    XCTAssertEqual(parsed.imageURL, URL(string: "https://example.com/plain.png"))
    XCTAssertEqual(parsed.description, "From the summary.")
    XCTAssertNil(parsed.author)
  }

  // MARK: Episodes

  func testReadsAnEpisodeWithItunesTags() throws {
    let data = feed(
      """
      <item>
        <title>Episode One</title>
        <guid isPermaLink="false">abc-123</guid>
        <pubDate>Mon, 02 Jan 2023 10:30:00 +0000</pubDate>
        <itunes:duration>01:02:03</itunes:duration>
        <itunes:season>2</itunes:season>
        <itunes:episode>5</itunes:episode>
        <itunes:image href="https://example.com/ep.jpg"/>
        <description>Short notes.</description>
        <enclosure url="https://cdn.example.com/one.mp3" length="4567" type="audio/mpeg"/>
      </item>
      """)
    let episode = try XCTUnwrap(try FeedParser.parse(data).episodes.first)
    XCTAssertEqual(episode.guid, "abc-123")
    XCTAssertEqual(episode.title, "Episode One")
    XCTAssertEqual(episode.published, Date(timeIntervalSince1970: 1_672_655_400))
    XCTAssertEqual(episode.durationSeconds, 3723)
    XCTAssertEqual(episode.season, 2)
    XCTAssertEqual(episode.number, 5)
    XCTAssertEqual(episode.imageURL, URL(string: "https://example.com/ep.jpg"))
    XCTAssertEqual(episode.notes, "Short notes.")
    XCTAssertEqual(episode.audioURL, URL(string: "https://cdn.example.com/one.mp3"))
    XCTAssertEqual(episode.audioType, "audio/mpeg")
    XCTAssertEqual(episode.audioBytes, 4567)
  }

  func testKeepsTheFeedOrder() throws {
    let data = feed(
      item("<title>A</title><guid>1</guid>") + item("<title>B</title><guid>2</guid>"))
    XCTAssertEqual(try FeedParser.parse(data).episodes.map(\.title), ["A", "B"])
  }

  func testUsesTheAudioURLWhenThereIsNoGuid() throws {
    let data = feed(item("<title>No guid</title>"))
    let episode = try XCTUnwrap(try FeedParser.parse(data).episodes.first)
    XCTAssertEqual(episode.guid, "https://cdn.example.com/a.mp3")
  }

  func testUsesTheAudioURLWhenTheGuidIsEmpty() throws {
    let data = feed(item("<title>Blank</title><guid>  </guid>"))
    let episode = try XCTUnwrap(try FeedParser.parse(data).episodes.first)
    XCTAssertEqual(episode.guid, "https://cdn.example.com/a.mp3")
  }

  func testSkipsAnItemWithoutAnAudioEnclosure() throws {
    let data = feed(
      """
      <item><title>Text only</title><guid>t</guid></item>
      <item><title>Picture</title><guid>p</guid>
        <enclosure url="https://example.com/a.jpg" length="1" type="image/jpeg"/></item>
      \(item("<title>Audio</title><guid>a</guid>"))
      """)
    XCTAssertEqual(try FeedParser.parse(data).episodes.map(\.title), ["Audio"])
  }

  func testAcceptsAnEnclosureWithoutATypeWhenItLooksLikeAudio() throws {
    let data = feed(
      """
      <item><title>Untyped</title>
        <enclosure url="https://example.com/ep.m4a?x=1" length="0"/></item>
      """)
    let episode = try XCTUnwrap(try FeedParser.parse(data).episodes.first)
    XCTAssertEqual(episode.audioURL, URL(string: "https://example.com/ep.m4a?x=1"))
    XCTAssertEqual(episode.audioBytes, nil)
  }

  func testEpisodeWithoutATitleStillGetsOne() throws {
    let episode = try XCTUnwrap(
      try FeedParser.parse(feed(item("<guid>x</guid>"))).episodes.first)
    XCTAssertEqual(episode.title, "Untitled episode")
  }

  func testBadNumbersAreLeftOut() throws {
    let data = feed(
      item("<guid>x</guid><itunes:season>two</itunes:season><itunes:episode></itunes:episode>"))
    let episode = try XCTUnwrap(try FeedParser.parse(data).episodes.first)
    XCTAssertNil(episode.season)
    XCTAssertNil(episode.number)
  }

  // MARK: Durations

  func testDurationFormats() {
    XCTAssertEqual(FeedParser.parseDuration("01:02:03"), 3723)
    XCTAssertEqual(FeedParser.parseDuration("1:02:03"), 3723)
    XCTAssertEqual(FeedParser.parseDuration("42:10"), 2530)
    XCTAssertEqual(FeedParser.parseDuration("3600"), 3600)
    XCTAssertEqual(FeedParser.parseDuration(" 1234.5 "), 1234.5)
    XCTAssertEqual(FeedParser.parseDuration("00:00:12.5"), 12.5)
  }

  func testBadDurationsAreNil() {
    XCTAssertNil(FeedParser.parseDuration(""))
    XCTAssertNil(FeedParser.parseDuration("soon"))
    XCTAssertNil(FeedParser.parseDuration("1:2:3:4"))
    XCTAssertNil(FeedParser.parseDuration("-5"))
    XCTAssertNil(FeedParser.parseDuration("12:xx"))
  }

  func testDurationInAnItem() throws {
    for (text, seconds) in [("10:00", 600.0), ("90", 90.0), ("1:00:00", 3600.0)] {
      let data = feed(item("<guid>d</guid><itunes:duration>\(text)</itunes:duration>"))
      XCTAssertEqual(try FeedParser.parse(data).episodes.first?.durationSeconds, seconds)
    }
  }

  // MARK: Dates

  func testDateVariants() {
    let base = 1_672_655_400.0  // 2023-01-02 10:30:00 UTC
    let cases: [(String, Double?)] = [
      ("Mon, 02 Jan 2023 10:30:00 +0000", base),
      ("Mon, 02 Jan 2023 10:30:00 GMT", base),
      ("Mon, 02 Jan 2023 10:30:00 UT", base),
      ("Mon, 02 Jan 2023 05:30:00 EST", base),
      ("Mon, 02 Jan 2023 02:30:00 PST", base),
      ("Sun, 01 Jan 2023 23:30:00 PST", base - 3 * 3600),
      ("Mon, 02 Jan 2023 12:30:00 +0200", base),
      ("Mon, 02 Jan 2023 10:30 +0000", base),
      ("02 Jan 2023 10:30:00 +0000", base),
      ("Mon, 2 Jan 2023 10:30:00 +0000", base),
      ("Mon, 02 Jan 23 10:30:00 +0000", base),
      ("Mon, 02 Jan 2023 10:30:00 +02:00", base - 2 * 3600),
      ("2023-01-02T10:30:00Z", base),
      ("  Mon, 02 Jan 2023 10:30:00 +0000  ", base),
      ("sometime last week", nil),
      ("", nil),
    ]
    for (text, expected) in cases {
      let got = FeedParser.parseDate(text)?.timeIntervalSince1970
      if let expected {
        XCTAssertEqual(got, expected, "for \(text)")
      } else {
        XCTAssertNil(got, "for \(text)")
      }
    }
  }

  // MARK: Notes

  func testNotesStripHTMLAndDecodeEntities() throws {
    let data = feed(
      item(
        """
        <guid>n</guid>
        <description><![CDATA[<p>Hello <b>there</b> &amp; welcome&nbsp;back.</p><p>Second&#33; &#x41; &quot;q&quot; &lt;3</p><ul><li>One</li><li>Two</li></ul>Line<br/>break<br>again]]></description>
        """))
    let notes = try XCTUnwrap(try FeedParser.parse(data).episodes.first?.notes)
    XCTAssertEqual(
      notes,
      "Hello there & welcome back.\nSecond! A \"q\" <3\nOne\nTwo\nLine\nbreak\nagain")
  }

  func testNotesCollapseBlankLines() {
    XCTAssertEqual(
      FeedParser.plainText("<p>One</p>\n\n\n<p></p><p></p><p>Two</p>"), "One\n\nTwo")
  }

  func testNotesPreferContentEncoded() throws {
    let data = feed(
      item(
        """
        <guid>c</guid>
        <description>Short.</description>
        <content:encoded><![CDATA[<p>The <i>full</i> notes.</p>]]></content:encoded>
        """))
    XCTAssertEqual(try FeedParser.parse(data).episodes.first?.notes, "The full notes.")
  }

  func testNotesFallBackToTheSummary() throws {
    let data = feed(item("<guid>s</guid><itunes:summary>Summary text.</itunes:summary>"))
    XCTAssertEqual(try FeedParser.parse(data).episodes.first?.notes, "Summary text.")
  }

  func testUnknownEntitiesAreKept() {
    XCTAssertEqual(FeedParser.plainText("a &madeup; b &#99999999999; c"), "a &madeup; b &#99999999999; c")
  }

  // MARK: Not a feed

  func testAnHTMLPageIsNotAFeed() {
    let page = Data("<!DOCTYPE html><html><head><title>Hi</title></head><body><p>Hello</p></body></html>".utf8)
    XCTAssertThrowsError(try FeedParser.parse(page)) { error in
      XCTAssertEqual(error.localizedDescription, "This link isn't a podcast feed.")
    }
  }

  func testAnAtomFeedIsNotSupported() {
    let atom = Data(
      "<?xml version=\"1.0\"?><feed xmlns=\"http://www.w3.org/2005/Atom\"><title>x</title></feed>".utf8)
    XCTAssertThrowsError(try FeedParser.parse(atom)) { error in
      XCTAssertEqual(error.localizedDescription, "This link isn't a podcast feed.")
    }
  }

  func testEmptyDataIsNotAFeed() {
    XCTAssertThrowsError(try FeedParser.parse(Data())) { error in
      XCTAssertEqual(error.localizedDescription, "This link isn't a podcast feed.")
    }
  }

  func testBrokenXMLIsNotAFeed() {
    let broken = Data("<rss version=\"2.0\"><channel><title>Oops</title><item><title>x</item></channel>".utf8)
    XCTAssertThrowsError(try FeedParser.parse(broken)) { error in
      XCTAssertEqual(error.localizedDescription, "This link isn't a podcast feed.")
    }
  }

  func testAFeedWithoutAChannelIsNotAFeed() {
    let data = Data("<rss version=\"2.0\"></rss>".utf8)
    XCTAssertThrowsError(try FeedParser.parse(data))
  }
}
