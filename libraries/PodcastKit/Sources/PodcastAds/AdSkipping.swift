// LOFI-FORK: when the player skips an ad (see FORK.md). Plain values, no AVFoundation.
import Foundation

/// The listener's four switches: sponsor ads, the hosts' own plugs and the show's promos are on
/// until they turn them off; credits are off until they turn them on.
public struct AdSkipSettings: Equatable, Sendable {
  /// Skip sponsor reads and other produced ads.
  public var skipAds: Bool
  /// Skip the hosts' own plugs (Patreon, merch, asking for a review).
  public var skipOwnPlugs: Bool
  /// Skip the show's or its network's promos for something of its own (another show, a live
  /// event, tickets, a subscription, an app).
  public var skipPromos: Bool
  /// Skip the standing opening and the closing credits.
  public var skipCredits: Bool

  public init(
    skipAds: Bool = true, skipOwnPlugs: Bool = true, skipPromos: Bool = true,
    skipCredits: Bool = false
  ) {
    self.skipAds = skipAds
    self.skipOwnPlugs = skipOwnPlugs
    self.skipPromos = skipPromos
    self.skipCredits = skipCredits
  }

  /// These switches with a show's own choices where it has them (nil keeps the listener's). A
  /// show overrides the first two. Promos used to be ads, so a show that turns ad skipping off
  /// (`false`) does not have its promos skipped either; a show's choice of on, or none, leaves
  /// the promo switch as the listener set it. The credits switch stays the listener's.
  public func overridden(skipAds show: Bool?, skipOwnPlugs showPlugs: Bool?) -> AdSkipSettings {
    AdSkipSettings(
      skipAds: show ?? skipAds, skipOwnPlugs: showPlugs ?? skipOwnPlugs,
      skipPromos: show == false ? false : skipPromos, skipCredits: skipCredits)
  }

  /// Whether a stretch of this kind may be skipped under these switches.
  public func allows(_ kind: AdKind) -> Bool {
    switch kind {
    case .ad: return skipAds
    case .ownPlug: return skipOwnPlugs
    case .promo: return skipPromos
    case .credits: return skipCredits
    }
  }
}

/// A skip the player is to make: jump to `target` seconds.
public struct AdSkip: Equatable, Sendable {
  public var ad: FoundAd
  public var target: Double
  /// The stretches that follow `ad` at once (an ad and then the hosts' plug), skipped with it. Only
  /// kinds the switches allow are ever in it.
  public var chained: [FoundAd]

  public init(ad: FoundAd, target: Double, chained: [FoundAd] = []) {
    self.ad = ad
    self.target = target
    self.chained = chained
  }

  /// Where the skipped stretch ends according to the ads (the target may be a little earlier at
  /// the end of the episode).
  public var end: Double { chained.last?.end ?? ad.end }
}

/// The player's decisions about ads in one loaded episode. The player sets a marker at each
/// `boundaryTimes` entry and calls `reached` when playback crosses one; it calls `seeked`
/// whenever the listener (or the app) moves the playhead and `undo` for the Undo button.
public struct AdSkipper: Sendable {
  /// The wrong skips can be undone for this long (the app shows the note for 6 seconds).
  public static let undoSeconds = 6.0
  /// A little more, for the time the tap takes to get here.
  public static let undoGrace = 2.0
  /// A marker is set this far in when an ad starts at the very start, because a marker at
  /// zero is never crossed.
  static let firstBoundary = 0.05
  /// An ad that starts this close to where the one before ends is skipped with it.
  static let chainGap = 0.5
  /// An ad that is found while it plays is left only when at least this much of it (with the
  /// ads skipped along with it) is still ahead. A jump costs about a second of seeking and
  /// re-buffering and the "Skipped ad" note, so a shorter rest is cheaper to hear than to skip.
  public static let leaveMinimum = 3.0
  /// A skip is found "too far" when the listener goes back into it at most this long after it.
  public static let tooFarSeconds = 20.0
  /// ... and at most this far before where the skip landed.
  public static let tooFarReach = 60.0

  /// The sure and unsure ads that were not undone before, whatever the switches say.
  private var candidates: [FoundAd]
  public private(set) var settings: AdSkipSettings
  /// Where the playhead was put last, and the ads it landed in.
  private var lastSeek: Double?
  private var enteredBySeek: Set<Double> = []
  /// What the listener undid in this episode, so far: an ad found again a second later (the
  /// model's first line, a pause snap) is the same ad.
  private var undone: [(start: Double, end: Double)] = []
  /// What the listener found too far in this episode, so far. The file's own trims are read from
  /// the file; these stay when the file is read again before it holds them.
  private var trims: [AdTrim] = []
  /// Where the ads left in progress were skipped to (start and end), so a second look at the
  /// same file does not jump again before the first jump has landed, while an ad that is found
  /// again longer (cut short at the edge of the first pass) is left once more.
  private var left: [(start: Double, end: Double)] = []
  private var last: (skip: AdSkip, at: Double)?

  /// - Parameter file: the episode's ads file, nil when it has none. Sure and unsure ads that
  ///   the listener did not undo before are skipped (Undo takes a wrong skip back for good);
  ///   guesses are never in the file.
  public init(file: AdsFile?, settings: AdSkipSettings) {
    self.settings = settings
    candidates = Self.candidates(in: file, trims: [])
  }

  /// The ads of the file as they are skipped: cut short by the trims, and without the ones that
  /// are not worth a skip.
  private static func candidates(in file: AdsFile?, trims: [AdTrim]) -> [FoundAd] {
    let allTrims = (file?.trims ?? []) + trims
    return (file?.ads ?? []).filter { ad in
      ad.confidence >= .unsure && file?.isUndone(ad) == false
    }.map { $0.trimmed(by: allTrims) }.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
  }

  /// The ads file changed (ads were found while the episode plays). Where the playhead was put
  /// last and what was undone stay, so the new ads are treated as if they had been there.
  public mutating func replace(file: AdsFile?) {
    candidates = Self.candidates(in: file, trims: trims)
    if let lastSeek { seeked(to: lastSeek) }
  }

  /// Like `replace(file:)`, for the player while the episode plays at `playhead` (nil when it is
  /// not playing): when the playhead is inside an ad that is to be skipped, the skip to make at
  /// once. Not when the listener seeked into that ad (a manual seek is respected, also after
  /// the ad was found), when the ad was undone, when its switch is off, when it was left this
  /// way already, or when less than `leaveMinimum` seconds of it are left.
  public mutating func replace(
    file: AdsFile?, playhead: Double?, duration: Double?, now: Double
  ) -> AdSkip? {
    replace(file: file)
    guard let playhead, playhead.isFinite,
      let ad = ads.first(where: { $0.start <= playhead && playhead < $0.end }),
      !enteredBySeek.contains(ad.start), !wasLeft(ad),
      chainEnd(of: ad) - playhead >= Self.leaveMinimum
    else { return nil }
    left.append((ad.start, ad.end))
    return makeSkip(ad, duration: duration, now: now)
  }

  /// Whether a jump out of this ad (or out of one that ended no sooner) was made already.
  private func wasLeft(_ ad: FoundAd) -> Bool {
    left.contains { $0.start < ad.end && ad.start < $0.end && $0.end >= ad.end - 0.5 }
  }

  /// The ads that will be skipped under the current switches.
  public var ads: [FoundAd] { candidates.filter { settings.allows($0.kind) && !isUndone($0) } }

  /// Whether an ad overlaps a stretch the listener undid.
  private func isUndone(_ ad: FoundAd) -> Bool {
    undone.contains { $0.start < ad.end && ad.start < $0.end }
  }

  /// Where to set the markers, in seconds, in order.
  public var boundaryTimes: [Double] { ads.map { max(Self.firstBoundary, $0.start) } }

  /// The switches changed. What was entered by a seek and what was undone stays.
  public mutating func apply(settings: AdSkipSettings) { self.settings = settings }

  /// The playhead is being moved to `position` by the listener (Back 10 s, the seek bar, a lock
  /// screen button). When that is at most `tooFarSeconds` after a skip, lands before where the
  /// skip landed, at most `tooFarReach` seconds before it and inside the skipped stretch, the
  /// skip went too far: the trim to save, and from now on that ad ends at `position`. Nil
  /// otherwise (also when the seek would not make the ad any shorter). Call it before
  /// `seeked(to:)`, so the ad is already shorter when that looks at where the seek landed.
  @discardableResult
  public mutating func backSeek(to position: Double, now: Double) -> AdTrim? {
    guard position.isFinite, let last, now - last.at <= Self.tooFarSeconds,
      position < last.skip.target, last.skip.target - position <= Self.tooFarReach,
      let held = ([last.skip.ad] + last.skip.chained).last(where: { $0.start < position })
    else { return nil }
    let currentEnd = candidates.first { $0.start == held.start }?.end ?? held.end
    guard position < currentEnd else { return nil }
    let trim = AdTrim(adStart: held.start, end: position)
    trims.append(trim)
    candidates = candidates.map { $0.trimmed(by: [trim]) }
    return trim
  }

  /// The playhead was moved to `position`. An ad it lands in is not skipped, so a seek into an
  /// ad (and Undo, and playing from an ad's start in the list) plays it.
  public mutating func seeked(to position: Double) {
    lastSeek = position
    enteredBySeek = Set(candidates.filter { $0.start <= position && position < $0.end }.map(\.start))
  }

  /// An episode was loaded to start at `position`. That is the app's choice and not the listener's
  /// seek, so an ad that starts later is skipped as usual. When the start lies inside an ad that is
  /// to be skipped, the skip to make at once.
  public mutating func started(at position: Double, duration: Double?, now: Double) -> AdSkip? {
    lastSeek = nil
    enteredBySeek = []
    left = []
    guard position.isFinite,
      let ad = ads.first(where: { $0.start <= position && position < $0.end })
    else { return nil }
    return makeSkip(ad, duration: duration, now: now)
  }

  /// The skip for `ad`, taking on the ads that start within `chainGap` of where it ends.
  private mutating func makeSkip(_ ad: FoundAd, duration: Double?, now: Double) -> AdSkip {
    let chained = chain(after: ad)
    let skip = AdSkip(
      ad: ad, target: Self.target(for: chained.last ?? ad, duration: duration), chained: chained)
    last = (skip, now)
    return skip
  }

  /// The ads that follow `ad` at once, in order.
  private func chain(after ad: FoundAd) -> [FoundAd] {
    var chained: [FoundAd] = []
    var end = ad.end
    for next in ads where next.start > ad.start && !chained.contains(next) && next != ad {
      if next.start <= end + Self.chainGap && next.end > end {
        chained.append(next)
        end = next.end
      }
    }
    return chained
  }

  private func chainEnd(of ad: FoundAd) -> Double { chain(after: ad).last?.end ?? ad.end }

  /// How far past a marker playback may be when the player is told about it and still count as
  /// having reached it: more at a higher speed, because the same delay covers more audio. Past
  /// that, the listener got there by seeking.
  public static func reachWindow(rate: Double) -> Double {
    1.0 + (rate.isFinite && rate > 1 ? rate : 1)
  }

  /// Where a skip of this ad lands. An ad that runs to the end of the episode lands just
  /// before it, so the episode ends as it would have.
  public static func target(for ad: FoundAd, duration: Double?) -> Double {
    guard let duration, duration.isFinite, duration > 0 else { return ad.end }
    if ad.end >= duration - 0.5 { return max(ad.start, duration - 0.05) }
    return ad.end
  }

  /// Playback crossed a marker at `position` while playing at `rate`. The skip to make, or
  /// nil when the playhead is not at the start of an ad that is to be skipped (it got into
  /// it by a seek, the ad was undone, or its switch is off). `now` is any steady clock in
  /// seconds, kept for Undo.
  public mutating func reached(
    position: Double, rate: Double, duration: Double?, now: Double
  ) -> AdSkip? {
    guard position.isFinite else { return nil }
    let window = Self.reachWindow(rate: rate)
    guard
      let ad = ads.last(where: {
        let boundary = max(Self.firstBoundary, $0.start)
        return position >= boundary - 0.5 && position <= boundary + window
      }),
      !enteredBySeek.contains(ad.start)
    else { return nil }
    return makeSkip(ad, duration: duration, now: now)
  }

  /// The last skip that can still be undone and when it was made (the `now` it was made with).
  public var lastSkip: (skip: AdSkip, at: Double)? { last }

  /// A skip that was made by hand (the Skip ad button), so Undo takes it back like any other.
  public mutating func noteSkip(_ skip: AdSkip, now: Double) { last = (skip, now) }

  /// Where the player lands when it moves the playhead to `position` on its own and does not want
  /// to land inside an ad that is skipped: the end of that ad and of the ads that follow it at
  /// once, or `position` when no such ad holds it.
  public func landing(for position: Double, duration: Double?) -> Double {
    guard position.isFinite, let ad = ads.first(where: { $0.start <= position && position < $0.end })
    else { return position }
    return max(position, Self.target(for: chain(after: ad).last ?? ad, duration: duration))
  }

  /// The listener tapped Undo: the ad that was just skipped, to be played from its start, or nil
  /// when nothing was skipped lately. The ad is not skipped again.
  public mutating func undo(now: Double) -> FoundAd? { undoSkip(now: now)?.ad }

  /// Like `undo`, but gives back the whole skip, so the ads that were skipped with the first
  /// one (an ad and then the hosts' plug) can be saved as undone as well.
  public mutating func undoSkip(now: Double) -> AdSkip? {
    guard let last, now - last.at <= Self.undoSeconds + Self.undoGrace else { return nil }
    for undid in [last.skip.ad] + last.skip.chained { undone.append((undid.start, undid.end)) }
    self.last = nil
    return last.skip
  }
}
