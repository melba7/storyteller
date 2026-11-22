import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// Writes files of a made-up teaching folder.
struct FolderWriter {
  let url: URL

  init() throws {
    url = FileManager.default.temporaryDirectory.appendingPathComponent("teach-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  func write(_ name: String, _ text: String) throws {
    let file = url.appendingPathComponent(name)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: file)
  }

  func remove() { try? FileManager.default.removeItem(at: url) }
}

/// A label with the given segments.
func labelJSON(_ segments: String) -> String {
  "{\"version\": 1, \"episode\": \"x\", \"feed\": \"f\", \"show\": \"s\", \"lines\": 3, \"length\": 20, \"segments\": [\(segments)]}"
}

func segmentJSON(start: String, end: String, sort: String = "sponsor", confidence: String = "high") -> String {
  "{\"first\": 1, \"last\": 2, \"start\": \(start), \"end\": \(end), \"sort\": \"\(sort)\", \"who\": \"\", \"delivery\": \"host\", \"confidence\": \"\(confidence)\", \"why\": \"\"}"
}

let sampleText = "[0:00:00.0] hello and welcome\n[0:00:10.5] this is a sponsor read\n[0:01:00.0] back to the show\n"

final class TeachingFolderTests: XCTestCase {
  func testTranscriptTimesAndEnds() {
    let transcript = TeachingFolder.transcript(fromText: sampleText, duration: 90)
    XCTAssertEqual(transcript.lines.map(\.start), [0, 10.5, 60])
    XCTAssertEqual(transcript.lines.map(\.end), [10.5, 60, 90])
    XCTAssertEqual(transcript.duration, 90)
  }

  func testLastLineEndsFiveSecondsAfterItsStartWhenTheLengthIsUnknownOrEarlier() {
    XCTAssertEqual(TeachingFolder.transcript(fromText: sampleText, duration: nil).lines.last?.end, 65)
    let early = TeachingFolder.transcript(fromText: sampleText, duration: 30)
    XCTAssertEqual(early.lines.last?.end, 65)
    XCTAssertEqual(early.duration, 65)
    XCTAssertEqual(TeachingFolder.transcript(fromText: sampleText, duration: nil).duration, 65)
  }

  func testWordsAreSpreadEvenlyOverTheLine() {
    let transcript = TeachingFolder.transcript(
      fromText: "[0:00:10.0] one two three four\n[0:00:20.0] five", duration: 30)
    let first = transcript.words.prefix(4)
    XCTAssertEqual(first.map(\.text), ["one", "two", "three", "four"])
    XCTAssertEqual(first.map(\.start), [10, 12.5, 15, 17.5])
    XCTAssertEqual(first.last?.end, 20)
    XCTAssertEqual(transcript.words.last, TranscriptWord(text: "five", start: 20, end: 30))
  }

  func testLinesThatDoNotMatchAreSkipped() {
    let text = "title line\n[0:00:05.0] first\n[bad] nope\n[0:00:07.0]   \n\n[1:02:03.5] last words"
    let transcript = TeachingFolder.transcript(fromText: text, duration: nil)
    XCTAssertEqual(transcript.lines.map(\.text), ["first", "last words"])
    XCTAssertEqual(transcript.lines.last?.start, 3723.5)
    XCTAssertEqual(TeachingFolder.transcript(fromText: "", duration: nil).lines, [])
  }

  private func fill(_ folder: FolderWriter) throws {
    try folder.write(
      "episodes.json",
      """
      {"version": 1, "episodes": [
        {"id": "b", "feed": "f1", "show": "One", "title": "B"},
        {"id": "a", "feed": "f2", "show": "Two", "title": "A"},
        {"id": "nolabel", "feed": "f2", "show": "Two", "title": "N"},
        {"id": "badlabel", "feed": "f2", "show": "Two", "title": "Bad"},
        {"title": "no id"}
      ]}
      """)
    for id in ["b", "a", "nolabel", "badlabel"] { try folder.write("transcripts/\(id).txt", sampleText) }
    try folder.write(
      "labels/b.json",
      labelJSON(
        [
          segmentJSON(start: "5", end: "10"),
          segmentJSON(start: "20", end: "30", sort: "host_ask", confidence: "medium"),
          segmentJSON(start: "40", end: "50", confidence: "low"),
          segmentJSON(start: "50", end: "50"),
          segmentJSON(start: "\"x\"", end: "60"),
          segmentJSON(start: "true", end: "60"),
          segmentJSON(start: "1", end: "9", sort: "unknown"),
        ].joined(separator: ",")))
    try folder.write("labels/a.json", labelJSON(""))
    try folder.write("labels/badlabel.json", "not json")
    try folder.write("shelf.json", "{\"version\": 1, \"episodes\": [\"a\"]}")
  }

  func testEpisodesInOrderWithShelfAndConfidence() throws {
    let folder = try FolderWriter()
    defer { folder.remove() }
    try fill(folder)
    var notes: [String] = []
    let episodes = try TeachingFolder.episodes(in: folder.url, notes: &notes)
    XCTAssertEqual(episodes.map(\.id), ["b", "a"])
    XCTAssertEqual(episodes.map(\.onShelf), [false, true])
    XCTAssertEqual(episodes[0].feed, "f1")
    XCTAssertEqual(episodes[0].show, "One")
    XCTAssertEqual(
      episodes[0].truth,
      [
        TeachingTruth(start: 5, end: 10, sort: "sponsor"),
        TeachingTruth(start: 20, end: 30, sort: "host_ask"),
      ])
    XCTAssertEqual(episodes[0].maybe, [TeachingTruth(start: 40, end: 50, sort: "sponsor")])
    XCTAssertEqual(episodes[1].truth, [])
    XCTAssertEqual(episodes[0].transcript.lines.count, 3)
  }

  func testUnreadableFilesAreNotedAndSkipped() throws {
    let folder = try FolderWriter()
    defer { folder.remove() }
    try fill(folder)
    var notes: [String] = []
    _ = try TeachingFolder.episodes(in: folder.url, notes: &notes)
    XCTAssertEqual(notes.count, 2)
    XCTAssertTrue(notes.contains { $0.contains("badlabel") })
    XCTAssertTrue(notes.contains { $0.contains("no usable id") })
  }

  func testAnOtherLabelsFolderIsRead() throws {
    let folder = try FolderWriter()
    defer { folder.remove() }
    try fill(folder)
    try folder.write("second/b.json", labelJSON(segmentJSON(start: "1", end: "2")))
    var notes: [String] = []
    let episodes = try TeachingFolder.episodes(in: folder.url, labels: "second", notes: &notes)
    XCTAssertEqual(episodes.map(\.id), ["b"])
  }

  func testMissingOrWrongEpisodesFileThrows() throws {
    let folder = try FolderWriter()
    defer { folder.remove() }
    var notes: [String] = []
    XCTAssertThrowsError(try TeachingFolder.episodes(in: folder.url, notes: &notes)) {
      XCTAssertTrue($0.localizedDescription.contains("episodes.json"))
    }
    try folder.write("episodes.json", "[1, 2]")
    XCTAssertThrowsError(try TeachingFolder.episodes(in: folder.url, notes: &notes)) {
      XCTAssertTrue($0.localizedDescription.contains("expected shape"))
    }
  }

  func testLibraryUsesTheFeedAsTheShow() throws {
    let folder = try FolderWriter()
    defer { folder.remove() }
    XCTAssertEqual(TeachingFolder.library(in: folder.url, now: Date()).ads.count, 0)
    let text = (0..<40).map { "word\($0)" }.joined(separator: " ")
    try folder.write(
      "ad-library.json",
      """
      {"version": 1, "ads": [
        {"feed": "https://x/feed", "scope": "show", "sort": "sponsor", "who": "Acme", "text": "\(text)", "length": 30, "seen": 3},
        {"feed": "https://x/feed", "scope": "all", "sort": "bogus", "who": "", "text": "\(text)", "length": 30, "seen": 1},
        "junk"
      ]}
      """)
    let known = TeachingFolder.library(in: folder.url, now: Date())
    XCTAssertEqual(known.ads.count, 1)
    XCTAssertEqual(known.ads[0].showId, "https://x/feed")
    XCTAssertEqual(known.ads[0].kind, .ad)
    XCTAssertEqual(known.ads[0].seen, 3)
  }

  func testHabitsUseTheFeedAsTheShowId() throws {
    let folder = try FolderWriter()
    defer { folder.remove() }
    XCTAssertEqual(TeachingFolder.habits(in: folder.url).shows.count, 0)
    try folder.write(
      "habits.json",
      """
      {"version": 1, "shows": [
        {"feed": "f1", "title": "One", "episodes": 5, "opensWithAd": 5, "openingStarts": 2.0, "openingEnds": 40.0, "breaks": 2, "adSeconds": 90},
        {"feed": "f2", "title": "Two", "episodes": 5, "opensWithAd": 0, "openingStarts": null, "openingEnds": null, "breaks": 1, "adSeconds": 30},
        {"title": "no feed"}
      ]}
      """)
    let habits = TeachingFolder.habits(in: folder.url)
    XCTAssertEqual(habits.shows.count, 2)
    XCTAssertTrue(habits.usuallyOpensWithAd(show: "f1"))
    XCTAssertEqual(habits.openingEnd(show: "f1"), 40)
    XCTAssertTrue(habits.startsClean(show: "f2"))
  }
}
