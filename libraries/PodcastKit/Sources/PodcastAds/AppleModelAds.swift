// LOFI-FORK: what the phone and the scorecard do with the ads of Apple's on-device model on one
// show (see FORK.md, ShowTuning.swift and AdsRunner.swift). Foundation only, no clock, no disk.
import Foundation

/// Apple's model asks by default. On the 63 shelf episodes its answers cost 183 skips with no ad
/// (20 without them), so they become questions (`AdsFile.asks`, at most three an episode) unless
/// the Mac's `show-settings.json` says "skip" for a show or for every show. The rules are the ones
/// of every new finder (`ShowTuning.apply`, run on the finder's own list before any join), plus
/// the finder guard's mode: the stricter of the two wins.
public enum AppleModelAds {
  /// The `source` of the model's ads, which `ShowTuning` knows as the finder "apple-model".
  public static let source = ShowTuning.appleModel

  /// What the model may do on `show`: the stricter of the finder guard's mode (`guarded`, `.skip`
  /// when nothing is known) and the Mac's settings.
  public static func level(guarded: FinderMode, tuning: ShowTuning, show: String) -> FinderMode {
    ShowTuning.stricter(guarded, tuning.level(forFinder: source, show: show))
  }

  /// The model's ads of one list, named, sorted into what skips and what only asks. At the level
  /// `skip` the settings sort them (a sort that only asks goes to `ask`, one that is off is
  /// dropped); at the level `ask` every one that is not dropped asks, in the order of time; at
  /// `off` all are dropped. Their confidence stays as the model gave it.
  public static func place(
    _ ads: [FoundAd], level: FinderMode, tuning: ShowTuning, show: String
  ) -> (skip: [FoundAd], ask: [FoundAd]) {
    guard level != .off else { return ([], []) }
    let named = ads.map { ad -> FoundAd in
      var one = ad
      one.source = source
      return one
    }
    let placed = tuning.apply(to: named, show: show)
    guard level == .skip else {
      return ([], (placed.skip + placed.ask).sorted { $0.start < $1.start })
    }
    return placed
  }
}

/// What a run of the model does with its ads for one show (`AdsRunner.run` and `runPartial`):
/// only the ads that may skip go into the ads files, and the ones that only ask are kept here for
/// the questions (`asked`, of the last list the run made). A run with no placing keeps every ad,
/// with no source, as the Mac's tools do.
public final class ModelPlacing: @unchecked Sendable {
  public let level: FinderMode
  public let tuning: ShowTuning
  public let show: String
  private let lock = NSLock()
  private var questions: [FoundAd] = []

  public init(level: FinderMode, tuning: ShowTuning, show: String) {
    self.level = level
    self.tuning = tuning
    self.show = show
  }

  /// The ads of the list that may skip, named after the model. The ones that only ask replace
  /// what `asked` held.
  public func keep(_ ads: [FoundAd]) -> [FoundAd] {
    let placed = AppleModelAds.place(ads, level: level, tuning: tuning, show: show)
    lock.withLock { questions = placed.ask }
    return placed.skip
  }

  /// The ads of the last list that only ask, in the model's order.
  public var asked: [FoundAd] { lock.withLock { questions } }
}
