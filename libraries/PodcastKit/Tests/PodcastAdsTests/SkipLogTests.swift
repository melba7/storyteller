import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// The skip log: how each skip ended (N8). The watch is the rules, the log is the file's text.
final class SkipLogTests: XCTestCase {
  private func ad(_ start: Double, _ end: Double) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "Acme", confidence: .sure, firstWords: "x")
  }

  private func context(
    _ episode: String = "ep1", time: Double = 1_800_000_000, source: SkipSource? = .model,
    tap: Double? = nil
  ) -> SkipContext {
    SkipContext(time: time, episode: episode, show: "show1", source: source, tapToSkip: tap)
  }

  /// A skipper that has just skipped `ads` at `now` 100, and the skip it made.
  private func skipped(_ ads: [FoundAd]) -> (AdSkipper, AdSkip) {
    let file = AdsFile(
      sha256: "aa", detector: "fake", detectorVersion: "1", osVersion: "26.0", duration: 1000,
      ads: ads)
    var skipper = AdSkipper(file: file, settings: AdSkipSettings())
    let skip = skipper.reached(position: ads[0].start + 0.1, rate: 1, duration: 1000, now: 100)!
    return (skipper, skip)
  }

  // MARK: How a skip ends

  func testASkipThenABackSeekFiveSecondsLaterIsTrimmedByTen() throws {
    let (made, skip) = skipped([ad(60, 120)])
    var skipper = made
    var watch = SkipWatch()
    XCTAssertEqual(watch.skipped(skip, context: context(tap: 2.5), now: 100), [])
    let trim = try XCTUnwrap(skipper.backSeek(to: 110, now: 105))
    let done = watch.trimmed(trim)
    XCTAssertEqual(done.count, 1)
    let entry = try XCTUnwrap(done.first)
    XCTAssertEqual(entry.result, .trimmed(seconds: 10))
    XCTAssertEqual([entry.start, entry.end], [60, 120])
    XCTAssertEqual(entry.kind, .ad)
    XCTAssertEqual(entry.confidence, .sure)
    XCTAssertEqual(entry.source, .model)
    XCTAssertEqual(entry.tapToSkip, 2.5)
    XCTAssertEqual([entry.episode, entry.show], ["ep1", "show1"])
    XCTAssertEqual(entry.time, 1_800_000_000)
  }

  func testNoEventInTwentySecondsIsKeptOnce() {
    let (_, skip) = skipped([ad(60, 120)])
    var watch = SkipWatch()
    _ = watch.skipped(skip, context: context(), now: 100)
    XCTAssertEqual(watch.settle(now: 119.5), [])
    XCTAssertEqual(watch.settle(now: 120.5).map(\.result), [.kept])
    XCTAssertEqual(watch.settle(now: 200), [])
  }

  func testTheNextSkipEndsTheLastOneAsKept() {
    let (_, first) = skipped([ad(60, 120)])
    let (_, second) = skipped([ad(300, 360)])
    var watch = SkipWatch()
    _ = watch.skipped(first, context: context("ep1"), now: 100)
    let done = watch.skipped(second, context: context("ep1"), now: 112)
    XCTAssertEqual(done.map(\.result), [.kept])
    XCTAssertEqual(done.first?.start, 60)
    XCTAssertEqual(watch.settle(now: 140).first?.start, 300)
  }

  func testUndoIsUndoneAndItsOwnSeekBackIsNothing() {
    let (_, skip) = skipped([ad(60, 120)])
    var watch = SkipWatch()
    _ = watch.skipped(skip, context: context(), now: 100)
    XCTAssertEqual(watch.undone().map(\.result), [.undone])
    let seek = watch.seeked(
      from: 124, to: 60, knownAds: [ad(60, 120)], context: context(), now: 103)
    XCTAssertEqual(seek, [])
    XCTAssertEqual(watch.settle(now: 200), [])
    XCTAssertEqual(watch.undone(), [])
  }

  func testASeekBackThatIsNotATrimIsASeekBackBySeconds() {
    let (_, skip) = skipped([ad(60, 120)])
    var watch = SkipWatch()
    _ = watch.skipped(skip, context: context(), now: 100)
    let done = watch.seeked(from: 125, to: 40, knownAds: [], context: context(), now: 105)
    XCTAssertEqual(done.map(\.result), [.seekBack(seconds: 85)])
  }

  func testASeekBackAfterTheLandingIsNotAboutTheSkip() {
    let (_, skip) = skipped([ad(60, 120)])
    var watch = SkipWatch()
    _ = watch.skipped(skip, context: context(), now: 100)
    XCTAssertEqual(
      watch.seeked(from: 140, to: 130, knownAds: [], context: context(), now: 108), [])
    XCTAssertEqual(watch.settle(now: 125).map(\.result), [.kept])
  }

  func testASeekBackLaterThanTwentySecondsKeepsTheSkip() {
    let (_, skip) = skipped([ad(60, 120)])
    var watch = SkipWatch()
    _ = watch.skipped(skip, context: context(), now: 100)
    let done = watch.seeked(from: 160, to: 100, knownAds: [], context: context(), now: 130)
    XCTAssertEqual(done.map(\.result), [.kept])
  }

  func testATrimWithNothingPendingIsNothing() {
    var watch = SkipWatch()
    XCTAssertEqual(watch.trimmed(AdTrim(adStart: 60, end: 110)), [])
  }

  // MARK: Jumps that may mean a missed ad

  private func jump(
    _ watch: inout SkipWatch, from: Double, by amount: Double, at now: Double,
    known: [FoundAd] = [], episode: String = "ep1"
  ) -> [SkipLogEntry] {
    watch.seeked(
      from: from, to: from + amount, knownAds: known, context: context(episode), now: now)
  }

  func testThreeForwardJumpsInFortySecondsAreOneMaybeMissed() throws {
    var watch = SkipWatch()
    XCTAssertEqual(jump(&watch, from: 100, by: 30, at: 0), [])
    XCTAssertEqual(jump(&watch, from: 140, by: 30, at: 20), [])
    let done = jump(&watch, from: 180, by: 30, at: 40)
    XCTAssertEqual(done.count, 1)
    let entry = try XCTUnwrap(done.first)
    XCTAssertEqual(entry.result, .maybeMissed)
    XCTAssertEqual([entry.start, entry.end], [100, 210])
    XCTAssertNil(entry.kind)
    XCTAssertNil(entry.confidence)
    XCTAssertEqual(entry.episode, "ep1")
  }

  func testTheCountStartsAgainAfterAMaybeMissed() {
    var watch = SkipWatch()
    for step in 0..<3 { _ = jump(&watch, from: 100 + 40 * Double(step), by: 30, at: 20 * Double(step)) }
    XCTAssertEqual(jump(&watch, from: 300, by: 30, at: 61), [])
    XCTAssertEqual(jump(&watch, from: 340, by: 30, at: 70), [])
    XCTAssertEqual(jump(&watch, from: 380, by: 30, at: 80).map(\.result), [.maybeMissed])
  }

  func testTwoJumpsAreNotEnough() {
    var watch = SkipWatch()
    XCTAssertEqual(jump(&watch, from: 100, by: 30, at: 0), [])
    XCTAssertEqual(jump(&watch, from: 140, by: 30, at: 20), [])
  }

  func testJumpsMoreThanSixtySecondsApartDoNotAdd() {
    var watch = SkipWatch()
    XCTAssertEqual(jump(&watch, from: 100, by: 30, at: 0), [])
    XCTAssertEqual(jump(&watch, from: 140, by: 30, at: 40), [])
    XCTAssertEqual(jump(&watch, from: 180, by: 30, at: 70), [])
  }

  func testJumpsFromInsideAKnownAdDoNotCount() {
    var watch = SkipWatch()
    let known = [ad(90, 400)]
    for step in 0..<4 {
      XCTAssertEqual(
        jump(&watch, from: 100 + 40 * Double(step), by: 30, at: 10 * Double(step), known: known), [])
    }
  }

  func testSmallAndHugeJumpsAndBackSeeksDoNotCount() {
    var watch = SkipWatch()
    XCTAssertEqual(jump(&watch, from: 100, by: 5, at: 0), [])
    XCTAssertEqual(jump(&watch, from: 100, by: 600, at: 5), [])
    XCTAssertEqual(jump(&watch, from: 100, by: -30, at: 10), [])
    XCTAssertEqual(jump(&watch, from: 100, by: 30, at: 15), [])
    XCTAssertEqual(jump(&watch, from: 100, by: 30, at: 20), [])
  }

  func testJumpsInTwoEpisodesDoNotAdd() {
    var watch = SkipWatch()
    XCTAssertEqual(jump(&watch, from: 100, by: 30, at: 0, episode: "ep1"), [])
    XCTAssertEqual(jump(&watch, from: 140, by: 30, at: 10, episode: "ep2"), [])
    XCTAssertEqual(jump(&watch, from: 180, by: 30, at: 20, episode: "ep2"), [])
  }

  // MARK: The words around an edge

  private func words(_ count: Int, step: Double = 1) -> [TranscriptWord] {
    (0..<count).map {
      TranscriptWord(text: "w\($0)", start: Double($0) * step, end: Double($0 + 1) * step)
    }
  }

  func testTwelveWordsOnEachSideOfAnEdge() {
    let around = SkipLog.edgeWords(at: 30, in: words(60))
    XCTAssertEqual(around.before, (18..<30).map { "w\($0)" }.joined(separator: " "))
    XCTAssertEqual(around.after, (30..<42).map { "w\($0)" }.joined(separator: " "))
  }

  func testFewerWordsAtTheStartAndEndOfTheFile() {
    let all = words(10)
    XCTAssertEqual(SkipLog.edgeWords(at: 0, in: all).before, "")
    XCTAssertEqual(SkipLog.edgeWords(at: 10, in: all).after, "")
    XCTAssertEqual(SkipLog.edgeWords(at: 3, in: all).before, "w0 w1 w2")
    XCTAssertEqual(SkipLog.edgeWords(at: 3, in: []), EdgeWords(before: "", after: ""))
  }

  func testAWordThatStartsAtTheEdgeIsAfterIt() {
    let around = SkipLog.edgeWords(at: 5, in: words(10))
    XCTAssertTrue(around.before.hasSuffix("w4"))
    XCTAssertTrue(around.after.hasPrefix("w5"))
  }

  func testAnEntryTakesWordsAtBothEdges() {
    var entry = SkipLogEntry(
      context: context(), start: 20, end: 40, kind: .ad, confidence: .sure, outcome: .kept)
    XCTAssertNil(entry.startWords)
    entry.addWords(from: words(60))
    XCTAssertTrue(entry.startWords?.after.hasPrefix("w20 w21") == true)
    XCTAssertTrue(entry.endWords?.before.hasSuffix("w38 w39") == true)
    XCTAssertTrue(entry.endWords?.after.hasPrefix("w40") == true)
  }

  func testAnEntryWithNoTranscriptHasNoWords() {
    var entry = SkipLogEntry(
      context: context(), start: 20, end: 40, kind: .ad, confidence: .sure, outcome: .kept)
    entry.addWords(from: [])
    XCTAssertNil(entry.startWords)
    XCTAssertNil(entry.endWords)
  }

  // MARK: The file

  private func entry(_ number: Int) -> SkipLogEntry {
    SkipLogEntry(
      context: context("ep\(number)"), start: Double(number), end: Double(number) + 30,
      kind: .ad, confidence: .sure, outcome: .kept)
  }

  func testAnEntryIsOneLineOfJSONThatReadsBack() throws {
    var log = SkipLog()
    var made = entry(7)
    made.addWords(from: words(60))
    log.append(made)
    XCTAssertEqual(log.lines.count, 1)
    XCTAssertFalse(log.lines[0].contains("\n"))
    XCTAssertTrue(log.text.hasSuffix("\n"))
    XCTAssertEqual(SkipLog(text: log.text).entries, [made])
    XCTAssertTrue(log.lines[0].contains("\"outcome\":\"kept\""))
  }

  func testOutcomeAndSecondsAreSavedTogether() throws {
    var log = SkipLog()
    var made = entry(1)
    made.setResult(.trimmed(seconds: 10))
    log.append(made)
    XCTAssertTrue(log.lines[0].contains("\"outcome\":\"trimmed\""))
    XCTAssertTrue(log.lines[0].contains("\"outcomeSeconds\":10"))
    XCTAssertEqual(SkipLog(text: log.text).entries.first?.result, .trimmed(seconds: 10))
  }

  func testLineFiveHundredAndOneDropsLineOne() {
    var log = SkipLog()
    for number in 1...500 { log.append(entry(number)) }
    XCTAssertEqual(log.lines.count, 500)
    XCTAssertEqual(log.entries.first?.episode, "ep1")
    log.append(entry(501))
    XCTAssertEqual(log.lines.count, 500)
    XCTAssertEqual(log.entries.first?.episode, "ep2")
    XCTAssertEqual(log.entries.last?.episode, "ep501")
  }

  func testAFileOfMoreLinesThanTheCapIsCutToTheNewestWhenRead() {
    let text = (1...620).map { "{\"n\":\($0)}" }.joined(separator: "\n") + "\n"
    let log = SkipLog(text: text)
    XCTAssertEqual(log.lines.count, 500)
    XCTAssertEqual(log.lines.first, "{\"n\":121}")
    XCTAssertEqual(log.lines.last, "{\"n\":620}")
  }

  func testBlankLinesAndNoFinalNewlineAreFine() {
    let log = SkipLog(text: "{\"a\":1}\n\n{\"a\":2}")
    XCTAssertEqual(log.lines, ["{\"a\":1}", "{\"a\":2}"])
    XCTAssertEqual(log.text, "{\"a\":1}\n{\"a\":2}\n")
    XCTAssertEqual(SkipLog().text, "")
  }

  func testALineThatIsNotAnEntryIsKeptButNotRead() {
    var log = SkipLog(text: "not json\n")
    log.append(entry(1))
    XCTAssertEqual(log.lines.count, 2)
    XCTAssertEqual(log.entries.count, 1)
  }
}
