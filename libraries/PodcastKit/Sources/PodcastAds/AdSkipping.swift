// LOFI-FORK: when the player skips an ad (see FORK.md). Plain values, no AVFoundation.
import Foundation

/// The listener's two switches, both on until they turn them off.
public struct AdSkipSettings: Equatable, Sendable {
  /// Skip sponsor reads and other produced ads.
  public var skipAds: Bool
  /// Skip the hosts' own plugs (Patreon, merch, their other shows).
  public var skipOwnPlugs: Bool

  public init(skipAds: Bool = true, skipOwnPlugs: Bool = true) {
    self.skipAds = skipAds
    self.skipOwnPlugs = skipOwnPlugs
  }

  /// These switches with a show's own choices where it has them (nil keeps the listener's).
  public func overridden(skipAds show: Bool?, skipOwnPlugs showPlugs: Bool?) -> AdSkipSettings {
    AdSkipSettings(skipAds: show ?? skipAds, skipOwnPlugs: showPlugs ?? skipOwnPlugs)
  }

  /// Whether an ad of this kind may be skipped under these switches.
  public func allows(_ kind: AdKind) -> Bool {
    switch kind {
    case .ad: return skipAds
    case .ownPlug: return skipOwnPlugs
    }
  }
}

/// A skip the player is to make: jump to `target` seconds.
public struct AdSkip: Equatable, Sendable {
  public var ad: FoundAd
  public var target: Double
  /// The ads that follow `ad` at once (an ad and then the hosts' plug), skipped with it.
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

  /// The sure and unsure ads that were not undone before, whatever the switches say.
  private var candidates: [FoundAd]
  public private(set) var settings: AdSkipSettings
  /// Where the playhead was put last, and the ads it landed in.
  private var lastSeek: Double?
  private var enteredBySeek: Set<Double> = []
  private var undone: Set<Double> = []
  private var last: (skip: AdSkip, at: Double)?

  /// - Parameter file: the episode's ads file, nil when it has none. Sure and unsure ads that
  ///   the listener did not undo before are skipped (Undo takes a wrong skip back for good);
  ///   guesses are never in the file.
  public init(file: AdsFile?, settings: AdSkipSettings) {
    self.settings = settings
    candidates = Self.candidates(in: file)
  }

  private static func candidates(in file: AdsFile?) -> [FoundAd] {
    (file?.ads ?? []).filter { ad in
      ad.confidence >= .unsure && file?.isUndone(ad) == false && ad.end > ad.start
    }.sorted { $0.start < $1.start }
  }

  /// The ads file changed (ads were found while the episode plays). Where the playhead was put
  /// last and what was undone stay, so the new ads are treated as if they had been there.
  public mutating func replace(file: AdsFile?) {
    candidates = Self.candidates(in: file)
    if let lastSeek { seeked(to: lastSeek) }
  }

  /// The ads that will be skipped under the current switches.
  public var ads: [FoundAd] { candidates.filter { settings.allows($0.kind) && !undone.contains($0.start) } }

  /// Where to set the markers, in seconds, in order.
  public var boundaryTimes: [Double] { ads.map { max(Self.firstBoundary, $0.start) } }

  /// The switches changed. What was entered by a seek and what was undone stays.
  public mutating func apply(settings: AdSkipSettings) { self.settings = settings }

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
    guard position.isFinite,
      let ad = ads.first(where: { $0.start <= position && position < $0.end })
    else { return nil }
    return makeSkip(ad, duration: duration, now: now)
  }

  /// The skip for `ad`, taking on the ads that start within `chainGap` of where it ends.
  private mutating func makeSkip(_ ad: FoundAd, duration: Double?, now: Double) -> AdSkip {
    var chained: [FoundAd] = []
    var end = ad.end
    for next in ads where next.start > ad.start && !chained.contains(next) && next != ad {
      if next.start <= end + Self.chainGap && next.end > end {
        chained.append(next)
        end = next.end
      }
    }
    let skip = AdSkip(
      ad: ad, target: Self.target(for: chained.last ?? ad, duration: duration), chained: chained)
    last = (skip, now)
    return skip
  }

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

  /// The listener tapped Undo: the ad that was just skipped, to be played from its start, or nil
  /// when nothing was skipped lately. The ad is not skipped again.
  public mutating func undo(now: Double) -> FoundAd? { undoSkip(now: now)?.ad }

  /// Like `undo`, but gives back the whole skip, so the ads that were skipped with the first
  /// one (an ad and then the hosts' plug) can be saved as undone as well.
  public mutating func undoSkip(now: Double) -> AdSkip? {
    guard let last, now - last.at <= Self.undoSeconds + Self.undoGrace else { return nil }
    undone.insert(last.skip.ad.start)
    for later in last.skip.chained { undone.insert(later.start) }
    self.last = nil
    return last.skip
  }
}
