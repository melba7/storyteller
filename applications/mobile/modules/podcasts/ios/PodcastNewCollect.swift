// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// What the new finders gave so far for one episode, and what becomes of it: the skips, the
// questions and the maybes. Moved out of PodcastAdFinder+New.swift without a change to its rules.
import Foundation
import PodcastAds
import PodcastAudioMatch

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
  /// The ads the word finders gave for the whole transcript, which tell the snap which starts it
  /// may pull back to a joint (`JointPull.allows(_:words:)`).
  var words: [FoundAd] = []

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
  /// which are asked about. With `onlyAsk` none is skipped, whatever the level (a stretch the finder
  /// is not sure of).
  mutating func add(_ finder: String, _ found: [FoundAd], onlyAsk: Bool = false) {
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
      if onlyAsk {
        asks += (placed.skip + placed.ask).map { AdAsks.Candidate(ad: $0, chance: Self.askChance) }
      } else {
        taken += placed.skip
        asks += placed.ask.map { AdAsks.Candidate(ad: $0, chance: Self.askChance) }
      }
    }
    counts.append((finder, list.count))
  }

  /// The stretches the listener judged or was asked about: the snap's pull and the Mac's marks keep
  /// out of them.
  var judged: [(start: Double, end: Double)] {
    (file.denied ?? []).map { (start: $0.start, end: $0.end) }
      + (file.asks ?? []).map { (start: $0.start, end: $0.end) }
      + file.undone.map { (start: $0.start, end: $0.end) }
  }

  /// The file's ads and the skips, in order of time, with their borders put on the joints.
  func written(joints: Joints?, steadyToo: Bool) -> (file: AdsFile, moved: [NewAds.Moved]) {
    var out = file
    out.ads = (file.ads + AdJoin.join(taken)).sorted { $0.start < $1.start }
    var moved: [NewAds.Moved] = []
    if let joints {
      let snapped = NewAds.snap(
        out.ads, joints: joints, steadyToo: steadyToo, judged: self.judged, words: words,
        leaving: { NewAds.isFixed($0, in: out, words: words) })
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

  /// The maybes of the episode (PodcastAdFinder+Maybes.swift): the stretches the finders only
  /// asked about that did not become one of the `picked` questions (the cap or an overlap left
  /// them out), and the weak `spans` of the word model, of the sorts the listener skips and the
  /// settings do not switch off.
  func maybes(besides picked: [FoundAd], spans: [FoundAd]) -> [FoundAd] {
    askable(asks.map(\.ad).filter { ad in !picked.contains { NewAds.overlap($0, ad) } } + spans)
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
