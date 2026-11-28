import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// Everything that writes found ads into an ads file leaves a prepared file exactly as it is.
final class PreparedWritersTests: XCTestCase {
  private let sha = String(repeating: "ef", count: 32)
  private let detector = "apple-on-device"

  private func prepared() -> AdsFile {
    let copy = PreparedCopy(file: "prepared/0123456789ab.mp3", sha256: sha, bytes: 1000)
    let marks = [
      AheadMark(
        kind: .ad, confidence: .high, start: 100, end: 160, startWords: "one two three",
        endWords: "four five six"),
      AheadMark(
        kind: .ad, confidence: .low, start: 500, end: 540, startWords: "one two three",
        endWords: "four five six"),
    ]
    let entry = AheadEntry(
      feed: "f", guid: "g", title: "t", marked: 0, ads: marks, copy: copy)
    return PreparedAds.file(for: entry, duration: 1800, detector: detector)!
  }

  private func found(_ start: Double, _ end: Double, source: String? = "meaning") -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "", confidence: .unsure, firstWords: "x",
      source: source)
  }

  private func savedStore() throws -> (AdsStore, Data) {
    let store = AdsStore(folder: try temporaryFolder(), sha256: sha)
    try store.save(prepared())
    return (store, try Data(contentsOf: store.url(detector: detector)))
  }

  func testTheAheadPassLeavesItAlone() {
    let file = prepared()
    let result = AheadFound(ads: [found(700, 760, source: "ahead")], asks: [found(900, 940, source: "ahead")])
    let made = AheadPass.merge(
      result, into: file, show: "s", listener: AdSkipSettings(), tuning: ShowTuning(), level: .skip)
    XCTAssertEqual(made.file, file)
    XCTAssertEqual(made.skips, 0)
    XCTAssertEqual(made.questions, 0)
  }

  func testQuestionsAndMaybesAreNotAddedToIt() {
    let file = prepared()
    XCTAssertEqual(AdAsking.adding([found(900, 940)], to: file), file)
    XCTAssertEqual(AdMaybes.setting([found(900, 940)], in: file), file)
    var plain = file
    plain.prepared = nil
    XCTAssertNotEqual(AdAsking.adding([found(900, 940)], to: plain), plain, "other files still take them")
  }

  func testTheLocalFindersAddNothingToTheFinalOrThePartialFile() throws {
    let (store, before) = try savedStore()
    let after = LocalAdsFile.addToFinal([found(700, 760)], store: store, detector: detector)
    XCTAssertEqual(after, prepared())
    XCTAssertEqual(try Data(contentsOf: store.url(detector: detector)), before)
    XCTAssertFalse(
      LocalAdsFile.addToPartial(
        [found(700, 760)], store: store, detector: detector, detectorVersion: "1", osVersion: "26",
        duration: 1800, covered: 900))
    XCTAssertNil(store.loadPartial(detector: detector))
  }

  func testTheLocalFinalSaveGivesBackTheFileAsItIs() throws {
    let (store, before) = try savedStore()
    let saved = try LocalAdsFile.saveFinal(
      [found(700, 760)], store: store, detector: detector, detectorVersion: LocalAdsFile.localVersion,
      osVersion: "26", duration: 1800)
    XCTAssertEqual(saved, prepared())
    XCTAssertEqual(try Data(contentsOf: store.url(detector: detector)), before)
  }

  func testTheModelIsNotAskedAndTheFileIsNotRewritten() async throws {
    let (store, before) = try savedStore()
    let asked = Counter()
    let detect = FakeDetector(name: detector) { _ in
      asked.add()
      return [range(1, 2)]
    }
    let transcript = makeTranscript(talk(60), sha: sha)
    let outcome = try await AdsRunner.run(
      transcript: transcript, detector: detect, store: store, osVersion: "26")
    XCTAssertEqual(outcome, .finished(prepared()))
    let partial = PartialTranscript(
      identity: transcript.identity, duration: transcript.duration, reached: 600,
      words: transcript.words)
    let again = try await AdsRunner.runPartial(partial: partial, detector: detect, store: store, osVersion: "26")
    XCTAssertEqual(again, .finished(prepared()))
    XCTAssertEqual(asked.count, 0)
    XCTAssertEqual(try Data(contentsOf: store.url(detector: detector)), before)
    XCTAssertNil(store.loadPartial(detector: detector))
  }

  func testThePhoneCanAskWhetherAStoredFileIsPrepared() throws {
    let (store, _) = try savedStore()
    XCTAssertTrue(store.hasPrepared(detector: detector))
    XCTAssertFalse(store.hasPrepared(detector: "other"))
    XCTAssertFalse(AdsStore(folder: try temporaryFolder(), sha256: sha).hasPrepared(detector: detector))
    XCTAssertTrue(prepared().isPrepared)
    var plain = prepared()
    plain.prepared = false
    XCTAssertFalse(plain.isPrepared)
  }

  func testWhatTheListenerDoesStillWrites() throws {
    let (store, _) = try savedStore()
    XCTAssertTrue(store.markUndone(detector: detector, adStart: 100))
    XCTAssertTrue(store.markTrimmed(detector: detector, AdTrim(adStart: 100, end: 130)))
    let saved = try XCTUnwrap(store.load(detector: detector))
    XCTAssertEqual(saved.undone.count, 1)
    XCTAssertEqual(saved.trims?.first?.end, 130)
    XCTAssertEqual(saved.prepared, true)
  }
}

private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0
  func add() { lock.lock(); value += 1; lock.unlock() }
  var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}
