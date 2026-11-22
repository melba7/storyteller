import XCTest

@testable import PodcastFeed

final class FeedNewAddressTests: XCTestCase {
  private func feed(channel: String) -> Data {
    Data(
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
        <channel>
          <title>The Test Show</title>
          \(channel)
          <item>
            <guid>e1</guid>
            <enclosure url="https://cdn.example.com/a.mp3" length="1" type="audio/mpeg"/>
          </item>
        </channel>
      </rss>
      """.utf8)
  }

  func testReadsTheNewFeedAddress() throws {
    let parsed = try FeedParser.parse(
      feed(channel: "<itunes:new-feed-url> https://new.example.com/feed.xml </itunes:new-feed-url>"))
    XCTAssertEqual(parsed.newFeedURL, URL(string: "https://new.example.com/feed.xml"))
  }

  func testAFeedWithoutTheTagHasNoNewAddress() throws {
    XCTAssertNil(try FeedParser.parse(feed(channel: "")).newFeedURL)
  }

  func testAnEmptyOrNonWebAddressIsIgnored() throws {
    for value in ["", "   ", "ftp://x.test/feed", "javascript:alert(1)", "not a link"] {
      let parsed = try FeedParser.parse(
        feed(channel: "<itunes:new-feed-url>\(value)</itunes:new-feed-url>"))
      XCTAssertNil(parsed.newFeedURL, value)
    }
  }
}
