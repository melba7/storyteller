import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// The word half of the whole-round test: a made show of three episodes (`RoundShow`) with a
/// standing host plug that has no ad words in it. The plug is said in all three episodes. The
/// phone only asks about it in episode two, and skips it in episode three once the listener said
/// yes. A "no" keeps a stretch from being asked again and from being skipped.
final class RoundThreeEpisodesTests: XCTestCase {
  private var folder: URL!
  private let one = RoundShow.one
  private let two = RoundShow.two
  private let three = RoundShow.three
  /// A question starts where the repeat finder's first line did, within one line (5 s) of the truth.
  private let oneLine = Double(RoundShow.perLine) * RoundShow.step

  override func setUpWithError() throws { folder = try temporaryFolder() }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  private func question(_ file: AdsFile, near start: Double) throws -> FoundAd {
    try XCTUnwrap(
      AdAsking.open(in: file).first { abs($0.start - start) <= oneLine }, "no open question near \(start)")
  }

  // MARK: Episode one and two: the plug is asked, never skipped

  func testTheStandingPlugIsAskedInEpisodeTwoAndNotSkipped() throws {
    var phone = RoundPhone(folder: folder)
    let first = try phone.finish(one)
    // The sponsor read has ad words, so the older finders skip it in every episode. The plug has
    // none, so they do not, and episode one has nothing to compare it with.
    XCTAssertEqual(first.older.count, 1)
    XCTAssertTrue(RoundPhone.skips(first.file, one.start("sponsor"), one.end("sponsor"), slack: 2))
    XCTAssertFalse(RoundPhone.touches(first.file, one.start("plug"), one.end("plug")))
    XCTAssertNil(first.file.asks)

    let second = try phone.finish(two)
    XCTAssertEqual(second.older.count, 1, "the older finders still see only the sponsor read")
    XCTAssertFalse(RoundPhone.touches(second.file, two.start("plug"), two.end("plug")), "a repeat only asks")
    XCTAssertFalse(RoundPhone.touches(second.file, two.start("quiz"), two.end("quiz")))
    // Both standing passages became questions: guesses that no skip can come from.
    let open = AdAsking.open(in: second.file)
    XCTAssertEqual(open.count, 2)
    let ask = try question(second.file, near: two.start("plug"))
    XCTAssertEqual(ask.end, two.end("plug"), accuracy: oneLine)
    XCTAssertEqual(ask.source, "repeat-words")
    XCTAssertEqual(ask.confidence, .guess)
    XCTAssertEqual(ask.kind, .ad)
    XCTAssertEqual(AdAsking.live(in: second.file, at: two.start("plug") + 10)?.source, "repeat-words")
    XCTAssertNil(second.file.denied)
  }

  func testNoMoreThanThreeQuestionsAnEpisode() throws {
    func standing(_ id: String) -> RoundShow.Episode {
      RoundShow.episode(
        id,
        [.talk(lines: 20)]
          + ["pa", "pb", "pc", "pd"].flatMap { tag -> [RoundShow.Part] in
            [.named(tag, RoundShow.passage(tag, words: 80, id: id)), .talk(lines: 12)]
          })
    }
    var phone = RoundPhone(folder: folder)
    try phone.finish(standing("s1"))
    let file = try phone.finish(standing("s2")).file
    XCTAssertEqual(AdAsks.most, 3)
    XCTAssertEqual(AdAsking.open(in: file).count, 3, "four passages repeat, three are asked")
    XCTAssertEqual(file.asks?.count, 3)
    // A later pass over the same episode cannot bring the number over three.
    let again = try phone.finish(standing("s2")).file
    XCTAssertEqual(again.asks?.count, 3)
    XCTAssertEqual(AdAsking.open(in: again).map(\.start), AdAsking.open(in: file).map(\.start))
  }

  // MARK: A yes

  func testAYesIsSkippedInEpisodeThreeAtOnce() throws {
    var phone = RoundPhone(folder: folder)
    try phone.finish(one)
    let second = try phone.finish(two).file
    let ask = try XCTUnwrap(
      phone.answer(two, askStart: try question(second, near: two.start("plug")).start, isAd: true))
    // The file of episode two is not written again. The answer alone has taught the memory of ads
    // the plug's words, so episode three skips it for sure, with no question about it.
    let third = try phone.finish(three)
    // What the listener said yes to began a few words into the plug (the first changed word), so
    // the skip does too: the same stretch of words, to the word.
    let begins = three.start("plug") + (ask.start - two.start("plug"))
    XCTAssertTrue(RoundPhone.skips(third.file, begins, three.end("plug"), slack: 1))
    let plug = try XCTUnwrap(third.file.ads.first { $0.start <= begins + 1 && $0.end >= three.end("plug") - 1 })
    XCTAssertEqual(plug.confidence, .sure)
    XCTAssertFalse(RoundPhone.touches(third.file, three.start("quiz"), three.end("quiz")), "the quiz is only asked")
    XCTAssertFalse(AdAsking.open(in: third.file).contains { $0.start < three.end("plug") && three.start("plug") < $0.end })
    XCTAssertEqual(third.older.count, 2, "the sponsor read, and the plug from the memory of ads")
  }

  func testAYesIsRebuiltAsATapAdOnEveryWriteOfEpisodeTwosFileEvenAfterAJoin() throws {
    var phone = RoundPhone(folder: folder)
    try phone.finish(one)
    let second = try phone.finish(two).file
    let ask = try XCTUnwrap(
      phone.answer(two, askStart: try question(second, near: two.start("plug")).start, isAd: true))
    // The yes is in the file as a sure "tap" ad over the plug, and is recorded in the question.
    var saved = try XCTUnwrap(phone.store(two).load(detector: RoundShow.detector))
    XCTAssertTrue(RoundPhone.skips(saved, ask.start, ask.end, slack: 0.5))
    XCTAssertEqual(saved.ads.first { $0.source == "tap" }?.confidence, .sure)
    XCTAssertEqual(saved.asks?.filter { $0.confidence == .sure }.count, 1)
    XCTAssertEqual(AdAsking.open(in: saved).count, 1, "the other question waits")

    // An ad that touches the plug is joined with the tap ad, and the join drops its source.
    let touching = FoundAd(
      start: ask.end + 0.2, end: ask.end + 14, kind: .ad, advertiser: "Acme", confidence: .sure,
      firstWords: "x")
    saved = try XCTUnwrap(LocalAdsFile.addToFinal([touching], store: phone.store(two), detector: RoundShow.detector))
    XCTAssertNil(saved.ads.first { $0.start <= ask.start + 0.5 && $0.end >= ask.end }?.source)
    // A finder that knows nothing of the answer writes a fresh final file with no tap ad in it.
    // Every write goes through `AdsStore`, which puts the yes back where nothing covers it.
    let fresh = LocalAds().ads(transcript: two.transcript, episodeDuration: two.transcript.duration)
    XCTAssertFalse(fresh.contains { $0.start < ask.end && ask.start < $0.end }, "nothing of it covers the plug")
    _ = try LocalAdsFile.saveFinal(
      fresh + [touching], store: phone.store(two), detector: RoundShow.detector,
      detectorVersion: "1", osVersion: "26", duration: two.transcript.duration)
    let later = try XCTUnwrap(phone.store(two).load(detector: RoundShow.detector))
    XCTAssertTrue(RoundPhone.skips(later, ask.start, ask.end, slack: 0.5), "\(later.ads)")
    XCTAssertEqual(later.ads.first { $0.source == "tap" }?.confidence, .sure)
    XCTAssertEqual(AdAsking.open(in: later).count, 1, "and it is not asked again")
  }

  func testWithoutTheYesThePlugIsOnlyAskedAgainInEpisodeThree() throws {
    var phone = RoundPhone(folder: folder)
    try phone.finish(one)
    try phone.finish(two)
    let third = try phone.finish(three)
    XCTAssertFalse(RoundPhone.touches(third.file, three.start("plug"), three.end("plug")))
    XCTAssertEqual(AdAsking.open(in: third.file).count, 2)
  }

  // MARK: A no

  func testANoGoesToDeniedAndTheStretchIsNeitherAskedAgainNorSkipped() throws {
    var phone = RoundPhone(folder: folder)
    try phone.finish(one)
    let second = try phone.finish(two).file
    let quiz = try question(second, near: two.start("quiz"))
    phone.answer(two, askStart: quiz.start, isAd: false)
    var saved = try XCTUnwrap(phone.store(two).load(detector: RoundShow.detector))
    XCTAssertEqual(saved.denied, [UndoneAd(start: quiz.start, end: quiz.end)])
    XCTAssertEqual(saved.undone, [], "a no is not an undone skip: it must never stop a real ad")
    XCTAssertEqual(AdAsking.open(in: saved).count, 1, "the plug is still waiting")
    XCTAssertFalse(RoundPhone.touches(saved, two.start("quiz"), two.end("quiz")))
    // A later pass over the episode does not ask it again, and the no is carried.
    saved = try phone.finish(two).file
    XCTAssertEqual(saved.denied, [UndoneAd(start: quiz.start, end: quiz.end)])
    XCTAssertFalse(AdAsking.open(in: saved).contains { abs($0.start - quiz.start) <= oneLine })
    XCTAssertFalse(RoundPhone.touches(saved, two.start("quiz"), two.end("quiz")))
    // The next episode says the same words again. They are not asked about and not skipped, while
    // the plug, which nobody answered, is asked once more.
    let third = try phone.finish(three).file
    XCTAssertFalse(RoundPhone.touches(third, three.start("quiz"), three.end("quiz")))
    let open = AdAsking.open(in: third)
    XCTAssertEqual(open.count, 1, "\(open)")
    XCTAssertEqual(open.first?.start ?? -1, three.start("plug"), accuracy: oneLine)
  }
}
