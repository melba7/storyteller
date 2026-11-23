// LOFI-FORK: turns what a model is half sure about into questions for the listener (see FORK.md
// and docs/PODCASTS-ADS-TEACHING.md). Foundation only.
import Foundation

/// Makes the questions: stretches the phone does not skip because no finder is sure enough, but
/// that a model gave a fair chance of being an ad. They are kept in `AdsFile.asks` (see
/// `AdAsking`), and the listener answers them with one tap.
///
/// A question is a `FoundAd` with the confidence `guess`, so nothing that reads an ads file's
/// `ads` can ever skip it, and the name of the finder that made it in `source`.
public enum AdAsks {
  /// A line is asked about from this chance of being an ad up to the model's own start
  /// threshold. A parameter of `questions`; the Mac's settings file may raise it.
  public static let askFrom = 0.35
  /// The most questions for one episode.
  public static let most = 3

  /// A stretch that could be asked about, with how likely it is an ad (0 to 1). A finder that
  /// has no model rows (the repeats) hands these to `pick` itself.
  public struct Candidate: Sendable, Equatable {
    public var ad: FoundAd
    public var chance: Double

    public init(ad: FoundAd, chance: Double) {
      self.ad = ad
      self.chance = chance
    }
  }

  // MARK: From a model's rows

  /// The questions for the lines of a transcript, from the word model. The rows are the model's
  /// (`AdWordModel.probabilities`), smoothed as its decoder smooths them (`smoothed`), and the
  /// ceiling is its own start threshold. The decoder opens an ad where the SMOOTHED chance
  /// reaches that threshold, so a stretch it drops (its smoothed chance stays under the
  /// threshold) is asked about even when some of its lines have a raw chance over it.
  ///
  /// The rows do not know the ads: the decoder's spans only become ads after the clean-up cuts
  /// and joins them, and other finders add theirs. So `ads` must hold every ad already in the
  /// episode's file after the clean-up, or a stretch that an ad covers can be asked about.
  public static func questions(
    model: AdWordModel, lines: [NumberedLine], duration: Double?, from: Double = askFrom,
    outside ads: [FoundAd], source: String
  ) -> [FoundAd] {
    questions(
      lines: lines, rows: smoothed(model.probabilities(lines: lines, duration: duration)),
      from: from, below: model.thresholds.start, outside: ads, source: source)
  }

  /// The rows with the chance of an ad on each line replaced by the decoder's smoothed value
  /// (`AdWordModel+Spans`): a quarter of the line before, half of the line and a quarter of the
  /// line after, where a missing neighbour (the first and last line, or a row that is not
  /// numbers) counts as the line itself. Only the first number of each row, the probability of
  /// "none", is changed (to one minus the smoothed chance); the classes keep their numbers, so
  /// the kind of a question is as before. A row that is not numbers is left as it is. A model
  /// whose decoder smooths the same way (the meaning model) passes its rows through this.
  public static func smoothed(_ rows: [[Double]]) -> [[Double]] {
    let chances = rows.map { chance(of: $0) }
    return rows.indices.map { at in
      guard let own = chances[at] else { return rows[at] }
      let before = at > 0 ? chances[at - 1] ?? own : own
      let after = at + 1 < rows.count ? chances[at + 1] ?? own : own
      var row = rows[at]
      row[0] = 1 - (before / 4 + own / 2 + after / 4)
      return row
    }
  }

  /// The questions for the lines, from any model's probability rows: one row for each line, in
  /// the order of `AdWordModel.classes` (the first is "none", so the chance of an ad is one
  /// minus it). The chance is each line's own, as the row gives it: these rows are NOT smoothed
  /// (a model whose decoder smooths passes `smoothed(rows)`). The runs of lines whose chance is
  /// at least `from` and under `below`, that lie outside every ad in `ads`, last at least
  /// `AdRules.minLength` seconds and at most `AdRules.maxLength`, are the candidates; at most
  /// `most` of them are kept, the most likely first. A row that is not a list of numbers reads
  /// as no chance (the line is not asked about), and lines with no row are left out, so bad
  /// input asks nothing and traps nothing.
  public static func questions(
    lines: [NumberedLine], rows: [[Double]], from: Double = askFrom, below: Double,
    outside ads: [FoundAd], source: String
  ) -> [FoundAd] {
    pick(
      candidates(
        lines: lines, rows: rows, from: from, below: below, outside: ads, source: source),
      outside: ads)
  }

  /// Every run of lines that fits, with the mean chance of its lines, before the choice of the
  /// most likely few. For a caller that adds the candidates of another finder before `pick`.
  public static func candidates(
    lines: [NumberedLine], rows: [[Double]], from: Double = askFrom, below: Double,
    outside ads: [FoundAd], source: String
  ) -> [Candidate] {
    guard from.isFinite, below.isFinite, from < below else { return [] }
    let count = min(lines.count, rows.count)
    var found: [Candidate] = []
    var first: Int?
    var total = 0.0
    // One step past the last line closes a run that reaches the end.
    for at in 0...count {
      if at < count, let chance = chance(of: rows[at]), chance >= from, chance < below,
        usable(lines[at], outside: ads)
      {
        if first == nil {
          first = at
          total = 0
        }
        total += chance
        continue
      }
      guard let start = first else { continue }
      first = nil
      let run = lines[start..<at]
      if let made = makeCandidate(
        run, rows: rows[start..<at], chance: total / Double(at - start), source: source)
      {
        found.append(made)
      }
    }
    return found
  }

  // MARK: Choosing

  /// At most `most` questions from the candidates, the most likely first (the earlier one when
  /// two are equally likely). A candidate that is not a number, is shorter than
  /// `AdRules.minLength` or longer than `AdRules.maxLength`, overlaps an ad in `ads`, or overlaps
  /// a more likely candidate is left out. Every question comes out with the confidence `guess`
  /// and keeps the rest of what its finder gave it, `source` included.
  public static func pick(_ candidates: [Candidate], outside ads: [FoundAd]) -> [FoundAd] {
    let fit = candidates.filter { entry in
      let ad = entry.ad
      guard entry.chance.isFinite, ad.start.isFinite, ad.end.isFinite,
        (AdRules.minLength...AdRules.maxLength).contains(ad.end - ad.start)
      else { return false }
      return !ads.contains { overlap($0, ad) }
    }
    let ranked = fit.sorted {
      $0.chance != $1.chance ? $0.chance > $1.chance : $0.ad.start < $1.ad.start
    }
    var picked: [FoundAd] = []
    for entry in ranked where picked.count < most {
      guard !picked.contains(where: { overlap($0, entry.ad) }) else { continue }
      var question = entry.ad
      question.confidence = .guess
      picked.append(question)
    }
    return picked
  }

  // MARK: Details

  /// Whether two stretches share any time (touching at an edge is not sharing).
  static func overlap(_ a: FoundAd, _ b: FoundAd) -> Bool { a.start < b.end && b.start < a.end }

  /// The chance of an ad on a line: one minus the probability of "none", kept between 0 and 1.
  /// Nil for a row with fewer than two numbers or a probability of "none" that is not a number.
  private static func chance(of row: [Double]) -> Double? {
    guard row.count >= 2, row[0].isFinite else { return nil }
    return min(max(1 - row[0], 0), 1)
  }

  /// Whether a line can be part of a question: it has a real time and lies inside no ad.
  private static func usable(_ line: NumberedLine, outside ads: [FoundAd]) -> Bool {
    guard line.start.isFinite, line.end.isFinite, line.end > line.start else { return false }
    return !ads.contains { $0.start < line.end && line.start < $0.end }
  }

  /// A run of lines as a candidate, or nil when it is too short or too long to be an ad.
  private static func makeCandidate(
    _ run: ArraySlice<NumberedLine>, rows: ArraySlice<[Double]>, chance: Double, source: String
  ) -> Candidate? {
    guard let first = run.first, let last = run.last else { return nil }
    let length = last.end - first.start
    guard (AdRules.minLength...AdRules.maxLength).contains(length) else { return nil }
    let words = run.flatMap { $0.text.split(whereSeparator: \.isWhitespace) }
    let ad = FoundAd(
      start: first.start, end: last.end, kind: kind(of: rows), advertiser: "", confidence: .guess,
      firstWords: words.prefix(AdRules.firstWords).joined(separator: " "), source: source)
    return Candidate(ad: ad, chance: chance)
  }

  /// The kind of the class that has the most probability over the rows, never "none". A class
  /// the Mac's names do not know (or a row of another shape) gives a plain ad.
  private static func kind(of rows: ArraySlice<[Double]>) -> AdKind {
    var totals = [Double](repeating: 0, count: AdWordModel.classes.count)
    for row in rows {
      for c in 1..<min(row.count, totals.count) where row[c].isFinite { totals[c] += row[c] }
    }
    var best = 1
    for c in 2..<totals.count where totals[c] > totals[best] { best = c }
    return AdKind(sort: AdWordModel.classes[best]) ?? .ad
  }
}
