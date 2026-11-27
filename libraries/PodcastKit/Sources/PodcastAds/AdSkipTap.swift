// LOFI-FORK: what a tap on skip forward does in a podcast with ads (see FORK.md and docs/PLAN.md,
// milestone X5). Plain values, no AVFoundation.
import Foundation

/// Where the skip forward button takes the listener when the episode has ads: the rule next to
/// `AdSkipNow.decide`, which is for the Skip ad button. The six cases are tried in this order,
/// and the first that fits decides.
public enum AdSkipTap {
  /// A hole between two skipped ads is bridged when it is this long or shorter.
  public static let longestHole = 60.0

  public enum Action: Equatable, Sendable {
    /// Move the playhead here: the plain move, or the end of the skipped ad it would land in.
    case plain(to: Double)
    /// The playhead is in a known ad: leave it like the Skip ad button (note, tally, Undo).
    case skip(AdSkip)
    /// The playhead is in the open question that starts here: the tap is the answer yes.
    case answer(start: Double)
    /// The playhead is in the maybe that starts here: it becomes a confirmed ad and is left.
    case confirm(start: Double)
    /// The playhead is in a short hole between two skipped ads: go to `to`; the miss to note runs
    /// from the playhead to `holeEnd`.
    case bridge(to: Double, holeEnd: Double)
  }

  /// What the tap does at `position`. `plain` is where the button's own move would land (ahead of
  /// `position`; the caller works it out). The cases:
  ///  1. Right after an automatic skip (as `AdSkipNow` defines it) cases 2 to 5 are off.
  ///  2. The playhead is in a known ad (any kind and confidence, cut by the trims, from
  ///     `AdSkipNow.leadSeconds` before its start, not undone): leave it and the ads that follow,
  ///     also over holes of `AdSkipNow.carryHole` seconds or less to ads the switches skip (see
  ///     `AdSkipNow.holder` and `AdsFile.carryBlocks`).
  ///  3. It is in an open question: the answer yes.
  ///  4. It is in a maybe: confirm it.
  ///  5. It is in a hole of `longestHole` seconds or less between two stretches of skipped ads,
  ///     with no undone or "no" stretch in it: go to the end of the stretch after the hole.
  ///  6. Otherwise the plain move, taken to the end of a skipped ad it would land in.
  /// With no file it is the plain move. The place is never behind the playhead.
  public static func decide(
    position: Double, plain: Double, duration: Double?, file: AdsFile?, settings: AdSkipSettings,
    lastSkip: AdSkip?, lastSkipAge: Double
  ) -> Action {
    let place = position.isFinite ? position : 0
    let move = plain.isFinite ? max(place, plain) : place
    guard let file else { return .plain(to: move) }
    if !AdSkipNow.isJustAfter(place, lastSkip: lastSkip, age: lastSkipAge) {
      if let known = known(at: place, duration: duration, file: file, settings: settings) {
        return .skip(known)
      }
      if let ask = AdAsking.live(in: file, at: place) { return .answer(start: ask.start) }
      if let maybe = AdMaybes.live(in: file, at: place) { return .confirm(start: maybe.start) }
      if let bridge = bridge(at: place, duration: duration, file: file, settings: settings) {
        return bridge
      }
    }
    let landing = AdSkipper(file: file, settings: settings).landing(for: move, duration: duration)
    return .plain(to: max(place, landing))
  }

  // MARK: The cases

  /// Case 2: the skip of the ad the playhead is in, with the ads that follow it.
  private static func known(
    at place: Double, duration: Double?, file: AdsFile, settings: AdSkipSettings
  ) -> AdSkip? {
    let ads = file.ads.filter { !file.isUndone($0) }.map { $0.trimmed(by: file.trims ?? []) }
      .filter { $0.end > $0.start }
    guard
      let (first, chained) = AdSkipNow.holder(
        of: place, in: ads, carrying: skippedAds(in: file, settings: settings),
        unless: file.carryBlocks(settings: settings))
    else { return nil }
    let target = AdSkipper.target(for: chained.last ?? first, duration: duration)
    return AdSkip(ad: first, target: max(place, target), chained: chained)
  }

  /// Case 5: the playhead is in a short hole between two stretches of skipped ads.
  private static func bridge(
    at place: Double, duration: Double?, file: AdsFile, settings: AdSkipSettings
  ) -> Action? {
    let stretches = skipped(in: file, settings: settings)
    guard !stretches.contains(where: { $0.start <= place && place < $0.end }),
      let before = stretches.last(where: { $0.end <= place }),
      let after = stretches.first(where: { $0.start > place }),
      after.start - before.end <= longestHole,
      !file.blockedStretches.contains(where: { $0.start < after.start && before.end < $0.end })
    else { return nil }
    let to = AdSkipper.target(for: after, duration: duration)
    return .bridge(to: max(place, to), holeEnd: after.start)
  }

  /// The ads the switches skip, as the player would (unsure or better, not undone, cut by the
  /// trims), in the order of the file. These are the ads a tap inside an ad may carry into.
  static func skippedAds(in file: AdsFile, settings: AdSkipSettings) -> [FoundAd] {
    file.ads.filter {
      $0.confidence >= .unsure && settings.allows($0.kind) && !file.isUndone($0)
    }.map { $0.trimmed(by: file.trims ?? []) }.filter { $0.end > $0.start }
  }

  /// The ads of `skippedAds` joined into stretches where they follow each other within
  /// `AdSkipper.chainGap`.
  private static func skipped(in file: AdsFile, settings: AdSkipSettings) -> [FoundAd] {
    let ads = skippedAds(in: file, settings: settings).sorted { $0.start < $1.start }
    var stretches: [FoundAd] = []
    for ad in ads {
      if var last = stretches.last, ad.start <= last.end + AdSkipper.chainGap {
        last.end = max(last.end, ad.end)
        stretches[stretches.count - 1] = last
      } else {
        stretches.append(ad)
      }
    }
    return stretches
  }
}

extension AdsFile {
  /// The stretches that stop a carry or a bridge over a hole: the undone ones and the "no" answers.
  var blockedStretches: [(start: Double, end: Double)] {
    undone.map { ($0.start, $0.end) } + (denied ?? []).map { ($0.start, $0.end) }
  }

  /// The stretches a tap's carry does not pass over (`AdSkipNow.holder`): the blocked stretches,
  /// the ads of a kind the listener keeps (their switch is off), and what a trim cut off an ad
  /// (the listener went back there to listen, so it is the show to them).
  func carryBlocks(settings: AdSkipSettings) -> [(start: Double, end: Double)] {
    var blocks = blockedStretches
    for ad in ads {
      let cut = ad.trimmed(by: trims ?? [])
      if cut.end < ad.end { blocks.append((start: cut.end, end: ad.end)) }
      if !settings.allows(ad.kind), cut.end > cut.start {
        blocks.append((start: cut.start, end: cut.end))
      }
    }
    return blocks
  }
}
