// LOFI-FORK: the questions in an episode's ads file and what an answer does to it (see FORK.md
// and docs/PODCASTS-ADS-TEACHING.md). Foundation only.
import Foundation

/// The questions of one ads file (`AdsFile.asks`): which one is live at the playhead, what the
/// listener's answer changes, and which new questions may be added. `AdAsks` makes them.
///
/// A question stays in `asks` for good, so that the cap of `AdAsks.most` questions an episode
/// counts the answered ones too. A question is made with the confidence `guess`, and it is open
/// (`open(in:)`, `live(in:at:)`) while it is one and nothing covers it:
///  - A "yes" is recorded IN the question: its confidence becomes `sure` (it keeps the finder's
///    name in `source`). The sure ad with the source "tap" that goes into `ads` is not what
///    keeps the yes, because `AdJoin` drops an ad's source when it joins it with a touching ad,
///    and a finder's fresh file does not hold it. Every write through `AdsStore` rebuilds a
///    "tap" ad for the parts of the confirmed stretch that no ad of the file covers
///    (`carrying`), except where the listener undid it: an undone yes stays undone and closed.
///  - A "no" puts the stretch in `AdsFile.denied`, never in `undone`: `undone` stops any ad that
///    overlaps it, and a question often lies next to a real ad. Ads are never compared with
///    `denied`.
///  - A question over an ad, an undone stretch or a denied one is not open whatever the file
///    says, so a finder that asks about the same stretch again changes nothing.
///
/// WHAT THE WIRING MUST DO (every point matters):
///  1. Make questions only from WHOLE-transcript passes, never from partial ones: a partial
///     pass sees part of the episode, and its questions would use up the cap of three before
///     the rest is read.
///  2. Write ads files only through `AdsStore` (`save`, `savePartial`). Each write puts back
///     what the file already saved holds of the listener's answers: the questions (the saved
///     ones first, answered ones before the rest, never more than three), a yes as a "tap" ad
///     where nothing covers its stretch, and the "no" answers (the newest few). So a file that
///     was loaded before an answer and is written after it keeps the answer, and cannot bring
///     the count of questions over three.
///  3. `answer` returns nil when the question is hidden (an ad already covers it, or it was
///     answered): the caller must still skip in that case, because the listener pressed Skip.
///  4. A "tap" ad that `AdJoin` joins with an overlapping ad loses its `source`. `KnownAds.
///     learnTapped` already counted the confirmed stretch, so the known-ads learn from the
///     whole file must also skip any ad that overlaps an ad with the source "tap" (or a
///     stretch of an answered yes) that was counted already.
public enum AdAsking {
  /// The `source` of an ad the listener confirmed by answering a question.
  public static let source = "tap"
  /// An answer names its question by the start the app was told, which may be a little off.
  static let startTolerance = 0.5
  /// A part of a confirmed stretch shorter than this (the distance `AdJoin` calls touching) is
  /// not made an ad.
  static let sliver = 0.5
  /// The most "no" answers kept when files are carried: the questions are three, so this is
  /// plenty, and a damaged file cannot make every write slow.
  static let mostDenied = 4 * AdAsks.most

  // MARK: Reading

  /// The questions still waiting for an answer, by start: those that are a `guess`, have a real
  /// time, and lie over no ad of the file (whatever its confidence), no stretch the listener
  /// undid and none they said "not an ad" to.
  public static func open(in file: AdsFile) -> [FoundAd] {
    (file.asks ?? [])
      .filter { $0.confidence == .guess && valid($0) && !covered($0, by: file) }
      .sorted { $0.start < $1.start }
  }

  /// The question the playhead is inside (from its start up to, not including, its end), or nil.
  public static func live(in file: AdsFile, at time: Double) -> FoundAd? {
    open(in: file).first { $0.start <= time && time < $0.end }
  }

  // MARK: Answering

  /// The file after the listener answered the open question that starts at `start` (within half
  /// a second). A "yes" (`isAd`) records it in the question (`answered`) and puts the stretch in
  /// `ads` as a sure ad with the source "tap", placed by its start. A "no" adds its stretch to
  /// `denied`, which keeps the phone from asking about it again and never stops an ad. The
  /// question stays in `asks` either way. Nil when no open question starts there, so answering
  /// twice does nothing.
  public static func answer(_ file: AdsFile, askStart start: Double, isAd: Bool) -> AdsFile? {
    guard let ask = question(in: file, startingAt: start) else { return nil }
    var next = file
    if isAd {
      next.asks = (file.asks ?? []).map { $0 == ask ? answered($0) : $0 }
      insert(tapAd(for: ask, from: ask.start, to: ask.end), into: &next.ads)
    } else {
      next.denied = (file.denied ?? []) + [UndoneAd(start: ask.start, end: ask.end)]
    }
    return next
  }

  /// The same as `answer(_:askStart:isAd:)` on the episode's saved file for this detector (the
  /// final file, else the partial one; each is read once), and saves it where it was found.
  /// Returns the question that was answered (as it was asked), or nil when there was none to
  /// answer or the file could not be saved.
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
  /// kept as a `guess` (a question cannot be handed in as answered), and the list is kept by
  /// start.
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

  /// `file` with what `earlier` (a file saved before it, of the same detector) holds of the
  /// listener's answers. `AdsStore.carryingTrims` calls this on every write, once for the final
  /// file and once for the partial one, after their undone skips are carried.
  ///  - Questions: those of both files, answered yes first (and a question that is a yes in one
  ///    file is a yes in the result), then the saved ones before the new ones, at most
  ///    `AdAsks.most`. A question that is not a real stretch is left out.
  ///  - Every yes (an answered question): a sure "tap" ad for each part of its stretch that no
  ///    ad of `file` covers and that lasts `sliver` seconds or more, unless the listener undid
  ///    the stretch. A model ad that covers only a part leaves the rest to the yes.
  ///  - "No" answers: those of both, each once, the newest `mostDenied`, real stretches only.
  /// Writing a file that already has all of this again changes nothing.
  static func carrying(_ earlier: AdsFile, into file: AdsFile) -> AdsFile {
    var carried = file
    if let saved = earlier.asks, !saved.isEmpty {
      let all = mergedAsks(saved + (file.asks ?? []))
      carried.asks = all.isEmpty ? nil : all
    }
    if let saved = earlier.denied, !saved.isEmpty {
      let all = mergedDenied((file.denied ?? []) + saved)
      carried.denied = all.isEmpty ? nil : all
    }
    for ask in carried.asks ?? [] where ask.confidence != .guess && valid(ask) {
      guard !carried.isUndone(ask), !earlier.isUndone(ask) else { continue }
      for part in uncovered(ask, by: carried.ads) {
        insert(tapAd(for: ask, from: part.start, to: part.end), into: &carried.ads)
      }
    }
    return AdMaybes.carrying(earlier, into: carried)
  }

  /// The questions of a list that may hold the same one twice: real stretches only, answered
  /// ones first, a question that overlaps one already taken is the same question (and is a yes
  /// if either is), at most `AdAsks.most`, by start.
  private static func mergedAsks(_ list: [FoundAd]) -> [FoundAd] {
    let real = list.filter(valid)
    var all: [FoundAd] = []
    for ask in real.filter({ $0.confidence != .guess }) + real.filter({ $0.confidence == .guess }) {
      if let at = all.firstIndex(where: { AdAsks.overlap($0, ask) }) {
        all[at].confidence = max(all[at].confidence, ask.confidence)
      } else if all.count < AdAsks.most {
        all.append(ask)
      }
    }
    return all.sorted { $0.start < $1.start }
  }

  /// The real stretches of a list, each once (the first one stays), and the last `mostDenied`
  /// of them: the newest, as answers are added at the end. One pass.
  private static func mergedDenied(_ list: [UndoneAd]) -> [UndoneAd] {
    struct Key: Hashable { var start: UInt64, end: UInt64 }
    var seen = Set<Key>()
    var all: [UndoneAd] = []
    for no in list where no.start.isFinite && no.end.isFinite && no.end > no.start {
      if seen.insert(Key(start: no.start.bitPattern, end: no.end.bitPattern)).inserted {
        all.append(no)
      }
    }
    return Array(all.suffix(mostDenied))
  }

  /// The parts of the question's stretch that no ad covers and that last `sliver` or more.
  static func uncovered(_ ask: FoundAd, by ads: [FoundAd]) -> [(start: Double, end: Double)] {
    var parts: [(start: Double, end: Double)] = []
    var from = ask.start
    for ad in ads.filter({ AdAsks.overlap($0, ask) }).sorted(by: { $0.start < $1.start }) {
      if ad.start > from { parts.append((from, ad.start)) }
      from = max(from, ad.end)
    }
    if from < ask.end { parts.append((from, ask.end)) }
    return parts.filter { $0.end - $0.start >= sliver }
  }

  // MARK: Details

  /// The question as it is stored after a "yes".
  static func answered(_ ask: FoundAd) -> FoundAd {
    var done = ask
    done.confidence = .sure
    return done
  }

  /// The sure ad that a yes puts in `ads`, for the part from `start` to `end` of the question.
  static func tapAd(for ask: FoundAd, from start: Double, to end: Double) -> FoundAd {
    var ad = ask
    ad.start = start
    ad.end = end
    ad.confidence = .sure
    ad.source = source
    return ad
  }

  static func insert(_ ad: FoundAd, into ads: inout [FoundAd]) {
    ads.insert(ad, at: ads.firstIndex(where: { $0.start > ad.start }) ?? ads.count)
  }

  /// The open question whose start is nearest to `start`, within `startTolerance`.
  private static func question(in file: AdsFile, startingAt start: Double) -> FoundAd? {
    open(in: file)
      .filter { abs($0.start - start) < startTolerance }
      .min { abs($0.start - start) < abs($1.start - start) }
  }

  static func valid(_ ask: FoundAd) -> Bool {
    ask.start.isFinite && ask.end.isFinite && ask.end > ask.start
  }

  /// Whether the file already has an ad over the question, or the listener undid that stretch
  /// or said "not an ad" to it. Ads are never compared with `denied`; this is the other way.
  static func covered(_ ask: FoundAd, by file: AdsFile) -> Bool {
    func over(_ stretch: UndoneAd) -> Bool {
      abs(stretch.start - ask.start) < startTolerance
        || (stretch.start < ask.end && ask.start < stretch.end)
    }
    return file.ads.contains { AdAsks.overlap($0, ask) } || file.isUndone(ask)
      || (file.denied ?? []).contains(where: over)
  }
}
