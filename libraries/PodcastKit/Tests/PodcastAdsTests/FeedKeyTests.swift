import XCTest

@testable import PodcastAds

/// The same cases as `feedKey` in applePodcasts.test.ts: the app and the phone's files must agree
/// on which feed address is which show.
final class FeedKeyTests: XCTestCase {
  func testSpellingsOfOneAddressMatch() {
    let key = FeedKey.key("https://example.com/feed.xml")
    XCTAssertEqual(FeedKey.key("http://example.com/feed.xml"), key)
    XCTAssertEqual(FeedKey.key("HTTPS://Example.COM/feed.xml#top"), key)
    XCTAssertEqual(FeedKey.key("https://www.example.com/feed.xml"), key)
    XCTAssertEqual(FeedKey.key("feed://example.com/feed.xml"), key)
    XCTAssertEqual(FeedKey.key("https://example.com/feed/"), FeedKey.key("https://example.com/feed"))
    XCTAssertEqual(
      FeedKey.key("https://example.com/feed/?a=1"), FeedKey.key("https://example.com/feed?a=1"))
  }

  func testDifferentFeedsStayApart() {
    XCTAssertNotEqual(FeedKey.key("https://example.com/a"), FeedKey.key("https://example.com/b"))
    XCTAssertNotEqual(
      FeedKey.key("https://example.com/feed?show=1"), FeedKey.key("https://example.com/feed?show=2"))
    XCTAssertNotEqual(FeedKey.key("https://example.com/Feed"), FeedKey.key("https://example.com/feed"))
  }

  func testTheKeyItself() {
    XCTAssertEqual(FeedKey.key("https://www.Show-B.test/rss/"), "show-b.test/rss")
    XCTAssertEqual(FeedKey.key("  https://Example.com/Feed?A=1#x  "), "example.com/Feed?A=1")
    XCTAssertEqual(FeedKey.key("//example.com/a//"), "example.com/a")
  }

  func testAnAddressWithNoSchemeIsKeptByItsHostAndPath() {
    XCTAssertEqual(FeedKey.key("Example.com/feed/"), "example.com/feed")
    XCTAssertEqual(FeedKey.key("www.example.com?x=1"), "example.com?x=1")
    XCTAssertEqual(FeedKey.key(""), "")
  }

  func testAKeyIsItsOwnKey() {
    for address in ["https://www.Show-B.test/rss/", "example.com/feed?a=1", "feed://x.test/"] {
      let key = FeedKey.key(address)
      XCTAssertEqual(FeedKey.key(key), key)
    }
  }
}
