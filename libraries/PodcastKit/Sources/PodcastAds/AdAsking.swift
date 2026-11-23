// LOFI-FORK: the questions in an episode's ads file and what an answer does to it (see FORK.md
// and docs/PODCASTS-ADS-TEACHING.md). Foundation only.
import Foundation

/// The questions of one ads file (`AdsFile.asks`): which one is live at the playhead, what the
/// listener's answer changes, and which new questions may be added. `AdAsks` makes them.
///
/// A question is open until it is answered, and an answered one is never open again: a "yes"
/// moves it into `ads` as a sure ad, a "no" into `undone`, and a question that lies over an ad
/// or an undone stretch is not open whatever the file says. So a finder that asks about the same
/// stretch again, after a later pass, changes nothing.
public enum AdAsking {
  /// The `source` of an ad the listener confirmed by answering a question.
  public static let source = "tap"
  /// An answer names its question by the start the app was told, which may be a little off.
  static let startTolerance = 0.5

  // MARK: Reading

  /// The questions still waiting for an answer, by start. One that has no real time, or lies
  /// over an ad of the file (whatever its confidence) or over a stretch the listener undid, is
  /// not waiting.
  public static func open(in file: AdsFile) -> [FoundAd] {
    (file.asks ?? [])
      .filter { valid($0) && !covered($0, by: file) }
      .sorted { $0.start < $1.start }
  }

  /// The question the playhead is inside (from its start up to, not including, its end), or nil.
  public static func live(in file: AdsFile, at time: Double) -> FoundAd? {
    open(in: file).first { $0.start <= time && time < $0.end }
  }

  // MARK: Answering

  /// The file after the listener answered the open question that starts at `start` (within half
  /// a second). A "yes" (`isAd`) moves it into `ads` as a sure ad with the source "tap", placed
  /// by its start. A "no" moves it to `undone`, which `LocalAdsFile.carryChoices` carries to a
  /// new final file and which keeps the phone from asking about it again. Nil when no open
  /// question starts there, so answering twice does nothing. Questions that are no longer open
  /// are dropped from the list, and an empty list is written as none.
  public static func answer(_ file: AdsFile, askStart start: Double, isAd: Bool) -> AdsFile? {
    guard let ask = question(in: file, startingAt: start) else { return nil }
    var next = file
    var rest = open(in: file)
    rest.removeAll { $0 == ask }
    next.asks = rest.isEmpty ? nil : rest
    if isAd {
      var ad = ask
      ad.confidence = .sure
      ad.source = source
      next.ads.insert(ad, at: file.ads.firstIndex(where: { $0.start > ad.start }) ?? file.ads.count)
    } else {
      next.undone.append(UndoneAd(start: ask.start, end: ask.end))
    }
    return next
  }

  /// The same as `answer(_:askStart:isAd:)` on the episode's saved file for this detector (the
  /// final file, else the partial one), and saves it where it was found. Returns the question
  /// that was answered, or nil when there was none to answer or the file could not be saved.
  @discardableResult
  public static func answer(
    store: AdsStore, detector: String, askStart start: Double, isAd: Bool
  ) -> FoundAd? {
    let isFinal = store.load(detector: detector) != nil
    guard let file = store.best(detector: detector),
      let ask = question(in: file, startingAt: start),
      let changed = answer(file, askStart: start, isAd: isAd),
      (try? (isFinal ? store.save(changed) : store.savePartial(changed))) != nil
    else { return nil }
    return ask
  }

  // MARK: Adding

  /// The file with `asks` added, most likely first (the order `AdAsks` gives them). The file
  /// never holds more than `AdAsks.most` open questions, so only as many are added as there is
  /// room for. A question with no real time, or over an ad, an undone stretch or an open
  /// question, is left out. Every question is kept as a `guess`.
  public static func adding(_ asks: [FoundAd], to file: AdsFile) -> AdsFile {
    var kept = open(in: file)
    for ask in asks where kept.count < AdAsks.most {
      guard valid(ask), !covered(ask, by: file), !kept.contains(where: { AdAsks.overlap($0, ask) })
      else { continue }
      var question = ask
      question.confidence = .guess
      kept.append(question)
    }
    var next = file
    next.asks = kept.isEmpty ? nil : kept.sorted { $0.start < $1.start }
    return next
  }

  // MARK: Details

  /// The open question whose start is nearest to `start`, within `startTolerance`.
  private static func question(in file: AdsFile, startingAt start: Double) -> FoundAd? {
    open(in: file)
      .filter { abs($0.start - start) < startTolerance }
      .min { abs($0.start - start) < abs($1.start - start) }
  }

  private static func valid(_ ask: FoundAd) -> Bool {
    ask.start.isFinite && ask.end.isFinite && ask.end > ask.start
  }

  /// Whether the file already has an ad over the question, or the listener undid that stretch.
  private static func covered(_ ask: FoundAd, by file: AdsFile) -> Bool {
    file.ads.contains { AdAsks.overlap($0, ask) } || file.isUndone(ask)
  }
}
