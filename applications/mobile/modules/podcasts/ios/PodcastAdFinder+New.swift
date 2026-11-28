// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The new finders, after the old ones: the phone's own sounds, the repeated sounds, the repeated
// words, the meaning layer and the Mac's marks of the night before, then the joints. The old
// finders' ads (the words, the model, the Mac's sounds, the chapters) are in the final ads file
// already, so a crash here loses nothing.
// Each new finder runs through `PodcastFinderGuard` (a mark on disk before, cleared after) and
// only while iOS holds time for the app. The order, for each finder: find; keep only what lies
// outside every ad that is in the file (so a new finder can only ADD stretches, never lengthen or
// upgrade an ad); set the settings and the guard on it (`ShowTuning.apply`, which needs the
// `source`, so it comes before any join); the skips are joined; borders snap onto the file's
// joints; the file is written through `AdsStore`; the asks go into the file's questions.
// The listener's own switches come first: a show whose skipping is switched off for every sort
// gets no new finder and no question, and an ad of a sort that is switched off is left out of the
// skips and of the questions alike. It runs in the finder's own background task, never on the main
// thread. Questions come only from this whole-transcript pass.
import Foundation
import PodcastAds
import PodcastAudioMatch
import PodcastPlayback
import PodcastTranscripts

/// What the new finders may do for one episode: the stricter of the guard and the settings.
struct NewModes {
  var show: String
  /// The listener's switches for the show (ads, plugs, promos, credits), which come before the
  /// Mac's settings.
  var listener: AdSkipSettings
  var tuning: ShowTuning
  var levels: [String: FinderMode]
  /// Whether borders snap onto joints, and whether a file with a steady encoding counts too.
  var joints: Bool
  var steadyToo: Bool

  func level(_ finder: String) -> FinderMode { levels[finder] ?? .off }
}

/// What `addNewFinders` did: the file as saved, and the borders the snap moved.
struct NewResult {
  var file: AdsFile
  var moved: [NewAds.Moved] = []
  var modes: NewModes?
  /// What the word rules and the word model gave for the whole transcript, before any join. It is
  /// empty unless steady joints are on (the pull-back is only on then); see `JointPull`.
  var words: [FoundAd] = []
}

extension PodcastAdFinder {
  /// The listener's switches for a show: theirs, with the show's own choices for ads and plugs
  /// (the rule of `PodcastPlayer.skipAds(forShow:)` and of the player's skipper).
  static func listenerSwitches(forShow show: String) -> AdSkipSettings {
    let own = ShowSettingsFile.load(from: ShowSettingsStore.url)[show]
    return AdSkipDefaults.settings.overridden(skipAds: own?.skipAds, skipOwnPlugs: own?.skipPlugs)
  }

  /// The modes for this episode, or nil when no new finder may run now: its show is not known,
  /// the listener skips no sort of ad for it, or the finder may not work now (`allowedNow`).
  func newModes(_ id: String, now: Date = Date()) -> NewModes? {
    guard let show = EpisodeShows.shared.show(for: id), !show.isEmpty, allowedNow else {
      return nil
    }
    let listener = Self.listenerSwitches(forShow: show)
    guard listener.skipsAnySort else { return nil }
    let tuning = PodcastTeaching.shared.files.tuning
    let guardian = PodcastFinderGuard.shared
    var levels: [String: FinderMode] = [:]
    for name in ShowTuning.finderNames + [FinderNames.wordModel] {
      levels[name] = ShowTuning.stricter(
        guardian.mode(finder: name, show: show, episode: id, now: now),
        tuning.level(forFinder: name, show: show))
    }
    // The repeats only ever find plain ads: with those switched off there is nothing to look for.
    if !listener.skipAds {
      levels[FinderNames.repeatSound] = .off
      levels[FinderNames.repeatWords] = .off
    }
    let snaps =
      guardian.mode(finder: FinderNames.joints, show: show, episode: id, now: now) == .skip
    return NewModes(
      show: show, listener: listener, tuning: tuning, levels: levels,
      joints: snaps && tuning.joints(show: show), steadyToo: tuning.steadyJoints(show: show))
  }

  /// Runs the new finders on the final ads file `file` of a whole transcript and saves what they
  /// add. The result holds the file as saved (`file` itself when nothing changed). `modelAsks` are
  /// the answers of Apple's model that only ask on this show (`ModelPlacing.asked`): they take part
  /// in the ranking of the questions like the other finders' stretches.
  func addNewFinders(
    _ id: String, ads store: AdsStore, transcript: Transcript, file: AdsFile,
    modelAsks: [FoundAd] = []
  ) -> NewResult {
    var result = NewResult(file: file)
    // The Mac's marks on a copy it prepared are final: no new finder runs for it (PreparedAds).
    guard !store.hasPrepared(detector: Self.detectorName) else { return result }
    guard let modes = newModes(id), let fresh = store.load(detector: Self.detectorName),
      let local = PodcastDownloader.shared.localFile(for: id)
    else { return result }
    result.modes = modes
    var collect = NewCollect(file: fresh, modes: modes)
    if !modelAsks.isEmpty { collect.add(ShowTuning.appleModel, modelAsks) }
    let pass = soundResult(id, sha256: store.sha256, file: local, modes: modes)
    if modes.level(FinderNames.ownSound) != .off, let pass {
      collect.add(FinderNames.ownSound, NewAds.ads(ofSounds: pass.own))
    }
    if modes.level(FinderNames.repeatSound) != .off, let pass {
      collect.add(FinderNames.repeatSound, NewAds.ads(ofRepeats: pass.repeats))
    }
    if allowedNow, modes.level(FinderNames.repeatWords) != .off {
      let already = collect.already + openingStretch(modes.show, transcript)
      let found = PodcastFinderGuard.shared.hold([FinderNames.repeatWords], episode: id) { _ in
        PodcastRepeats.shared.findWords(
          show: modes.show, episode: id, lines: transcript.lines, duration: transcript.duration,
          already: already)
      }
      if let found { collect.add(FinderNames.repeatWords, found) }
    }
    var meaningRows: (model: AdMeaningModel, rows: [[Double]])?
    if allowedNow, modes.level(FinderNames.meaning) != .off,
      let model = PodcastTeaching.shared.files.meaning
    {
      let outcome = PodcastFinderGuard.shared.hold([FinderNames.meaning], episode: id) { held in
        PodcastMeaning.run(model: model, transcript: transcript, stop: held.stop)
      }
      PodcastTimeline.mark(id, outcome?.diary ?? "meaning layer left out: no time was held")
      if let run = outcome?.run {
        collect.add(FinderNames.meaning, run.ads)
        meaningRows = (model, run.rows)
      }
    }
    // The Mac's marks of the night before (PodcastAdFinder+Ahead.swift): skips for the ads found
    // by both edges, questions for the ads found by one.
    var marks: [FoundAd] = []
    if allowedNow, modes.level(FinderNames.ahead) != .off,
      let found = aheadFound(id, transcript: transcript, judged: collect.judged)
    {
      marks = found.ads
      collect.add(FinderNames.ahead, found.ads)
      collect.add(FinderNames.ahead, found.asks, onlyAsk: true)
    }
    // The snap, the word model's questions and the meaning layer's are new work too: each runs
    // under the mark of the finder it belongs to, so a crash in it is not repeated every launch.
    let guardian = PodcastFinderGuard.shared
    var asked: [FoundAd] = []
    if modes.level(FinderNames.wordModel) != .off, PodcastTeaching.shared.files.model != nil {
      asked =
        guardian.hold([FinderNames.wordModel], episode: id) { _ in
          wordModelQuestions(id, modes, transcript, collect.allAds)
        } ?? []
    }
    // The pull-back of a late start is for the starts the word finders gave, and the ads of the
    // file are joined already, so the words are found again here (as `localAds` does for the file).
    if modes.joints && modes.steadyToo {
      collect.words = PodcastTeaching.shared.files.local.ads(
        transcript: transcript, episodeDuration: transcript.duration)
    }
    let snapped = (modes.joints ? pass?.joints : nil).flatMap { joints in
      guardian.hold([FinderNames.joints], episode: id) { _ in
        collect.written(joints: joints, steadyToo: modes.steadyToo)
      }
    }
    var out = snapped ?? collect.written(joints: nil, steadyToo: modes.steadyToo)
    result.moved = out.moved
    let cued = addCueStretches(id, modes, transcript, to: &out.file, marks: marks)
    result.words = collect.words
    let lines = AdChunker.number(transcript.lines)
    let picked =
      guardian.hold(meaningRows == nil ? [] : [FinderNames.meaning], episode: id) { _ in
        collect.questions(lines: lines, meaning: meaningRows, first: asked)
      } ?? collect.questions(lines: lines, meaning: nil, first: asked)
    out.file = AdAsking.adding(picked, to: out.file)
    let maybes = settingMaybes(id, modes, transcript, collect, picked: picked, in: &out.file)
    PodcastTimeline.mark(
      id,
      "new finders: \(collect.summary), \(out.moved.count) borders on joints, \(picked.count) questions, opening lines \(cued.openings), filled holes \(cued.holes), \(maybes) maybes"
    )
    guard out.file != fresh, (try? store.save(out.file)) != nil else { return result }
    result.file = store.load(detector: Self.detectorName) ?? out.file
    return result
  }

  /// The questions the word model's middle band gives (its own chance between the ask threshold
  /// and its start threshold), outside every ad of the file after the new skips.
  private func wordModelQuestions(
    _ id: String, _ modes: NewModes, _ transcript: Transcript, _ ads: [FoundAd]
  ) -> [FoundAd] {
    guard modes.level(FinderNames.wordModel) != .off,
      let model = PodcastTeaching.shared.files.model
    else { return [] }
    return AdAsks.questions(
      model: model, lines: AdChunker.number(transcript.lines), duration: transcript.duration,
      from: modes.tuning.askThreshold, outside: ads, source: FinderNames.wordModel)
  }

  /// Where the show's opening words are in this episode, as a stretch no repeat is offered over.
  private func openingStretch(_ show: String, _ transcript: Transcript) -> [FoundAd] {
    guard let opening = PodcastShowOpenings.shared.opening(show: show),
      let at = ShowOpening.find(opening, in: transcript.words)
    else { return [] }
    let tail = transcript.words.drop { $0.start < at - 0.01 }
      .prefix(opening.split(separator: " ").count)
    return [
      FoundAd(
        start: at, end: max(tail.last?.end ?? at, at + 1), kind: .ad, advertiser: "",
        confidence: .unsure, firstWords: "")
    ]
  }
}
