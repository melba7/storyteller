// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The new finders, after the old ones: the phone's own sounds, the repeated sounds, the repeated
// words and the meaning layer, then the joints. The old finders' ads (the words, the model, the
// Mac's sounds, the chapters) are in the final ads file already, so a crash here loses nothing.
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
  /// add. The result holds the file as saved (`file` itself when nothing changed).
  func addNewFinders(
    _ id: String, ads store: AdsStore, transcript: Transcript, file: AdsFile
  ) -> NewResult {
    var result = NewResult(file: file)
    guard let modes = newModes(id), let fresh = store.load(detector: Self.detectorName),
      let local = PodcastDownloader.shared.localFile(for: id)
    else { return result }
    result.modes = modes
    var collect = NewCollect(file: fresh, modes: modes)
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
    let snapped = (modes.joints ? pass?.joints : nil).flatMap { joints in
      guardian.hold([FinderNames.joints], episode: id) { _ in
        collect.written(joints: joints, steadyToo: modes.steadyToo)
      }
    }
    var out = snapped ?? collect.written(joints: nil, steadyToo: modes.steadyToo)
    result.moved = out.moved
    let lines = AdChunker.number(transcript.lines)
    let picked =
      guardian.hold(meaningRows == nil ? [] : [FinderNames.meaning], episode: id) { _ in
        collect.questions(lines: lines, meaning: meaningRows, first: asked)
      } ?? collect.questions(lines: lines, meaning: nil, first: asked)
    out.file = AdAsking.adding(picked, to: out.file)
    PodcastTimeline.mark(
      id,
      "new finders: \(collect.summary), \(out.moved.count) borders on joints, \(picked.count) questions"
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

/// The ads the new finders gave so far for one episode, and what becomes of them.
struct NewCollect {
  /// The final file as it was read just now.
  let file: AdsFile
  let modes: NewModes
  /// The skips that were accepted (every one `unsure`, with its finder's `source`).
  private(set) var taken: [FoundAd] = []
  /// The stretches the finders would only ask about, with the chance each is an ad.
  private var asks: [AdAsks.Candidate] = []
  private var counts: [(finder: String, count: Int)] = []

  /// The chance given to a stretch a finder found that only asks. A repeat or a print has no
  /// model behind it; the questions of a model's own band rank by their own chance.
  static let askChance = 0.5
  /// How many of an episode's questions (`AdAsks.most`) the word model may take before the other
  /// finders' questions; the last place is theirs unless they have none.
  static let wordSlots = AdAsks.most - 1

  init(file: AdsFile, modes: NewModes) {
    self.file = file
    self.modes = modes
  }

  /// Every ad of the file and every skip accepted so far.
  var allAds: [FoundAd] { file.ads + taken }

  /// Every stretch known for this file, as ads: its ads, questions, undone skips and "no"
  /// answers, and the skips accepted so far.
  var already: [FoundAd] {
    func stretch(_ item: UndoneAd) -> FoundAd {
      FoundAd(
        start: item.start, end: item.end, kind: .ad, advertiser: "", confidence: .unsure,
        firstWords: "")
    }
    return allAds + (file.asks ?? []) + file.undone.map(stretch) + (file.denied ?? []).map(stretch)
  }

  /// Takes the ads of one finder: of the sorts the listener skips, unsure at most, with the
  /// finder's name; only the parts outside every ad known so far, and not over a stretch the
  /// listener undid or said "no" to; then the settings and the guard decide which are skipped and
  /// which are asked about.
  mutating func add(_ finder: String, _ found: [FoundAd]) {
    var list = found.filter { modes.listener.allows($0.kind) }.map { ad -> FoundAd in
      var one = ad
      one.source = finder
      one.confidence = min(ad.confidence, .unsure)
      return one
    }
    list = NewAds.outside(AdJoin.join(list), of: allAds)
    list = list.filter { ad in
      !file.isUndone(ad) && !(file.denied ?? []).contains { NewAds.overlap($0, ad) }
    }
    let placed = modes.tuning.apply(to: list, show: modes.show)
    switch modes.level(finder) {
    case .off: return
    case .ask:
      asks += (placed.skip + placed.ask).map { AdAsks.Candidate(ad: $0, chance: Self.askChance) }
    case .skip:
      taken += placed.skip
      asks += placed.ask.map { AdAsks.Candidate(ad: $0, chance: Self.askChance) }
    }
    counts.append((finder, list.count))
  }

  /// The file's ads and the skips, in order of time, with their borders put on the joints.
  func written(joints: Joints?, steadyToo: Bool) -> (file: AdsFile, moved: [NewAds.Moved]) {
    var out = file
    out.ads = (file.ads + AdJoin.join(taken)).sorted { $0.start < $1.start }
    var moved: [NewAds.Moved] = []
    if let joints {
      // The stretches the listener judged or was asked about: the pull keeps out of them.
      var judged: [(start: Double, end: Double)] = []
      judged += (file.denied ?? []).map { (start: $0.start, end: $0.end) }
      judged += (file.asks ?? []).map { (start: $0.start, end: $0.end) }
      judged += file.undone.map { (start: $0.start, end: $0.end) }
      let snapped = NewAds.snap(
        out.ads, joints: joints, steadyToo: steadyToo, judged: judged,
        leaving: { NewAds.isFixed($0, in: out) })
      out.ads = snapped.ads
      moved = snapped.moved
    }
    return (out, moved)
  }

  /// The questions to add, in the order they take the places of the cap (`AdAsking.adding`): the
  /// word model's best `wordSlots`, then the best of the finders' asks and the meaning model's
  /// middle band, outside every ad, then what is left of the word model's. So the word model
  /// cannot fill all three places when a repeat or the meaning model has a question, and has
  /// them when they have none. The settings' sorts decide which kinds are asked about at all.
  func questions(
    lines: [NumberedLine], meaning: (model: AdMeaningModel, rows: [[Double]])?, first: [FoundAd]
  ) -> [FoundAd] {
    var candidates = asks
    if let meaning {
      candidates += AdAsks.candidates(
        lines: lines, rows: AdAsks.smoothed(meaning.rows), from: modes.tuning.askThreshold,
        below: meaning.model.askBelow, outside: allAds, source: FinderNames.meaning)
    }
    candidates = candidates.filter { modes.listener.allows($0.ad.kind) }
    let word = askable(first)
    // The places left in the file: one is kept for the finders' questions even when answered ones
    // already hold some.
    let left = AdAsks.most - (file.asks?.count ?? 0)
    let slots = max(0, min(Self.wordSlots, left - 1))
    let early = Array(word.prefix(slots))
    let rest = AdAsks.pick(
      candidates.filter { item in !early.contains { NewAds.overlap($0, item.ad) } },
      outside: allAds + early)
    let late = word.dropFirst(slots).filter { ad in
      !rest.contains { NewAds.overlap($0, ad) }
    }
    return askable(early + rest + late)
  }

  /// Questions of the sorts the listener skips and the settings do not switch off.
  private func askable(_ list: [FoundAd]) -> [FoundAd] {
    let wanted = list.filter { modes.listener.allows($0.kind) }
    let placed = modes.tuning.apply(to: wanted, show: modes.show)
    return wanted.filter { ad in (placed.skip + placed.ask).contains { $0 == ad } }
  }

  /// A line for the diary: how many ads each finder gave (numbers only).
  var summary: String {
    counts.isEmpty ? "none" : counts.map { "\($0.finder) \($0.count)" }.joined(separator: ", ")
  }
}
