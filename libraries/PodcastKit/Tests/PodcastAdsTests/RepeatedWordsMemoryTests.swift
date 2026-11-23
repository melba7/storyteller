import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// What the memory keeps (three episodes a show, 60 shows, a byte cap), how a damaged file reads,
/// what a "not an ad" answer remembers, and that bad input never traps.
final class RepeatedWordsMemoryTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private let day = 86_400.0

  private func talkLines(_ tag: String, words: Int = 200) -> [TranscriptLine] {
    Speech.lines(Speech.talk(words, tag: tag))
  }

  private func remember(
    _ memory: inout RepeatedWords, show: String = "show", episode: String, words: Int = 200
  ) {
    memory.remember(show: show, episode: episode, lines: talkLines(episode, words: words), now: now)
  }

  // MARK: Limits and pruning

  func testTheNewestThreeEpisodesOfAShowAreKept() {
    var memory = RepeatedWords()
    for id in ["e1", "e2", "e3", "e4"] { remember(&memory, episode: id) }
    XCTAssertEqual(memory.shows.count, 1)
    XCTAssertEqual(memory.shows[0].episodes.map(\.id), ["e2", "e3", "e4"])
    // A new episode has a piece of the first episode and a piece of the second, both after the
    // first minute. Only the second is found: the first episode's words are gone.
    let fromFirst = Array(Speech.talk(200, tag: "e1")[50..<110])
    let fromSecond = Array(Speech.talk(200, tag: "e2")[50..<110])
    let new = Speech.episode(
      tag: "fresh", total: 800, plugs: [(300, fromFirst), (500, fromSecond)])
    let found = memory.find(
      show: "show", episode: "e5", lines: Speech.lines(new), duration: 400, now: now)
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found.first?.start ?? 0, Speech.time(ofWord: 500), accuracy: 5)
  }

  func testAnEpisodeAskedTwiceIsStoredOnce() {
    var memory = RepeatedWords()
    remember(&memory, episode: "e1")
    let once = memory
    remember(&memory, episode: "e1")
    XCTAssertEqual(memory, once)
    XCTAssertEqual(memory.shows[0].episodes.count, 1)
  }

  func testSixtyShowsAreKeptAndTheOneIdleLongestGoesFirst() {
    var memory = RepeatedWords()
    for n in 0..<RepeatedWords.mostShows { remember(&memory, show: "show\(n)", episode: "e") }
    XCTAssertEqual(memory.shows.count, 60)
    // Hearing show0 again makes it the newest.
    remember(&memory, show: "show0", episode: "e2")
    remember(&memory, show: "show60", episode: "e")
    XCTAssertEqual(memory.shows.count, 60)
    XCTAssertTrue(memory.shows.contains { $0.id == "show0" })
    XCTAssertFalse(memory.shows.contains { $0.id == "show1" })
    XCTAssertEqual(memory.shows.last?.id, "show60")
  }

  func testTheCapOnHashesDropsTheShowsIdleLongestAndNeverTheNewest() {
    var memory = RepeatedWords()
    for n in 0..<5 { remember(&memory, show: "show\(n)", episode: "e") }
    let one = memory.shows[0].episodes[0].hashes.count / 4
    XCTAssertEqual(one, 196)
    memory.trim(toHashes: 3 * one + 5)
    XCTAssertEqual(memory.shows.map(\.id), ["show2", "show3", "show4"])
    memory.trim(toHashes: 10)
    XCTAssertEqual(memory.shows.map(\.id), ["show4"])
  }

  func testTheWorstCaseFileFitsItsByteBudget() {
    // The accounting in RepeatedWords.swift: 60 shows of three episodes with 6,666 hashes each
    // (1,199,880, under the cap of 1,200,000), five "not an ad" stretches a show, names of 80
    // letters.
    var bytes = FixedBytes(seed: 7)
    let episodeHashes = bytes.data(count: 4 * 6_666)
    let samples = bytes.data(count: 4 * RepeatedWords.deniedSamples)
    var memory = RepeatedWords()
    for n in 0..<RepeatedWords.mostShows {
      let name = String(repeating: "s", count: 78) + String(format: "%02d", n)
      let episodes = (0..<RepeatedWords.mostEpisodes).map {
        RepeatedWords.Episode(id: String(repeating: "e", count: 79) + "\($0)", hashes: episodeHashes)
      }
      let denied = (0..<RepeatedWords.mostDenied).map {
        RepeatedWords.Denied(at: 1_800_000_000 + $0, hashes: samples)
      }
      memory.shows.append(RepeatedWords.Show(id: name, episodes: episodes, denied: denied))
    }
    XCTAssertEqual(memory.hashCount, 1_199_880)
    XCTAssertLessThanOrEqual(memory.hashCount, RepeatedWords.mostHashesInAll)
    let data = memory.data
    // The accounting in RepeatedWords.swift says 6,594,383 bytes.
    XCTAssertGreaterThan(data.count, 6_500_000)
    XCTAssertLessThan(data.count, 6_700_000)
    XCTAssertLessThan(data.count, RepeatedWords.maxFileBytes)
    XCTAssertEqual(RepeatedWords.read(data), memory)
  }

  func testAnEpisodeWithTooFewWordsIsNotStored() {
    var memory = RepeatedWords()
    remember(&memory, episode: "short", words: 20)
    remember(&memory, episode: "none", words: 0)
    XCTAssertEqual(memory, RepeatedWords())
  }

  func testAHugeTranscriptIsCutAtTheWordLimit() {
    var memory = RepeatedWords()
    remember(&memory, episode: "long", words: RepeatedWords.mostWords + 5_000)
    let stored = (memory.shows.first?.episodes.first?.hashes.count ?? 0) / 4
    XCTAssertEqual(stored, RepeatedWords.mostWords - 4)
  }

  // MARK: Damaged files

  func testAnyDamagedFileReadsAsEmpty() {
    var memory = RepeatedWords()
    remember(&memory, episode: "e1")
    let good = memory.data
    XCTAssertEqual(RepeatedWords.read(good), memory)
    XCTAssertEqual(RepeatedWords.read(Data()), RepeatedWords())
    XCTAssertEqual(RepeatedWords.read(Data("not json at all".utf8)), RepeatedWords())
    XCTAssertEqual(RepeatedWords.read(good.prefix(good.count / 2)), RepeatedWords())
    XCTAssertEqual(RepeatedWords.read(Data("[]".utf8)), RepeatedWords())
    XCTAssertEqual(RepeatedWords.read(Data("{\"version\":1}".utf8)), RepeatedWords())
    // Another version.
    let text = String(decoding: good, as: UTF8.self)
    XCTAssertTrue(text.contains("\"version\":1"))
    for other in ["2", "0", "-1"] {
      let changed = text.replacingOccurrences(of: "\"version\":1", with: "\"version\":\(other)")
      XCTAssertEqual(RepeatedWords.read(Data(changed.utf8)), RepeatedWords(), other)
    }
  }

  func testAFileWithHashesOfTheWrongSizeReadsAsEmpty() {
    var memory = RepeatedWords()
    memory.shows = [
      RepeatedWords.Show(
        id: "s", episodes: [RepeatedWords.Episode(id: "e", hashes: Data([1, 2, 3, 4, 5]))], denied: [])
    ]
    XCTAssertEqual(RepeatedWords.read(memory.data), RepeatedWords())
  }

  func testAFileOverItsCapsReadsAsEmpty() {
    XCTAssertEqual(
      RepeatedWords.read(Data(repeating: 0x20, count: RepeatedWords.maxFileBytes + 1)),
      RepeatedWords())
    // Too many shows, too many episodes, a show listed twice, too many hashes in all.
    var memory = RepeatedWords()
    let hashes = Data(count: 4 * 30)
    func show(_ id: String, episodes: Int = 1) -> RepeatedWords.Show {
      RepeatedWords.Show(
        id: id,
        episodes: (0..<episodes).map { RepeatedWords.Episode(id: "e\($0)", hashes: hashes) },
        denied: [])
    }
    memory.shows = (0...RepeatedWords.mostShows).map { show("s\($0)") }
    XCTAssertEqual(RepeatedWords.read(memory.data), RepeatedWords())
    memory.shows = [show("s", episodes: RepeatedWords.mostEpisodes + 1)]
    XCTAssertEqual(RepeatedWords.read(memory.data), RepeatedWords())
    memory.shows = [show("s"), show("s")]
    XCTAssertEqual(RepeatedWords.read(memory.data), RepeatedWords())
    memory.shows = [show("s", episodes: RepeatedWords.mostEpisodes)]
    memory.shows[0].episodes[0].hashes = Data(count: 4 * (RepeatedWords.mostWords + 1))
    XCTAssertEqual(RepeatedWords.read(memory.data), RepeatedWords())
    memory.shows = (0..<RepeatedWords.mostShows).map { n in
      RepeatedWords.Show(
        id: "s\(n)",
        episodes: (0..<RepeatedWords.mostEpisodes).map {
          RepeatedWords.Episode(id: "e\($0)", hashes: Data(count: 4 * 6_667))
        }, denied: [])
    }
    XCTAssertEqual(memory.hashCount, 1_200_060)
    XCTAssertEqual(RepeatedWords.read(memory.data), RepeatedWords())
    // A file at the limits reads.
    memory.shows = (0..<RepeatedWords.mostShows).map { show("s\($0)", episodes: 3) }
    XCTAssertEqual(RepeatedWords.read(memory.data), memory)
  }

  // MARK: "Not an ad"

  /// An older episode with two standing passages, and the new episode that has them both.
  private func twoPassages() -> (old: [String], new: [String]) {
    let first = Speech.plug(60, tag: "first")
    let second = Speech.plug(60, tag: "second")
    return (
      Speech.episode(tag: "old", total: 1600, plugs: [(400, first), (1000, second)]),
      Speech.episode(tag: "new", total: 1600, plugs: [(900, first), (300, second)])
    )
  }

  func testDenyStopsTheSameStretchComingBack() {
    let (old, new) = twoPassages()
    var memory = RepeatedWords()
    memory.remember(show: "show", episode: "old", lines: Speech.lines(old), now: now)
    let lines = Speech.lines(new)
    let found = memory.find(show: "show", episode: "new", lines: lines, duration: 800, now: now)
    XCTAssertEqual(found.count, 2)
    // The listener says the passage at 150 seconds (the "second" one) is not an ad.
    guard let denied = found.first(where: { $0.start < 200 }) else { return XCTFail("\(found)") }
    memory.deny(show: "show", lines: lines, start: denied.start, end: denied.end, now: now)
    memory.remember(show: "show", episode: "new", lines: lines, now: now)
    // A later episode has the same two passages: only the other one is offered.
    let later = Speech.episode(
      tag: "later", total: 1600,
      plugs: [(500, Speech.plug(60, tag: "first")), (1200, Speech.plug(60, tag: "second"))])
    let again = memory.find(
      show: "show", episode: "later", lines: Speech.lines(later), duration: 800, now: now)
    XCTAssertEqual(again.count, 1)
    XCTAssertEqual(again.first?.start ?? 0, Speech.time(ofWord: 500), accuracy: 5)
  }

  func testDenyKeepsOnlyAFewHashes() {
    let (old, new) = twoPassages()
    var memory = RepeatedWords()
    memory.remember(show: "show", episode: "old", lines: Speech.lines(old), now: now)
    memory.deny(show: "show", lines: Speech.lines(new), start: 450, end: 480, now: now)
    XCTAssertEqual(memory.shows[0].denied.count, 1)
    let kept = memory.shows[0].denied[0].hashes.count / 4
    XCTAssertGreaterThan(kept, 0)
    XCTAssertLessThanOrEqual(kept, RepeatedWords.deniedSamples)
    XCTAssertFalse(String(decoding: memory.data, as: UTF8.self).contains("first"))
  }

  func testTheSameDenialTwiceIsKeptOnceAndOnlyTheNewestFiveStay() {
    var memory = RepeatedWords()
    let words = Speech.talk(4000, tag: "talk")
    let lines = Speech.lines(words)
    memory.deny(show: "show", lines: lines, start: 100, end: 130, now: now)
    memory.deny(show: "show", lines: lines, start: 100, end: 130, now: now)
    XCTAssertEqual(memory.shows[0].denied.count, 1)
    for n in 1...8 {
      let from = 100 + Double(n) * 100
      memory.deny(show: "show", lines: lines, start: from, end: from + 30, now: now)
    }
    XCTAssertEqual(memory.shows[0].denied.count, RepeatedWords.mostDenied)
    XCTAssertEqual(memory.shows[0].denied.count, 5)
    XCTAssertEqual(memory.shows.count, 1)
  }

  func testADenialIsForgottenAfterSixtyDays() {
    let (old, new) = twoPassages()
    var memory = RepeatedWords()
    memory.remember(show: "show", episode: "old", lines: Speech.lines(old), now: now)
    let lines = Speech.lines(new)
    let found = memory.find(show: "show", episode: "new", lines: lines, duration: 800, now: now)
    for ad in found {
      memory.deny(show: "show", lines: lines, start: ad.start, end: ad.end, now: now)
    }
    XCTAssertEqual(
      memory.find(show: "show", episode: "new2", lines: lines, duration: 800, now: now), [])
    let later = now.addingTimeInterval(61 * day)
    XCTAssertEqual(
      memory.find(show: "show", episode: "new2", lines: lines, duration: 800, now: later).count, 2)
    // And the next episode that is remembered clears the old denials from the file.
    memory.remember(show: "show", episode: "new3", lines: talkLines("other"), now: later)
    XCTAssertEqual(memory.shows[0].denied, [])
  }

  func testDenyIgnoresWhatIsNotAStretch() {
    var memory = RepeatedWords()
    let lines = talkLines("x", words: 400)
    let before = memory
    memory.deny(show: "show", lines: lines, start: 50, end: 40, now: now)
    memory.deny(show: "show", lines: lines, start: .nan, end: 40, now: now)
    memory.deny(show: "show", lines: lines, start: 0, end: .infinity, now: now)
    memory.deny(show: "show", lines: [], start: 0, end: 100, now: now)
    memory.deny(show: "show", lines: lines, start: 10, end: 12, now: now)
    memory.deny(show: "", lines: lines, start: 0, end: 100, now: now)
    XCTAssertEqual(memory, before)
  }
}
