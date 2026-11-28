// LOFI-FORK: the maybes in an episode's ads file: stretches the word model gives a weak chance
// of being an ad (see FORK.md and docs/PLAN.md, milestone X5). Foundation only.
import Foundation

/// The maybes of one ads file (`AdsFile.maybes`). A maybe is a `FoundAd` with the confidence
/// `guess`. It is never shown and never asked about: the skip tap (`AdSkipTap`) turns the one
/// the playhead is in into an ad, and that is all it is for.
///
/// A confirmed maybe is kept the way an answered question is (see `AdAsking`): it stays in
/// `maybes` with the confidence `sure`, the sure ad with the source "tap" goes into `ads`, and
/// every write through `AdsStore` rebuilds that ad where nothing covers the stretch
/// (`carrying`), unless the listener undid it. Open maybes are not carried: the whole-transcript
/// pass that writes a file sets its own (`setting`).
public enum AdMaybes {
  /// The chance a line needs to open a maybe, and to stay in one.
  public static let startChance = 0.30
  public static let stayChance = 0.15
  /// A maybe is at least this many seconds long (and at most `AdRules.maxLength`).
  public static let minLength = 8.0
  /// The most maybes an episode holds.
  public static let most = 20

  // MARK: Making

  /// The word model's weak spans: the lines decoded with a start threshold of `startChance` and a
  /// stay threshold of `stayChance`, of the three ad sorts only (never credits), joined where they
  /// overlap and cut to the parts outside every stretch in `outside`. Parts of `minLength`
  /// seconds or more and at most `AdRules.maxLength` are kept, each a `guess` with the span's
  /// kind and `source`. A line whose start or end is not a finite time gives nothing for the whole
  /// episode; a line with no length (a one-word line) is fine, since only the first line's start
  /// and the last line's end of a span are used.
  public static func weak(
    model: AdWordModel, lines: [NumberedLine], duration: Double?, outside: [FoundAd], source: String
  ) -> [FoundAd] {
    let real = lines.filter { $0.start.isFinite && $0.end.isFinite }
    guard real.count == lines.count, !lines.isEmpty else { return [] }
    var cutoffs = AdWordModel.Thresholds()
    cutoffs.start = startChance
    cutoffs.stay = stayChance
    cutoffs.sure = model.thresholds.sure
    let rows = model.probabilities(lines: lines, duration: duration)
    let spans =
      model.version >= 2
      ? AdWordModel.decodeTwo(rows: rows, lines: lines, thresholds: cutoffs)
      : AdWordModel.decode(rows: rows, lines: lines, thresholds: cutoffs)
    let byNumber = Dictionary(lines.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
    var found: [FoundAd] = []
    for span in spans {
      guard let kind = AdKind(sort: span.sort), kind != .credits,
        let first = byNumber[span.firstLine], let last = byNumber[span.lastLine]
      else { continue }
      found.append(
        FoundAd(
          start: first.start, end: last.end, kind: kind, advertiser: "", confidence: .guess,
          firstWords: "", source: source))
    }
    var parts: [FoundAd] = []
    for ad in union(found) { parts += cut(ad, around: outside) }
    return parts.filter { (minLength...AdRules.maxLength).contains($0.end - $0.start) }
      .map { part in
        var maybe = part
        maybe.firstWords = words(of: lines, from: part.start, to: part.end)
        return maybe
      }
  }

  /// The first words of the lines that start inside a stretch.
  private static func words(of lines: [NumberedLine], from start: Double, to end: Double) -> String {
    lines.filter { $0.start >= start - 0.001 && $0.start < end }
      .flatMap { $0.text.split(whereSeparator: \.isWhitespace) }
      .prefix(AdRules.firstWords).joined(separator: " ")
  }

  /// Stretches that overlap are one; the kind of the longer one wins.
  private static func union(_ list: [FoundAd]) -> [FoundAd] {
    var result: [FoundAd] = []
    for ad in list.sorted(by: { $0.start < $1.start }) {
      if var last = result.last, ad.start < last.end {
        if ad.duration > last.duration { last.kind = ad.kind }
        last.end = max(last.end, ad.end)
        result[result.count - 1] = last
      } else {
        result.append(ad)
      }
    }
    return result
  }

  /// What is left of `ad` outside the `covering` stretches.
  private static func cut(_ ad: FoundAd, around covering: [FoundAd]) -> [FoundAd] {
    var parts: [FoundAd] = []
    var from = ad.start
    for hole in covering.filter(AdAsking.valid).sorted(by: { $0.start < $1.start })
    where hole.start < ad.end && ad.start < hole.end {
      if hole.start > from { parts.append(piece(of: ad, from, hole.start)) }
      from = max(from, hole.end)
    }
    if from < ad.end { parts.append(piece(of: ad, from, ad.end)) }
    return parts
  }

  private static func piece(of ad: FoundAd, _ start: Double, _ end: Double) -> FoundAd {
    var part = ad
    part.start = start
    part.end = end
    return part
  }

  // MARK: Setting

  /// The file with its open maybes replaced by `maybes`. Only real stretches are taken, that lie
  /// over no ad of the file, no question (answered or not), no undone stretch and no "no" answer.
  /// Each is stored as a `guess`; they do not overlap each other or a confirmed maybe, which is
  /// kept; the file never holds more than `most` (the longest are kept when there are more).
  /// Sorted by start. Nil when the list ends up empty. A prepared file is given back as it is.
  public static func setting(_ maybes: [FoundAd], in file: AdsFile) -> AdsFile {
    guard !file.isPrepared else { return file }
    let confirmed = (file.maybes ?? []).filter { $0.confidence != .guess && AdAsking.valid($0) }
    var kept: [FoundAd] = []
    let room = max(0, most - confirmed.count)
    let ranked = maybes.filter(AdAsking.valid).sorted {
      $0.duration != $1.duration ? $0.duration > $1.duration : $0.start < $1.start
    }
    for maybe in ranked where kept.count < room {
      guard !covered(maybe, by: file),
        !(kept + confirmed).contains(where: { AdAsks.overlap($0, maybe) })
      else { continue }
      var one = maybe
      one.confidence = .guess
      kept.append(one)
    }
    var next = file
    let all = (confirmed + kept).sorted { $0.start < $1.start }
    next.maybes = all.isEmpty ? nil : all
    return next
  }

  // MARK: Reading

  /// The maybes nobody has taken up yet, by start: those that are a `guess`, are real
  /// stretches, and lie over no ad, no question, no undone stretch and no "no" answer.
  public static func open(in file: AdsFile) -> [FoundAd] {
    (file.maybes ?? []).filter { $0.confidence == .guess && AdAsking.valid($0) && !covered($0, by: file) }
      .sorted { $0.start < $1.start }
  }

  /// The open maybe the playhead is in: from `AdSkipNow.leadSeconds` before its start up to, not
  /// including, its end.
  public static func live(in file: AdsFile, at time: Double) -> FoundAd? {
    guard time.isFinite else { return nil }
    return open(in: file).first { $0.start - AdSkipNow.leadSeconds <= time && time < $0.end }
  }

  private static func covered(_ maybe: FoundAd, by file: AdsFile) -> Bool {
    AdAsking.covered(maybe, by: file) || (file.asks ?? []).contains { AdAsks.overlap($0, maybe) }
  }

  // MARK: Confirming

  /// The file after a tap confirmed the open maybe that starts at `maybeStart` (within half a
  /// second): it is recorded as confirmed in `maybes` (its confidence is `sure`, its `source`
  /// stays the finder's) and a sure ad with the source "tap" goes into `ads`. Nil when no open
  /// maybe starts there, so confirming twice does nothing.
  public static func confirm(_ file: AdsFile, maybeStart: Double) -> AdsFile? {
    guard let maybe = maybe(in: file, startingAt: maybeStart) else { return nil }
    var next = file
    next.maybes = (file.maybes ?? []).map { $0 == maybe ? AdAsking.answered($0) : $0 }
    AdAsking.insert(AdAsking.tapAd(for: maybe, from: maybe.start, to: maybe.end), into: &next.ads)
    return next
  }

  /// The same on the episode's saved file for this detector (the final file, else the partial
  /// one), saved where it was found. Returns the maybe as it was, or nil when there was none to
  /// confirm or the file could not be saved.
  @discardableResult
  public static func confirm(store: AdsStore, detector: String, maybeStart: Double) -> FoundAd? {
    let final = store.load(detector: detector)
    guard let file = final ?? store.loadPartial(detector: detector),
      let maybe = maybe(in: file, startingAt: maybeStart),
      let changed = confirm(file, maybeStart: maybeStart),
      (try? (final != nil ? store.save(changed) : store.savePartial(changed))) != nil
    else { return nil }
    return maybe
  }

  private static func maybe(in file: AdsFile, startingAt start: Double) -> FoundAd? {
    guard start.isFinite else { return nil }
    return open(in: file).filter { abs($0.start - start) < AdAsking.startTolerance }
      .min { abs($0.start - start) < abs($1.start - start) }
  }

  // MARK: Carrying

  /// `file` with the confirmed maybes of `earlier` (a file saved before it, of the same detector).
  /// A confirmed maybe replaces a maybe of `file` that overlaps it; a confirmed maybe is a "tap"
  /// ad for every part of its stretch that no ad of `file` covers and that lasts
  /// `AdAsking.sliver` seconds or more, unless the listener undid the stretch. Open maybes of
  /// `earlier` are not carried. `AdAsking.carrying` calls this on every write.
  static func carrying(_ earlier: AdsFile, into file: AdsFile) -> AdsFile {
    var carried = file
    let saved = (earlier.maybes ?? []).filter { $0.confidence != .guess && AdAsking.valid($0) }
    if !saved.isEmpty {
      var all = (file.maybes ?? []).filter { maybe in
        !saved.contains { AdAsks.overlap($0, maybe) && maybe.confidence == .guess }
      }
      for maybe in saved where !all.contains(where: { $0 == maybe }) {
        if let at = all.firstIndex(where: { AdAsks.overlap($0, maybe) }) {
          all[at].confidence = max(all[at].confidence, maybe.confidence)
        } else {
          all.append(maybe)
        }
      }
      carried.maybes = all.sorted { $0.start < $1.start }
    }
    for maybe in carried.maybes ?? [] where maybe.confidence != .guess && AdAsking.valid(maybe) {
      guard !carried.isUndone(maybe), !earlier.isUndone(maybe) else { continue }
      for part in AdAsking.uncovered(maybe, by: carried.ads) {
        AdAsking.insert(
          AdAsking.tapAd(for: maybe, from: part.start, to: part.end), into: &carried.ads)
      }
    }
    return carried
  }
}
