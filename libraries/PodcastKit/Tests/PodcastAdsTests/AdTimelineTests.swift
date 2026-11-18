import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

final class AdTimelineTests: XCTestCase {
  private func ad(_ start: Double, _ end: Double, _ confidence: AdConfidence = .sure) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: .ad, advertiser: "Acme", confidence: confidence, firstWords: "x")
  }

  func testAnAdKnownBeforeThePlayheadGetsThereIsSkipped() throws {
    let verdicts = AdTimeline.verdicts(snapshots: [
      AdSnapshot(elapsed: 30, ads: [ad(100, 160)]), AdSnapshot(elapsed: 90, ads: [ad(100, 160)]),
    ])
    let verdict = try XCTUnwrap(verdicts.first)
    XCTAssertEqual(verdicts.count, 1)
    XCTAssertEqual(verdict.knownAt, 30)
    XCTAssertEqual(verdict.reachedAt, 100)
    XCTAssertTrue(verdict.skipped)
    XCTAssertEqual(verdict.lead, 70)
  }

  func testAnAdKnownAfterThePlayheadPassedIsNotSkipped() throws {
    let verdicts = AdTimeline.verdicts(snapshots: [
      AdSnapshot(elapsed: 50, ads: []), AdSnapshot(elapsed: 130, ads: [ad(100, 160)]),
    ])
    let verdict = try XCTUnwrap(verdicts.first)
    XCTAssertEqual(verdict.knownAt, 130)
    XCTAssertFalse(verdict.skipped)
    XCTAssertEqual(verdict.lead, -30)
  }

  func testTheFirstSnapshotWithAnOverlappingAdIsWhenItWasKnown() throws {
    // The first answer saw only the start of the ad; the later one has all of it.
    let verdicts = AdTimeline.verdicts(snapshots: [
      AdSnapshot(elapsed: 20, ads: [ad(100, 120)]), AdSnapshot(elapsed: 60, ads: [ad(100, 160)]),
    ])
    XCTAssertEqual(verdicts.first?.knownAt, 20)
    XCTAssertEqual(verdicts.first?.ad.end, 160)
  }

  func testSkippingAnEarlierAdBringsALaterOneSooner() throws {
    let snapshots = [
      AdSnapshot(elapsed: 10, ads: [ad(50, 150)]),
      AdSnapshot(elapsed: 150, ads: [ad(50, 150), ad(200, 260)]),
    ]
    let verdicts = AdTimeline.verdicts(snapshots: snapshots)
    XCTAssertEqual(verdicts.map(\.skipped), [true, false])
    // The first ad is jumped (100 s), so 200 s of the episode is reached after 100 s of play.
    XCTAssertEqual(verdicts[1].reachedAt, 100)
  }

  func testAFasterListenerReachesAdsSooner() throws {
    let snapshots = [AdSnapshot(elapsed: 60, ads: [ad(100, 160)])]
    XCTAssertTrue(AdTimeline.verdicts(snapshots: snapshots, rate: 1).first!.skipped)
    let fast = try XCTUnwrap(AdTimeline.verdicts(snapshots: snapshots, rate: 2).first)
    XCTAssertEqual(fast.reachedAt, 50)
    XCTAssertFalse(fast.skipped)
  }

  func testAnAdAtTheVeryStartIsSkippedOnlyWhenKnownAtOnce() {
    let late = AdTimeline.verdicts(snapshots: [AdSnapshot(elapsed: 5, ads: [ad(0, 30)])])
    XCTAssertFalse(late[0].skipped)
    let atOnce = AdTimeline.verdicts(snapshots: [AdSnapshot(elapsed: 0, ads: [ad(0, 30)])])
    XCTAssertTrue(atOnce[0].skipped)
  }

  func testSureAndUnsureAdsAreCountedAndTheOrderIsByStart() {
    let verdicts = AdTimeline.verdicts(snapshots: [
      AdSnapshot(elapsed: 1, ads: [ad(300, 360), ad(100, 160, .unsure), ad(200, 260, .guess)])
    ])
    XCTAssertEqual(verdicts.map(\.ad.start), [100, 300])
  }

  func testNoSnapshotsGiveNoVerdicts() {
    XCTAssertEqual(AdTimeline.verdicts(snapshots: []), [])
  }

  func testSpeedIsAudioSecondsPerSecondOfWork() {
    XCTAssertEqual(AdTimeline.speed(audioSeconds: 3600, processingSeconds: 120), 30)
    XCTAssertEqual(AdTimeline.speed(audioSeconds: 3600, processingSeconds: 0), 0)
  }
}

/// A clock the fakes move forward by the work they pretend to do.
private final class Clock: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0.0
  var now: Double { lock.withLock { value } }
  func advance(_ seconds: Double) { lock.withLock { value += seconds } }
}

private struct ListeningRecogniser: PieceRecogniser {
  var transcript: Transcript
  var clock: Clock
  /// Seconds of audio heard in one second of work.
  var speed: Double
  let name = "Fake"
  let version = "1"
  let osVersion = "26.0"

  func prepare(locale: String) async throws -> String { locale }
  func duration(of file: URL) throws -> Double { transcript.duration }
  func recognise(file: URL, locale: String, from: Double, to: Double) async throws -> [TranscriptWord] {
    clock.advance((to - from) / speed)
    return transcript.words.filter { $0.start >= from && $0.start < to }
  }
}

final class PlayCheckTests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws { folder = try temporaryFolder() }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  /// A 10-minute episode with a sponsor read at lines 3 to 5 (20 to 49 s) and lines 50 to 52
  /// (490 to 519 s). The model needs `modelSeconds` for each piece.
  private func check(modelSeconds: Double) async throws -> PlayCheckResult {
    let transcript = makeTranscript(talk(60, ad: 3...5).enumerated().map { index, text in
      (50...52).contains(index + 1) ? "ad copy \(index + 1) from our sponsor" : text
    })
    let clock = Clock()
    let detector = FakeDetector(tokenBudget: 2500) { piece in
      clock.advance(modelSeconds)
      let inside = piece.lines.filter { $0.text.hasPrefix("ad copy") }.map(\.number)
      // One range for each run of ad lines.
      var ranges: [AdRange] = []
      for number in inside {
        if let last = ranges.last, last.endLine == number - 1 {
          ranges[ranges.count - 1].endLine = number
        } else {
          ranges.append(range(number, number))
        }
      }
      return ranges
    }
    return try await PlayCheck.run(
      audio: URL(fileURLWithPath: "/nowhere/a.mp3"), sha256: "aa", locale: "en-US",
      recogniser: ListeningRecogniser(transcript: transcript, clock: clock, speed: 20),
      detector: detector, store: AdsStore(folder: folder, sha256: "aa"), now: { clock.now })
  }

  func testAFastModelKeepsAheadOfTheListener() async throws {
    let result = try await check(modelSeconds: 1)
    XCTAssertEqual(result.verdicts.count, 2)
    XCTAssertEqual(result.verdicts.map(\.skipped), [true, true])
    XCTAssertEqual(result.verdicts[0].ad.start, 20, accuracy: 10)
    XCTAssertLessThan(result.verdicts[0].knownAt, 20, "found from the first minutes")
    XCTAssertGreaterThan(result.speed, 1)
  }

  func testASlowModelIsLateAndTheTotalsAddUp() async throws {
    let result = try await check(modelSeconds: 60)
    XCTAssertFalse(result.verdicts[0].skipped, "the first ad was known after a minute of work")
    XCTAssertGreaterThan(result.modelSeconds, 60)
    XCTAssertEqual(result.totalSeconds, result.transcribeSeconds + result.modelSeconds, accuracy: 0.001)
    XCTAssertEqual(result.snapshots.last?.elapsed, result.totalSeconds)
  }

  func testTheTranscriptIsCutInTheShortFirstPieces() async throws {
    let result = try await check(modelSeconds: 1)
    // 600 s of audio in four pieces (60, 120, 300, 120 s) at 20 s of audio per second; the
    // three later pieces each read 2 s of overlap again.
    XCTAssertEqual(result.transcribeSeconds, (600 + 3 * 2) / 20, accuracy: 0.001)
  }

  func testTheFullPassSavesTheFinalFile() async throws {
    let result = try await check(modelSeconds: 1)
    let finalAds = try XCTUnwrap(result.snapshots.last?.ads)
    XCTAssertEqual(finalAds.count, 2)
    XCTAssertNotNil(AdsStore(folder: folder, sha256: "aa").load(detector: "fake"))
  }
}
