import XCTest

@testable import PodcastAds

/// The copy an entry of `ahead-ads.json` may carry: how the phone reads it and what a bad one means.
final class PreparedCopyTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private let goodSha = String(repeating: "ab", count: 32)

  private func mark() -> String {
    #"{"kind": "ad", "confidence": "high", "start": 50, "end": 80, "startWords": "one two three four five six seven eight", "endWords": "nine ten eleven twelve thirteen fourteen fifteen sixteen"}"#
  }

  private func entry(copy: String?, ads: [String]? = nil) -> AheadEntry? {
    let list = (ads ?? [mark()]).joined(separator: ", ")
    let tail = copy.map { #", "copy": \#($0)"# } ?? ""
    let text =
      #"{"version": 1, "writtenAt": 1, "episodes": [{"feed": "https://show.test/rss", "guid": "g1", "title": "Episode One", "marked": \#(now.timeIntervalSince1970 - 100), "ads": [\#(list)]\#(tail)}]}"#
    return AheadFile(data: Data(text.utf8)).episodes.first
  }

  private func aCopy(
    file: String = "prepared/0123456789ab.mp3", sha: String? = nil, bytes: String = "48123456"
  ) -> String {
    #"{"file": "\#(file)", "sha256": "\#(sha ?? goodSha)", "bytes": \#(bytes)}"#
  }

  func testAGoodCopyIsRead() {
    let read = entry(copy: aCopy())
    XCTAssertEqual(
      read?.copy, PreparedCopy(file: "prepared/0123456789ab.mp3", sha256: goodSha, bytes: 48_123_456))
    XCTAssertEqual(read?.ads.count, 1)
  }

  func testAnEntryWithNoCopyHasNone() {
    XCTAssertNotNil(entry(copy: nil))
    XCTAssertNil(entry(copy: nil)?.copy)
  }

  func testTheHashIsKeptInLowerCase() {
    let upper = String(repeating: "AB", count: 32)
    XCTAssertEqual(entry(copy: aCopy(sha: upper))?.copy?.sha256, goodSha)
  }

  func testACopyThatIsNotPlainReadsAsNoCopyAndTheEntryIsStillRead() {
    let bad = [
      aCopy(file: "prepared/../x.mp3"), aCopy(file: "prepared/a/b.mp3"), aCopy(file: "prepared/"),
      aCopy(file: "prepared/.hidden.mp3"), aCopy(file: "prepared/.."), aCopy(file: "other/a.mp3"),
      aCopy(file: "/prepared/a.mp3"), aCopy(file: "a.mp3"), aCopy(file: "prepared//a.mp3"),
      aCopy(file: "prepared/a..mp3"), aCopy(file: #"prepared/a\\b.mp3"#), aCopy(file: ""),
      aCopy(sha: String(repeating: "a", count: 63)), aCopy(sha: String(repeating: "a", count: 65)),
      aCopy(sha: String(repeating: "g", count: 64)), aCopy(sha: ""),
      aCopy(bytes: "0"), aCopy(bytes: "-5"), aCopy(bytes: "1.5"), aCopy(bytes: #""big""#),
      #"{"file": "prepared/a.mp3", "sha256": "\#(goodSha)"}"#, "3", #""prepared/a.mp3""#, "null",
    ]
    for text in bad {
      let read = entry(copy: text)
      XCTAssertNotNil(read, "the entry is still read: \(text)")
      XCTAssertNil(read?.copy, "no copy: \(text)")
      XCTAssertEqual(read?.ads.count, 1, text)
    }
  }

  func testAnEntryWithACopyAndNoAdsIsReadAndKept() throws {
    let read = try XCTUnwrap(entry(copy: aCopy(), ads: []))
    XCTAssertEqual(read.ads, [])
    XCTAssertNotNil(read.copy)
    let file = AheadFile(episodes: [read])
    XCTAssertNotNil(
      file.entry(guid: "g1", feed: "https://show.test/rss", title: "x", now: now),
      "the entry says the episode has no ads")
  }

  func testAnEntryWithNoCopyAndNoAdsIsStillNotFound() throws {
    let read = try XCTUnwrap(entry(copy: nil, ads: []))
    XCTAssertNil(
      AheadFile(episodes: [read]).entry(
        guid: "g1", feed: "https://show.test/rss", title: "x", now: now))
  }

  func testTheFileStaysVersionOneAndAnEntryWithoutACopyEncodesAsBefore() throws {
    let plain = try XCTUnwrap(entry(copy: nil))
    let data = try XCTUnwrap(AheadFile(episodes: [plain]).encoded())
    let text = String(decoding: data, as: UTF8.self)
    XCTAssertFalse(text.contains("copy"))
    XCTAssertTrue(text.contains(#""version":1"#))
    var carried = plain
    carried.copy = PreparedCopy(file: "prepared/a.mp3", sha256: goodSha, bytes: 7)
    let again = AheadFile(data: try XCTUnwrap(AheadFile(episodes: [carried]).encoded()))
    XCTAssertEqual(again.episodes.first?.copy, carried.copy)
  }
}
