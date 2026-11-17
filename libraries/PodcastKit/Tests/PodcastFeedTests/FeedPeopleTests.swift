import XCTest

@testable import PodcastFeed

final class FeedPeopleTests: XCTestCase {
  private func feed(channel: String, item: String = "") -> Data {
    Data(
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0" xmlns:podcast="https://podcastindex.org/namespace/1.0">
        <channel>
          <title>The Test Show</title>
          \(channel)
          <item>
            <guid>e1</guid>
            \(item)
            <enclosure url="https://cdn.example.com/a.mp3" length="1" type="audio/mpeg"/>
          </item>
        </channel>
      </rss>
      """.utf8)
  }

  func testReadsChannelAndEpisodePeopleWithDefaults() throws {
    let parsed = try FeedParser.parse(
      feed(
        channel: """
          <podcast:person>Ann Host</podcast:person>
          <podcast:person role="Guest" group="Cast" img="https://x.test/b.jpg" href="https://x.test/b">  Bo Guest </podcast:person>
          """,
        item: #"<podcast:person role="producer" group="Crew">Cy</podcast:person>"#))
    XCTAssertEqual(
      parsed.people,
      [
        FeedPerson(name: "Ann Host"),
        FeedPerson(
          name: "Bo Guest", role: "guest", group: "cast",
          imageURL: URL(string: "https://x.test/b.jpg"), link: URL(string: "https://x.test/b")),
      ])
    XCTAssertEqual(
      parsed.episodes[0].people, [FeedPerson(name: "Cy", role: "producer", group: "crew")])
  }

  func testDropsNamelessPeopleAndKeepsOnlyWebLinks() throws {
    let parsed = try FeedParser.parse(
      feed(
        channel: """
          <podcast:person role="host"/>
          <podcast:person>   </podcast:person>
          <podcast:person img="ftp://x.test/a.jpg" href="javascript:alert(1)">Dee</podcast:person>
          """))
    XCTAssertEqual(parsed.people, [FeedPerson(name: "Dee")])
  }

  func testKeepsAtMostTwentyPeople() throws {
    let many = (1...25).map { "<podcast:person>P\($0)</podcast:person>" }.joined()
    let parsed = try FeedParser.parse(feed(channel: many, item: many))
    XCTAssertEqual(parsed.people.count, 20)
    XCTAssertEqual(parsed.people.last?.name, "P20")
    XCTAssertEqual(parsed.episodes[0].people.count, 20)
  }

  func testReadsFundingLinksAndDropsBadOnes() throws {
    let parsed = try FeedParser.parse(
      feed(
        channel: """
          <podcast:funding url="https://x.test/give">Support us</podcast:funding>
          <podcast:funding url="http://x.test/plain"/>
          <podcast:funding url="mailto:a@x.test">Mail</podcast:funding>
          <podcast:funding>No address</podcast:funding>
          """))
    XCTAssertEqual(
      parsed.funding,
      [
        FeedFunding(url: URL(string: "https://x.test/give")!, label: "Support us"),
        FeedFunding(url: URL(string: "http://x.test/plain")!),
      ])
  }

  func testKeepsAtMostFiveFundingLinks() throws {
    let many = (1...8).map { "<podcast:funding url=\"https://x.test/\($0)\">F\($0)</podcast:funding>" }
      .joined()
    XCTAssertEqual(try FeedParser.parse(feed(channel: many)).funding.count, 5)
  }

  func testAFeedWithoutTheTagsHasNone() throws {
    let parsed = try FeedParser.parse(feed(channel: ""))
    XCTAssertEqual(parsed.people, [])
    XCTAssertEqual(parsed.funding, [])
    XCTAssertEqual(parsed.episodes[0].people, [])
  }
}
