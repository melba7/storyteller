// LOFI-FORK: the ahead finder's one look at an episode whose ads file is final already (see
// FORK.md, AheadAds.swift and PodcastAdFinder+Ahead.swift). Foundation only.
import Foundation

// WHY A PASS OF ITS OWN. The Mac marks an episode at night, but the phone has usually downloaded
// and checked that episode the evening before, so its final ads file is made when the marks come.
// This is what the phone does then, without the model and without the sounds: the finder is run over
// the stored transcript, and what it finds is put into the file as every new finder's ads are: the
// parts outside the ads that are there, never over a stretch the listener undid or said no to, sorted
// by the settings of the show (`ShowTuning.apply`) before any join, at most unsure so the listener can
// undo them, and the half matches only as questions. What the listener did is never touched.

public enum AheadPass {
  /// A new ad stays this far from every ad of the file (the phone's `NewAds.apart`): `AdJoin` joins
  /// ads that lie within half a second, and the older ad must keep its borders and its name.
  public static let apart = 0.6
  /// The chance a question of this finder has when the questions are ranked (as every finder that
  /// has no model behind it).
  public static let askChance = 0.5

  /// What the pass made of the file.
  public struct Made: Equatable, Sendable {
    /// The file with the finder's ads and questions in it, or the file as it was.
    public var file: AdsFile
    /// How many ads were added to skip, and how many questions.
    public var skips: Int
    public var questions: Int
  }

  /// The stretches the finder keeps out of: the ones the listener said no to, was asked about or
  /// undid. Pass them to `AheadAds.find`.
  public static func judged(in file: AdsFile) -> [(start: Double, end: Double)] {
    (file.denied ?? []).map { (start: $0.start, end: $0.end) }
      + (file.asks ?? []).map { (start: $0.start, end: $0.end) }
      + file.undone.map { (start: $0.start, end: $0.end) }
  }

  /// `file` with what `found` gives. `level` is what the finder may do on this show and episode (the
  /// stricter of the guard and the settings): off adds nothing, ask only asks. `listener` has the
  /// sorts the listener skips: an ad of another sort is left out.
  public static func merge(
    _ found: AheadFound, into file: AdsFile, show: String, listener: AdSkipSettings,
    tuning: ShowTuning, level: FinderMode
  ) -> Made {
    // A prepared file holds the Mac's marks on that very copy; no word match adds to it.
    guard level != .off, !file.isPrepared else { return Made(file: file, skips: 0, questions: 0) }
    let whole = candidates(found.ads, in: file, listener: listener, blockers: file.ads)
    let placed = tuning.apply(to: whole, show: show)
    var skips: [FoundAd] = []
    var asked = placed.ask
    if level == .skip {
      skips = AdJoin.join(placed.skip)
    } else {
      asked += placed.skip
    }
    // The half matches only ask, and they keep away from the skips that were just added too.
    let unsure = candidates(found.asks, in: file, listener: listener, blockers: file.ads + skips)
    let half = tuning.apply(to: unsure, show: show)
    asked += half.skip + half.ask

    var made = file
    made.ads = (file.ads + skips).sorted { $0.start < $1.start }
    let questions = AdAsks.pick(
      asked.map { AdAsks.Candidate(ad: $0, chance: askChance) }, outside: made.ads)
    made = AdAsking.adding(questions, to: made)
    return Made(
      file: made, skips: skips.count,
      questions: (made.asks?.count ?? 0) - (file.asks?.count ?? 0))
  }

  /// The ads of one list as this finder's: of the sorts the listener skips, named, at most unsure,
  /// only the parts outside `blockers`, and not over a stretch the listener undid or said no to.
  private static func candidates(
    _ ads: [FoundAd], in file: AdsFile, listener: AdSkipSettings, blockers: [FoundAd]
  ) -> [FoundAd] {
    let mine = ads.filter { listener.allows($0.kind) }.map { ad -> FoundAd in
      var one = ad
      one.source = AheadAds.source
      one.confidence = min(ad.confidence, .unsure)
      return one
    }
    return ScoreAds.outside(AdJoin.join(mine), of: blockers, apart: apart).filter { ad in
      !file.isUndone(ad)
        && !(file.denied ?? []).contains { $0.start < ad.end && ad.start < $0.end }
    }
  }
}
