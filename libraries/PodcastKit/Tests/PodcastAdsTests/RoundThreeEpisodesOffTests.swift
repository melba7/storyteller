import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// The off switch of the whole-round test: with every new finder off, the phone's result for each
/// episode is exactly what `LocalAds` gave before this round (same ads, same starts and ends, same
/// order), and with them on it is not, so the equality says something. Every new finder is in
/// the run: the repeat of words for real, the two sound finders as made lists (the sound half of
/// the test proves them on real files), and the meaning model with a made embedder.
final class RoundThreeEpisodesOffTests: XCTestCase {
  private var folder: URL!
  private let episodes = [RoundShow.one, RoundShow.two, RoundShow.three]

  override func setUpWithError() throws { folder = try temporaryFolder() }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  /// What the phone gave before this round: the word rules, joined.
  private func before(_ episode: RoundShow.Episode) -> [FoundAd] {
    LocalAds().ads(transcript: episode.transcript, episodeDuration: episode.transcript.duration)
  }

  private func extras(_ episode: RoundShow.Episode) -> RoundPhone.Extras {
    var table = Made.table
    table["Come and say hello on our forum, we read every message."] = [1, 0.1, 0, 0]
    let plug = ScoreSpan(start: episode.start("plug") + 1, end: episode.end("plug") - 1)
    return RoundPhone.Extras(
      sounds: [ShowTuning.ownSound: [plug], ShowTuning.repeatSound: [plug]],
      meaning: (AdMeaningModel(data: Made.file())!, MadeEmbedder(table: table)))
  }

  /// The three episodes through a phone with these settings and this guard.
  private func run(
    _ tuning: ShowTuning, guardFile: FinderGuard = FinderGuard(appBuild: "1")
  ) throws -> (files: [AdsFile], phone: RoundPhone) {
    var phone = RoundPhone(folder: folder, tuning: tuning)
    phone.guardFile = guardFile
    var files: [AdsFile] = []
    for episode in episodes { files.append(try phone.finish(episode, extras: extras(episode)).file) }
    return (files, phone)
  }

  // MARK: Off

  func testWithTheMacsSettingsSayingOffTheResultIsWhatLocalAdsGave() throws {
    let made = try run(RoundShow.everythingOff)
    XCTAssertEqual(made.phone.ran, [], "an off finder is not even run")
    for (episode, file) in zip(episodes, made.files) {
      XCTAssertFalse(before(episode).isEmpty, "the sponsor read is found")
      XCTAssertEqual(file.ads, before(episode), episode.id)
      XCTAssertNil(file.asks)
      XCTAssertNil(file.denied)
    }
  }

  func testWithTheGuardSayingOffEverywhereTheResultIsWhatLocalAdsGave() throws {
    // Each finder trapped twice in this build (the app died inside it two times): off everywhere.
    var guardFile = FinderGuard(appBuild: "1")
    for _ in 0..<2 {
      for name in ShowTuning.finderNames { guardFile.begin(finder: name, episode: "any") }
      guardFile.recover()
    }
    let made = try run(ShowTuning(), guardFile: guardFile)
    XCTAssertEqual(made.phone.ran, [])
    for (episode, file) in zip(episodes, made.files) {
      XCTAssertEqual(file.ads, before(episode), episode.id)
      XCTAssertNil(file.asks)
    }
  }

  // MARK: On

  func testWithTheFindersOnTheResultGrowsAndNothingTheOlderFindersFoundIsEdited() throws {
    // The Mac's file lets the repeat of words skip too; the built-in default only asks.
    let tuning = RoundShow.tuning(show: #", "finders": {"repeat-words": "skip"}"#)
    let made = try run(tuning)
    XCTAssertEqual(Set(made.phone.ran), Set(ShowTuning.finderNames))
    for (episode, file) in zip(episodes, made.files) {
      // Rule 2 of the round: a new finder only adds. Every older ad is in the file as it was.
      for ad in before(episode) { XCTAssertTrue(file.ads.contains(ad), "\(episode.id): \(ad)") }
      // A skip made only by a new finder is unsure at most, so the Undo note shows.
      XCTAssertTrue(file.ads.filter { !before(episode).contains($0) }.allSatisfy { $0.confidence == .unsure })
      XCTAssertGreaterThan(file.ads.count, before(episode).count, episode.id)
    }
    // The meaning model's ad is the hosts' favour in episode two, and it names its finder.
    let meaning = made.files[1].ads.filter { $0.source == ShowTuning.meaning }
    XCTAssertEqual(meaning.count, 1)
    XCTAssertEqual(meaning.first?.start ?? 0, RoundShow.two.start("favour"), accuracy: 5)
    XCTAssertEqual(meaning.first?.kind, .ownPlug)
    // The repeat of sounds only asks by default, so no ad of the file is its own.
    XCTAssertFalse(made.files.contains { $0.ads.contains { $0.source == ShowTuning.repeatSound } })
  }

  // MARK: The names the finders put in their ads

  func testEachNewFindersAdsCarryTheNameTheSettingsUse() throws {
    XCTAssertEqual(RepeatedWords.source, ShowTuning.repeatWords)
    XCTAssertEqual(MeaningAds.source, ShowTuning.meaning)
    XCTAssertEqual(ScoreAds.ads([ScoreSpan(start: 10, end: 40)], source: ShowTuning.ownSound).first?.source, "own-sound")
    // The clean-up builds its ads with no source, so the meaning finder names them AFTER it, and
    // only then can the settings act on them (and drop them, when the finder is off).
    let transcript = RoundShow.two.transcript
    let lines = AdChunker.number(transcript.lines)
    let favour = lines.filter { RoundShow.favour.contains($0.text) }.map(\.number)
    let cleaned = AdCleanup.run(
      ranges: [AdRange(startLine: favour[0], endLine: favour[3], advertiser: "", kind: .ownPlug, confidence: .unsure)],
      transcript: transcript)
    XCTAssertEqual(cleaned.count, 1)
    XCTAssertNil(cleaned.first?.source, "this is why `apply` cannot run after the clean-up")
    let found = extras(RoundShow.two).meaning.map {
      MeaningAds.find(model: $0.model, transcript: transcript, embedder: $0.embedder)
    } ?? []
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found.map(\.source), [ShowTuning.meaning])
    XCTAssertEqual(RoundShow.everythingOff.apply(to: found, show: RoundShow.show).skip, [])
    XCTAssertEqual(ShowTuning().apply(to: found, show: RoundShow.show).skip, found)
  }
}
