import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// Bad input must never trap, and a long transcript must not make the work grow past what it
/// needs: one pass to hash each run, one dictionary, no scan of every pair.
final class RepeatedWordsRobustTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func line(_ start: Double, _ end: Double, _ text: String) -> TranscriptLine {
    TranscriptLine(start: start, end: end, text: text)
  }

  private func remembered(_ words: [String]) -> RepeatedWords {
    var memory = RepeatedWords()
    memory.remember(show: "show", episode: "old", lines: Speech.lines(words), now: now)
    return memory
  }

  func testNothingToWorkWithGivesNothing() {
    let memory = remembered(Speech.episode(tag: "old", total: 1200, plugs: [(400, Speech.plug(40))]))
    func find(_ lines: [TranscriptLine], duration: Double = 600) -> [FoundAd] {
      memory.find(show: "show", episode: "new", lines: lines, duration: duration, now: now)
    }
    XCTAssertEqual(find([]), [])
    XCTAssertEqual(find([line(0, 0, "")]), [])
    XCTAssertEqual(find([line(0, 10, "   \n  ")]), [])
    XCTAssertEqual(find([line(0, 10, "just one short line")]), [])
    // The memory is empty, or the show is not known, or the names are empty.
    let talk = Speech.lines(Speech.talk(100, tag: "x"))
    XCTAssertEqual(
      RepeatedWords().find(show: "show", episode: "new", lines: talk, duration: 50, now: now), [])
    XCTAssertEqual(
      memory.find(show: "", episode: "", lines: talk, duration: 50, now: now), [])
  }

  func testStrangeTimesNeverTrap() {
    let memory = remembered(Speech.episode(tag: "old", total: 1200, plugs: [(400, Speech.plug(40))]))
    let words = Speech.episode(tag: "new", total: 1200, plugs: [(900, Speech.plug(40))])
    let good = Speech.lines(words)
    let strange: [TranscriptLine] = [
      line(.nan, 5, "not a number"), line(5, .nan, "also not"), line(.infinity, .infinity, "far"),
      line(-.infinity, 3, "behind"), line(10, 2, "backwards line of words here"),
      line(-50, -40, "before the start of the episode"),
      line(1e300, 1e301, "huge times in this line of words"),
    ]
    let found = memory.find(
      show: "show", episode: "new", lines: strange + good + strange, duration: 600, now: now)
    XCTAssertEqual(found.count, 1)
    for duration in [0, -5, .nan, .infinity, -.infinity, 1e300, 1] {
      let result = memory.find(
        show: "show", episode: "new", lines: good, duration: duration, now: now)
      XCTAssertLessThanOrEqual(result.count, 1)
      for ad in result {
        XCTAssertTrue(ad.start.isFinite && ad.end.isFinite && ad.end > ad.start, "\(ad)")
      }
    }
    // A duration that is not known leaves the end to the words; one that is known cuts it.
    let unknown = memory.find(show: "show", episode: "new", lines: good, duration: 0, now: now)
    XCTAssertEqual(unknown.count, 1)
    let cut = memory.find(show: "show", episode: "new", lines: good, duration: 455, now: now)
    XCTAssertEqual(cut, [], "the stretch would be under 15 seconds inside the duration")
    var again = memory
    again.remember(show: "show", episode: "x", lines: strange, now: .init(timeIntervalSince1970: .nan))
    again.deny(show: "show", lines: good, start: 450, end: 470, now: .init(timeIntervalSince1970: .infinity))
    let wild = Date(timeIntervalSince1970: .nan)
    XCTAssertEqual(
      memory.find(show: "show", episode: "new", lines: good, duration: 600, now: wild).count, 1)
    // A clock that is not a number cannot expire a denial, and must not trap.
    _ = again.find(show: "show", episode: "new", lines: good, duration: 600, now: wild)
  }

  func testAnEpisodeOfOneLongLineIsStillFound() {
    let old = Speech.episode(tag: "old", total: 1200, plugs: [(400, Speech.plug(40))])
    let memory = remembered(old)
    let new = Speech.episode(tag: "new", total: 1200, plugs: [(900, Speech.plug(40))])
    let one = [line(0, 600, new.joined(separator: " "))]
    let found = memory.find(show: "show", episode: "new", lines: one, duration: 600, now: now)
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found.first?.start ?? 0, Speech.time(ofWord: 900), accuracy: 5)
  }

  func testOneRepeatedWordGivesNothingAndIsQuick() {
    let um = [String](repeating: "um", count: 70_000)
    let memory = remembered(um)
    let started = Date()
    let found = memory.find(
      show: "show", episode: "new", lines: Speech.lines(um), duration: 35_000, now: now)
    XCTAssertEqual(found, [])
    XCTAssertLessThan(Date().timeIntervalSince(started), 20)
  }

  func testAThreeHourEpisodeIsWorkedInBoundedTime() {
    // Three hours at 0.4 seconds a word: 27,000 words. Each earlier episode has three standing
    // passages; the new one has them in other places.
    let step = 0.4
    func passages(_ at: [Int]) -> [(at: Int, words: [String])] {
      zip(at, ["intro", "mid", "outro"]).map { (at: $0, words: Speech.plug(90, tag: $1)) }
    }
    var memory = RepeatedWords()
    for (n, at) in [[1500, 12_000, 25_000], [3000, 9000, 20_000]].enumerated() {
      let words = Speech.episode(tag: "old\(n)x", total: 27_000, plugs: passages(at))
      memory.remember(
        show: "show", episode: "old\(n)", lines: Speech.lines(words, perLine: 12, step: step),
        now: now)
    }
    let new = Speech.episode(tag: "newx", total: 27_000, plugs: passages([2000, 14_000, 22_000]))
    let lines = Speech.lines(new, perLine: 12, step: step)
    let started = Date()
    let found = memory.find(
      show: "show", episode: "new", lines: lines, duration: 10_800, now: now)
    memory.remember(show: "show", episode: "new", lines: lines, now: now)
    let seconds = Date().timeIntervalSince(started)
    // The bound is generous: this runs in a debug build on a shared machine.
    XCTAssertLessThan(seconds, 20, "took \(seconds) seconds")
    XCTAssertEqual(found.count, 3)
    for (ad, truth) in zip(found, [800.0, 5600, 8800]) {
      XCTAssertEqual(ad.start, truth, accuracy: 6)
    }
  }
}
