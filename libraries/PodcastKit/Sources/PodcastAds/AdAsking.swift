// LOFI-FORK: the questions in an episode's ads file and what an answer does to it (see FORK.md
// and docs/PODCASTS-ADS-TEACHING.md). Foundation only.
import Foundation

/// The questions of one ads file (`AdsFile.asks`): which one is live at the playhead, what the
/// listener's answer changes, and which new questions may be added. `AdAsks` makes them.
///
/// A question stays in `asks` for good, so that the cap of `AdAsks.most` questions an episode
/// counts the answered ones too. It is open (`open(in:)`, `live(in:at:)`) until it is answered
/// or covered: a "yes" puts a sure ad with the source "tap" over it, a "no" puts its stretch in
/// `AdsFile.denied`, and a question that lies over an ad or an undone stretch is not open
/// whatever the file says. So a finder that asks about the same stretch again, after a later
/// pass, changes nothing. A "no" goes to `denied` and never to `undone`, because `undone`
/// stops any ad that overlaps it, and a question often lies next to a real ad.
///
/// WHAT THE WIRING MUST DO (every point matters):
///  1. Make questions only from WHOLE-transcript passes, never from partial ones: a partial
///     pass sees part of the episode, and its questions would use up the cap of three before
///     the rest is read.
///  2. Every write of an ads file through `AdsStore` (`save`, `savePartial`) carries the
///     questions, the "no" answers and the confirmed ads of the file already saved
///     (`carrying`), so a model's checkpoint or final file cannot wipe them. The questions that
///     were saved come first and the cap holds, so a file loaded before an answer cannot bring
///     the count over three or bring an answered question back.
///  3. `answer` returns nil when the question is hidden (an ad already covers it, or it was
///     answered): the caller must still skip in that case, because the listener pressed Skip.
///  4. A confirmed ad that `AdJoin` later joins with an overlapping ad loses its `source` (a
///     joined ad keeps a source only when every part has it). `KnownAds.learnTapped` already
///     counted the confirmed stretch, so the known-ads learn from the whole file must also skip
///     any ad that overlaps an ad with the source "tap" that was counted already.
public enum AdAsking {
  /// The `source` of an ad the listener confirmed by answering a question.
  public static let source = "tap"
  /// An answer names its question by the start the app was told, which may be a little off.
  static let startTolerance = 0.5

  // MARK: Reading

  /// The questions still waiting for an answer, by start. One that has no real time, or lies
  /// over an ad of the file (whatever its confidence), over a stretch the listener undid or over
  /// one they said "not an ad" to, is not waiting.
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
  /// a second). A "yes" (`isAd`) puts the question in `ads` as a sure ad with the source "tap",
  /// placed by its start. A "no" adds its stretch to `denied`, which keeps the phone from asking
  /// about it again and never stops an ad. The question stays in `asks` either way. Nil when no
  /// open question starts there, so answering twice does nothing.
  public static func answer(_ file: AdsFile, askStart start: Double, isAd: Bool) -> AdsFile? {
    guard let ask = question(in: file, startingAt: start) else { return nil }
    var next = file
    if isAd {
      var ad = ask
      ad.confidence = .sure
      ad.source = source
      let at = file.ads.firstIndex(where: { $0.start > ad.start }) ?? file.ads.count
      next.ads.insert(ad, at: at)
    } else {
      next.denied = (file.denied ?? []) + [UndoneAd(start: ask.start, end: ask.end)]
    }
    return next
  }

  /// The same as `answer(_:askStart:isAd:)` on the episode's saved file for this detector (the
  /// final file, else the partial one; each is read once), and saves it where it was found.
  /// Returns the question that was answered, or nil when there was none to answer or the file
  /// could not be saved.
  @discardableResult
  public static func answer(
    store: AdsStore, detector: String, askStart start: Double, isAd: Bool
  ) -> FoundAd? {
    let final = store.load(detector: detector)
    guard let file = final ?? store.loadPartial(detector: detector),
      let ask = question(in: file, startingAt: start),
      let changed = answer(file, askStart: start, isAd: isAd),
      (try? (final != nil ? store.save(changed) : store.savePartial(changed))) != nil
    else { return nil }
    return ask
  }

  // MARK: Adding

  /// The file with `asks` added, most likely first (the order `AdAsks` gives them). The file
  /// never holds more than `AdAsks.most` questions in all, answered ones included, so only as
  /// many are added as there is room for. A question with no real time, or over an ad, an
  /// undone or denied stretch or a question already in the file, is left out. Every question is
  /// kept as a `guess`, and the list is kept by start.
  public static func adding(_ asks: [FoundAd], to file: AdsFile) -> AdsFile {
    var stored = file.asks ?? []
    for ask in asks where stored.count < AdAsks.most {
      guard valid(ask), !covered(ask, by: file), !stored.contains(where: { AdAsks.overlap($0, ask) })
      else { continue }
      var question = ask
      question.confidence = .guess
      stored.append(question)
    }
    var next = file
    next.asks = stored.isEmpty ? nil : stored.sorted { $0.start < $1.start }
    return next
  }

  // MARK: Carrying

  /// `file` with what `earlier` (the file saved before it, of the same detector) holds of the
  /// listener's answers: the saved questions come first, so the count stays at most
  /// `AdAsks.most`, and those of `file` are added where they overlap none; every "no"; and
  /// every ad with the source "tap" that overlaps no ad of `file` (a model that found the same
  /// ad keeps its own). Ads stay in order of start. `AdsStore.carryingTrims` calls this on
  /// every write, so a fresh file made by a finder cannot wipe an answer.
  static func carrying(_ earlier: AdsFile, into file: AdsFile) -> AdsFile {
    var carried = file
    if let saved = earlier.asks, !saved.isEmpty {
      var all = Array(saved.filter(valid).prefix(AdAsks.most))
      for ask in file.asks ?? [] where all.count < AdAsks.most && valid(ask) {
        if !all.contains(where: { AdAsks.overlap($0, ask) }) { all.append(ask) }
      }
      carried.asks = all.sorted { $0.start < $1.start }
    }
    for no in earlier.denied ?? [] where !(carried.denied ?? []).contains(no) {
      carried.denied = (carried.denied ?? []) + [no]
    }
    for ad in earlier.ads where ad.source == source {
      guard !carried.ads.contains(where: { AdAsks.overlap($0, ad) }) else { continue }
      let at = carried.ads.firstIndex(where: { $0.start > ad.start }) ?? carried.ads.count
      carried.ads.insert(ad, at: at)
    }
    return carried
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

  /// Whether the file already has an ad over the question, or the listener undid that stretch
  /// or said "not an ad" to it. Ads are never compared with `denied`; this is the other way.
  private static func covered(_ ask: FoundAd, by file: AdsFile) -> Bool {
    func over(_ stretch: UndoneAd) -> Bool {
      abs(stretch.start - ask.start) < startTolerance
        || (stretch.start < ask.end && ask.start < stretch.end)
    }
    return file.ads.contains { AdAsks.overlap($0, ask) } || file.isUndone(ask)
      || (file.denied ?? []).contains(where: over)
  }
}
