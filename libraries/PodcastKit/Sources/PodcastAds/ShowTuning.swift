// LOFI-FORK: what the Mac's per-show settings let each new finder do (see FORK.md and the round
// plan, idea 7). Foundation only, no clock and no disk access: the text of `show-settings.json`
// is read in ShowTuning+File.swift and everything here works on the value in memory.
import Foundation

// THE FILE (`show-settings.json`, version 1) is one written rule for the Mac (teach_settings.py)
// and the phone:
//
//   {"version": 1, "writtenAt": 1700000000,
//    "default": {"finders": {"own-sound": "skip", "repeat-sound": "ask", "repeat-words": "ask",
//                            "meaning": "skip", "apple-model": "ask"}, "joints": true,
//                "steadyJoints": false, "ask": 0.35},
//    "shows": [{"feed": "<feed address>", "finders": {"repeat-words": "skip"},
//               "sorts": {"host_ask": "ask"}, "joints": false}]}
//
// Finder names are "own-sound", "repeat-sound", "repeat-words", "meaning" and "apple-model" (Apple's
// on-device model, which asks by default: its answers are questions, never skips, unless the file
// says "skip" for a show or for every show); sort names are the word model's classes ("sponsor",
// "network_promo", "host_ask", "intro_credits"); the levels are "skip", "ask" and "off". Any other
// name or level is ignored, so a build that does not know "apple-model" reads the same file and the
// file stays version 1. A show is named by its feed address and turned into the app's show id when
// the file is read. A show entry overrides the default block key by key, and the default block
// overrides the built-in default key by key.
//
// HOW THE PHONE USES IT. The phone takes the STRICTER of the finder guard's mode and the mode
// here (`stricter`: off before ask before skip), so a finder the guard has silenced stays
// silent whatever the file says.
//
// WHERE `apply` MUST RUN. On EACH new finder's own list of ads, BEFORE `AdJoin.join` and
// `AdCleanup`, never on a joined list. Only the `skip` list goes on to be joined; the `ask` list
// becomes questions. The reason is the `source`: `AdJoin` clears it when the parts of a joined ad
// come from different finders, and `AdCleanup` builds new ads without it, and an ad with no source
// counts as an older finder's ad, which skips. So a joined list of "repeat-words" and
// "repeat-sound" ads would skip even where both finders only ask. ShowTuningTests pins the order.
//
// THE NAMES. Each new finder must put the constant of this type in its ads' `source`: `ownSound`
// and `repeatSound` are used as they are. `repeatWords` and `meaning` repeat the strings of
// `RepeatedWords.source` and the meaning model's `MeaningAds.source`, which are in other packages
// of this round and cannot be imported here; the wiring package must check that they are equal.
// `appleModel` is the `source` of Apple's model's ads: `AppleAnswers.ads(for:)` (the scorecard) and
// `ModelPlacing` (the phone) both use it, through `AppleModelAds.source`. A finder whose `source`
// is not one of the five is not held back by finder levels.
//
// APPLE'S MODEL is an older finder, whose ads are in the ads files before the new finders run, so
// its level is applied where the model's ads are made (`ModelPlacing`, `AdsRunner`, the stream's
// head scan), still before any join. See AppleModelAds.swift.

/// The Mac's settings for each show, read from `show-settings.json`.
public struct ShowTuning: Sendable, Equatable {
  public static let fileName = "show-settings.json"
  public static let currentVersion = 1
  /// A file bigger than this reads as the built-in default (the limit of every teaching file).
  public static let maxBytes = TeachingFiles.maxBytes
  /// The names of the finders the file can set. A finder puts its name in `FoundAd.source`.
  public static let ownSound = "own-sound"
  public static let repeatSound = "repeat-sound"
  public static let repeatWords = "repeat-words"
  public static let meaning = "meaning"
  public static let appleModel = "apple-model"
  public static let finderNames = [ownSound, repeatSound, repeatWords, meaning, appleModel]
  /// The word model's classes, which the file can set for each kind of ad.
  public static let sortNames = ["sponsor", "network_promo", "host_ask", "intro_credits"]
  public static let defaultAsk = 0.35
  /// The one threshold is kept inside this, so a file cannot make the phone ask about nothing or
  /// about everything.
  public static let askRange: ClosedRange<Double> = 0.2...0.6

  /// The choices of one block of the file: only what it says.
  struct Choices: Sendable, Equatable {
    var finders: [String: FinderMode] = [:]
    var sorts: [String: FinderMode] = [:]
    var joints: Bool?
    var steadyJoints: Bool?

    /// This block with `top`'s choices on top of it, key by key.
    func overlaid(by top: Choices) -> Choices {
      Choices(
        finders: finders.merging(top.finders) { _, new in new },
        sorts: sorts.merging(top.sorts) { _, new in new },
        joints: top.joints ?? joints, steadyJoints: top.steadyJoints ?? steadyJoints)
    }
  }

  /// What the phone does when there is no file: the Mac's default block.
  static let builtIn = Choices(
    finders: [
      ownSound: .skip, repeatSound: .ask, repeatWords: .ask, meaning: .skip, appleModel: .ask,
    ],
    sorts: [:], joints: true, steadyJoints: false)

  /// The built-in default with the file's default block on top.
  var base = ShowTuning.builtIn
  /// Each show's own entry, by the app's show id.
  var shows: [String: Choices] = [:]
  /// The chance above which the phone asks about a stretch it is not sure of (0.2 to 0.6).
  public internal(set) var askThreshold = ShowTuning.defaultAsk

  /// The built-in default: what the phone does with no file.
  public init() {}

  // MARK: Asking

  /// What `finder` may do on `show`. A name that is not one of the five is not held back.
  public func level(forFinder finder: String, show: String) -> FinderMode {
    shows[show]?.finders[finder] ?? base.finders[finder] ?? .skip
  }

  /// What may be done with ads of this sort (a class of the word model) on `show`.
  public func level(forSort sort: String, show: String) -> FinderMode {
    shows[show]?.sorts[sort] ?? base.sorts[sort] ?? .skip
  }

  /// Whether borders snap onto the joints of the file on `show`.
  public func joints(show: String) -> Bool {
    shows[show]?.joints ?? base.joints ?? true
  }

  /// Whether joints are also used in files whose frames are all alike (a steady file).
  public func steadyJoints(show: String) -> Bool {
    shows[show]?.steadyJoints ?? base.steadyJoints ?? false
  }

  /// The stricter of two modes: off before ask before skip.
  public static func stricter(_ first: FinderMode, _ second: FinderMode) -> FinderMode {
    rank(first) >= rank(second) ? first : second
  }

  private static func rank(_ mode: FinderMode) -> Int {
    switch mode {
    case .skip: return 0
    case .ask: return 1
    case .off: return 2
    }
  }

  // MARK: Applying

  /// Sorts `ads` for `show`. Call it on one finder's own list, before `AdJoin` (see the header). An
  /// ad whose finder (`source`) or sort is off is dropped; one whose finder or sort only asks goes
  /// to `ask`, the rest to `skip`; the stricter of the two levels decides. An ad with no source,
  /// or the source of something that is not one of the five finders ("tap"), is not touched by
  /// finder levels. Order and ads are kept as they were.
  public func apply(to ads: [FoundAd], show: String) -> (skip: [FoundAd], ask: [FoundAd]) {
    var skip: [FoundAd] = []
    var ask: [FoundAd] = []
    for ad in ads {
      let byFinder = ad.source.map { level(forFinder: $0, show: show) } ?? .skip
      switch Self.stricter(byFinder, level(forSort: ad.kind.sortName, show: show)) {
      case .skip: skip.append(ad)
      case .ask: ask.append(ad)
      case .off: break
      }
    }
    return (skip, ask)
  }
}

extension AdKind {
  /// The word model's class of this kind of ad (the reverse of `init(sort:)`).
  var sortName: String {
    switch self {
    case .ad: return "sponsor"
    case .promo: return "network_promo"
    case .ownPlug: return "host_ask"
    case .credits: return "intro_credits"
    }
  }
}
