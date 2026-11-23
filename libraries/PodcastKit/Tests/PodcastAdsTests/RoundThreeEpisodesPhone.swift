import Foundation
import XCTest

@testable import PodcastAds
@testable import PodcastTranscripts

/// What the phone does with a whole transcript in this round, written out with the real types of
/// PodcastKit in the order of docs/PODCASTS-ADS-TEACHING.md. The phone's own wiring is in the iOS
/// module, which only a Mac can build, so this is its stand-in: if the order or a rule of a type
/// changes, the tests that use it fail. The order for each episode is:
///  1. the older finders: `LocalAds` and what the memory of ads knows, joined and written first;
///  2. each new finder on its OWN list: run only when the Mac's settings and the finder guard both
///     allow it, kept outside the older ads, sorted by `ShowTuning.apply` into skips and questions;
///  3. only what skips is joined with the older ads (`AdJoin`) and written through `AdsStore`;
///  4. the questions are chosen (`AdAsks.pick`) and added to the file (`AdAsking.adding`);
///  5. learning: the repeat memory, and the memory of ads from the file's sure ads.
struct RoundPhone {
  var memory = RepeatedWords()
  var known = KnownAds()
  var tuning: ShowTuning
  var guardFile = FinderGuard(appBuild: "1")
  let folder: URL
  /// The finders that were really run, in order (an off finder is never run).
  var ran: [String] = []

  init(folder: URL, tuning: ShowTuning = ShowTuning()) {
    self.folder = folder
    self.tuning = tuning
  }

  func store(_ episode: RoundShow.Episode) -> AdsStore { AdsStore(folder: folder, sha256: episode.id) }

  /// What one pass gave: the file as saved, and the ads of the older finders alone.
  struct Outcome {
    var file: AdsFile
    var older: [FoundAd]
  }

  /// The finders the pass has besides the repeat of words, which it runs itself: the sound
  /// finders' lists as made spans (the sound half of the test proves them on real files) and the
  /// meaning model with its made embedder.
  struct Extras {
    var sounds: [String: [ScoreSpan]] = [:]
    var meaning: (model: AdMeaningModel, embedder: LineEmbedder)?
  }

  @discardableResult
  mutating func finish(_ episode: RoundShow.Episode, extras: Extras = Extras()) throws -> Outcome {
    let transcript = episode.transcript
    let words = transcript.words
    let store = store(episode)
    let show = RoundShow.show
    // 1. The older finders.
    let remembered = KnownAdUse.from(known.find(in: words, show: show), words: words)
    let older = AdJoin.join(
      LocalAds().ads(transcript: transcript, episodeDuration: transcript.duration)
        + remembered.ads.filter { !remembered.provisional.contains($0) })
    let repeats = memory
    // 2. Each new finder on its own list.
    let finders: [(name: String, find: () -> [FoundAd])] = [
      (ShowTuning.meaning, { Self.meaning(extras, transcript) }),
      (ShowTuning.ownSound, { ScoreAds.ads(extras.sounds[ShowTuning.ownSound] ?? [], source: ShowTuning.ownSound) }),
      (ShowTuning.repeatSound, { ScoreAds.ads(extras.sounds[ShowTuning.repeatSound] ?? [], source: ShowTuning.repeatSound) }),
      (
        ShowTuning.repeatWords,
        {
          repeats.find(
            show: show, episode: episode.id, lines: transcript.lines, duration: transcript.duration,
            now: RoundShow.now, already: older)
        }
      ),
    ]
    var skips: [FoundAd] = []
    var asks: [FoundAd] = []
    for finder in finders {
      let mode = ShowTuning.stricter(
        tuning.level(forFinder: finder.name, show: show),
        guardFile.mode(finder: finder.name, show: show, episode: episode.id, now: RoundShow.now))
      guard mode != .off else { continue }
      ran.append(finder.name)
      let sorted = tuning.apply(to: ScoreAds.outside(finder.find(), of: older), show: show)
      // A finder the guard turned to "ask" only asks, whatever the file says.
      if mode == .ask {
        asks += sorted.skip + sorted.ask
      } else {
        skips += sorted.skip
        asks += sorted.ask
      }
    }
    // 3. Only what skips is joined and written.
    var file = try LocalAdsFile.saveFinal(
      AdJoin.join(older + skips), store: store, detector: RoundShow.detector,
      detectorVersion: LocalAdsFile.localVersion, osVersion: "26", duration: transcript.duration)
    file = store.load(detector: RoundShow.detector) ?? file
    // 4. The questions.
    let questions = AdAsks.pick(asks.map { AdAsks.Candidate(ad: $0, chance: 0.5) }, outside: file.ads)
    try store.save(AdAsking.adding(questions, to: file))
    file = try XCTUnwrap(store.load(detector: RoundShow.detector))
    // 5. Learning.
    self.memory.remember(
      show: show, episode: episode.id, lines: transcript.lines, now: RoundShow.now)
    known.learn(from: file, transcript: transcript, show: show, now: RoundShow.now)
    return Outcome(file: file, older: older)
  }

  private static func meaning(_ extras: Extras, _ transcript: Transcript) -> [FoundAd] {
    guard let meaning = extras.meaning else { return [] }
    return MeaningAds.find(model: meaning.model, transcript: transcript, embedder: meaning.embedder)
  }

  // MARK: The listener

  /// The listener answers the open question that starts at `start` in the episode's file. A yes
  /// goes to the file and to the memory of ads, and tells the guard; a no goes to the file's
  /// `denied` list and to the repeat memory, and tells the guard. Returns the question.
  @discardableResult
  mutating func answer(_ episode: RoundShow.Episode, askStart start: Double, isAd: Bool) -> FoundAd? {
    guard
      let ask = AdAsking.answer(
        store: store(episode), detector: RoundShow.detector, askStart: start, isAd: isAd)
    else { return nil }
    let finder = ask.source ?? ""
    if isAd {
      known.learnTapped(ask, transcript: episode.transcript, show: RoundShow.show, now: RoundShow.now)
      guardFile.confirmed(finder: finder, show: RoundShow.show, now: RoundShow.now)
    } else {
      memory.deny(
        show: RoundShow.show, lines: episode.transcript.lines, start: ask.start, end: ask.end,
        now: RoundShow.now)
      guardFile.denied(finder: finder, show: RoundShow.show, now: RoundShow.now)
    }
    return ask
  }

  // MARK: Reading a file

  /// Whether the ads of the file that were not undone cover every second from `from` to `to`,
  /// give or take `slack`: whether the player would skip the whole stretch.
  static func skips(_ file: AdsFile, _ from: Double, _ to: Double, slack: Double) -> Bool {
    var reached = from + slack
    for ad in file.ads.filter({ !file.isUndone($0) }).sorted(by: { $0.start < $1.start }) {
      if ad.start <= reached { reached = max(reached, ad.end) }
    }
    return reached >= to - slack
  }

  /// Whether any ad of the file that was not undone touches the stretch.
  static func touches(_ file: AdsFile, _ from: Double, _ to: Double) -> Bool {
    file.ads.contains { !file.isUndone($0) && $0.start < to && from < $0.end }
  }
}
