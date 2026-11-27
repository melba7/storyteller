// LOFI-FORK: the scorecard's last two rows, "Plus opening lines" and "Plus filled holes" (see FORK.md,
// CueAds.swift, AheadScoreRow.swift and AdScoreLayer.swift). Foundation only.
//
// Both rows are rewriting layers, as the Mac's marks row is. The first stands on the Mac's marks row
// when `--ahead` was given and on the last finder row otherwise; the second stands on the first.
// They read the cues from `<teaching folder>/ad-cues.json`; with no such file there are no rows.
import Foundation
import PodcastTranscripts

enum CueScoreRows {
  static let openingName = "Plus opening lines"
  static let holesName = "Plus filled holes"
  /// The go rule, for the two rows together: this many more breaks pass than the row they stand
  /// on, with at most this many more skips with no ad.
  static let neededMore = 10
  static let mostMoreSkips = 2

  /// The ads of a row the finders look at: the ones the phone skips, those that are at least
  /// unsure and of a kind the listener's switches allow.
  static func skipping(_ ads: [FoundAd]) -> [FoundAd] {
    let settings = AdSkipSettings()
    return ads.filter { $0.confidence >= .unsure && settings.allows($0.kind) }
  }

  /// `base` plus what a finder found, sorted by the show's settings first (only `skip` is kept) and
  /// then joined. The stretches are NOT cut back to keep `ScoreAds.apart` from the ads of `base`, as
  /// every other new finder's are: they touch the ads they extend on purpose, because a gap of a
  /// second would leave a blip of the ad to hear.
  private static func add(
    _ found: [FoundAd], to base: [FoundAd], tuning: ShowTuning, show: String
  ) -> [FoundAd] {
    let skips = tuning.apply(to: found, show: show).skip
    return skips.isEmpty ? base : AdJoin.join(base + skips)
  }

  /// The two rows. A row changes nothing on the head of an episode: the finders need the whole
  /// transcript. `kept` keep each row's ads for every whole episode, for the stream replay.
  static func layers(
    _ cues: AdCues, tuning: ShowTuning, onMarks: Bool, standingOn finders: ScoreEpisodeAds,
    kept: (openings: ScoreEpisodeAds, holes: ScoreEpisodeAds)
  ) -> [AdScoreLayer] {
    [
      .rewriting(name: openingName) { input, soFar in
        guard !input.isHead else { return soFar }
        let base = onMarks ? soFar : finders.ads(for: input.episode.id) ?? soFar
        let show = input.episode.feed
        let found = CueAds.openings(
          lines: input.transcript.lines, skips: skipping(base), cues: cues, show: show)
        let made = add(found, to: base, tuning: tuning, show: show)
        kept.openings.put(made, for: input.episode.id)
        return made
      },
      .rewriting(name: holesName) { input, soFar in
        guard !input.isHead else { return soFar }
        let show = input.episode.feed
        let found = CueAds.holes(
          lines: input.transcript.lines, skips: skipping(soFar), cues: cues, show: show)
        let made = add(found, to: soFar, tuning: tuning, show: show)
        kept.holes.put(made, for: input.episode.id)
        return made
      },
    ]
  }

  // MARK: What a run of the scorecard adds

  /// The two rows of one run: the cues, the layers (none without a cue file) and what they kept.
  struct Run {
    let cues: AdCues?
    let layers: [AdScoreLayer]
    private let kept: (openings: ScoreEpisodeAds, holes: ScoreEpisodeAds)

    init(folder: URL, tuning: ShowTuning, onMarks: Bool, standingOn finders: ScoreEpisodeAds) {
      let read = (try? Data(contentsOf: folder.appendingPathComponent(AdCues.fileName)))
        .map { AdCues(data: $0) }
      let found = read.flatMap { $0.isEmpty ? nil : $0 }
      let box = (openings: ScoreEpisodeAds(), holes: ScoreEpisodeAds())
      cues = found
      kept = box
      layers =
        found.map {
          CueScoreRows.layers($0, tuning: tuning, onMarks: onMarks, standingOn: finders, kept: box)
        } ?? []
    }

    /// The two rows made of their scorecards (`cards` are the last two of the run), and the text
    /// about them. `last` is the row they stand on. With no cue file the text says so.
    func report(_ cards: [Scorecard], last: ScorecardRow?) -> (rows: [ScorecardRow], text: String) {
      guard let cues, cards.count == 2 else {
        return (
          [],
          "Opening lines and filled holes: left out, there is no \(AdCues.fileName) with cues in the teaching folder."
        )
      }
      let rows = zip([openingName, holesName], cards).map { ScorecardRow(name: $0, card: $1) }
      return (rows, CueScoreRows.lines(rows, cues: cues, last: last).joined(separator: "\n"))
    }

    /// The numbers of the two rows played as streams. `detect` is what the phone finds in the first
    /// seconds of an episode (the finders change nothing there).
    func streamed(
      episodes: [TeachingEpisode], habits: ShowHabits, tuning: ShowTuning, speech: Double?,
      detect: (TeachingEpisode, Transcript) -> [FoundAd]
    ) -> [StreamNumbers] {
      [kept.openings, kept.holes].map { row in
        StreamScore.run(
          episodes: episodes, habits: habits, settings: AdSkipSettings(), models: nil, tuning: tuning,
          speech: speech, whole: { row.ads(for: $0.id) ?? [] }, detect: detect
        ).finders
      }
    }
  }

  // MARK: The report

  /// The go rule for the two rows together (`both` is the second row) against the row they stand
  /// on, in a sentence that starts with the verdict.
  static func verdict(last: BarTotals, both: BarTotals) -> (go: Bool, line: String) {
    let more = both.passed - last.passed
    let skips = both.noAdSkips - last.noAdSkips
    let go = more >= neededMore && skips <= mostMoreSkips
    func change(_ number: Int, _ noun: String) -> String {
      number < 0 ? "\(-number) fewer \(noun)" : "\(number) more \(noun)"
    }
    return (
      go,
      (go ? "Verdict: go. " : "Verdict: no go. ")
        + "Both rows together: \(change(more, "breaks pass")) than the row they stand on (\(neededMore) more are needed), with \(change(skips, "skips")) with no ad (\(mostMoreSkips) more is the most)."
    )
  }

  /// What the file holds (numbers only), each row's bar and why breaks fail in it, and the verdict.
  static func lines(_ rows: [ScorecardRow], cues: AdCues, last: ScorecardRow?) -> [String] {
    var out = [
      "Opening lines and filled holes: \(AdCues.fileName) holds \(cues.generalStarts) opening and \(cues.generalReturns) return lines for every show, \(cues.showStarts) opening and \(cues.showReturns) return lines for \(cues.showCount) shows, \(cues.commonWords) common and \(cues.usualWords) usual words, learned from \(cues.episodes) episodes."
    ]
    for row in rows {
      guard let bar = row.bar else { continue }
      out.append("\(row.name): " + StreamReport.barLine(bar))
      let failing = BarCause.allCases.map { ($0, bar.count($0)) }.filter { $0.1 > 0 }
        .sorted { $0.1 > $1.1 }
      out.append(
        "  Why breaks fail in this row: "
          + (failing.isEmpty
            ? "no break fails." : failing.map { "\($0.0.label) \($0.1)" }.joined(separator: ", ") + "."))
    }
    if let before = last?.bar, let after = rows.last?.bar {
      out.append(verdict(last: before, both: after).line)
    }
    return out
  }
}
