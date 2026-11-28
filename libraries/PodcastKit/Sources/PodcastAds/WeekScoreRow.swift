// LOFI-FORK: the scorecard's row "Plus this week's ad sounds" (see FORK.md, AheadScoreRow.swift and
// WeekSounds.swift in PodcastAudioMatch). Foundation only.
//
// WHAT IT TESTS. If the Mac sent the phone the ad sounds of the last week every hour, what would the
// phone catch that it does not catch now? For each scored episode the sound finder (`weekScan`, made
// in podcast-teach from the sound bank) may use only the ads of episodes published at least a day and
// at most 7 days before that episode; the dates are in episodes.json. Its hits are sorted by the
// show's settings as the phone's own sounds are (`ShowTuning.ownSound`), cut back to the parts outside
// the ads of the last finder row, and joined with them, as every new finder is. The row stands on the
// last finder row, so it shows what the sounds add to everything the phone finds today.
//
// HONEST VALUE. The sounds come from the Mac's marks (Claude's own labels), which on the shelf are
// also the truth the row is scored against. A sound is only used for an episode of another day, so an
// episode never hears its own ad, but an ad that repeats in a week is as marked as the one before it.
// The gate is Z10's: the stream row passes at least 3 more breaks than the last finder row, with no
// more skips that cut no ad.
import Foundation
import PodcastTranscripts

enum WeekScoreRow {
  static let name = "Plus this week's ad sounds"
  /// The go rule, as the plan states it: this many more breaks pass than the last finder row, with
  /// at most this many more skips that cut no ad.
  static let neededMore = 3
  static let mostMoreSkips = 0

  /// What the row did, for the report.
  final class Tally: @unchecked Sendable {
    private let lock = NSLock()
    private var searched = 0
    private var hits = 0
    private var skips = 0

    func add(hits found: Int, skips kept: Int) {
      lock.lock()
      defer { lock.unlock() }
      searched += 1
      hits += found
      skips += kept
    }

    var numbers: (searched: Int, hits: Int, skips: Int) {
      lock.lock()
      defer { lock.unlock() }
      return (searched, hits, skips)
    }
  }

  /// The row: the last finder row's ads (`finders` keeps them for each whole episode) plus what the
  /// week's sounds find in the episode's audio, sorted by the show's settings before any join, and cut
  /// back to the parts outside the ads of the row it stands on. An episode with no audio, and the
  /// first look at an episode's start (which is by words), stay as the row before has them. `kept`
  /// keeps the row's ads for each whole episode, for the stream replay.
  static func layer(
    scan: @escaping @Sendable (URL, String) -> [ScoreSpan], tuning: ShowTuning,
    standingOn finders: ScoreEpisodeAds, kept: ScoreEpisodeAds, tally: Tally
  ) -> AdScoreLayer {
    .rewriting(name: name) { input, soFar in
      guard !input.isHead else { return soFar }
      let episode = input.episode
      var made = finders.ads(for: episode.id) ?? soFar
      if let audio = input.audio {
        let found = ScoreAds.ads(scan(audio, episode.id), source: ShowTuning.ownSound)
        let skips = tuning.apply(to: found, show: episode.feed).skip
        tally.add(hits: found.count, skips: skips.count)
        made = AdJoin.join(made + ScoreAds.outside(skips, of: made))
      }
      kept.put(made, for: episode.id)
      return made
    }
  }

  /// Everything `--week` adds to one run: the row's layer and what it kept for the stream replay.
  struct Run {
    let layer: AdScoreLayer
    let tally = Tally()
    private let kept = ScoreEpisodeAds()

    init(
      scan: @escaping @Sendable (URL, String) -> [ScoreSpan], tuning: ShowTuning,
      standingOn finders: ScoreEpisodeAds
    ) {
      let tally = self.tally
      let kept = self.kept
      layer = WeekScoreRow.layer(
        scan: scan, tuning: tuning, standingOn: finders, kept: kept, tally: tally)
    }

    /// The row made of its scorecard, and the text about it.
    func report(_ card: Scorecard, last: ScorecardRow?, scored: Int) -> (
      row: ScorecardRow, text: String
    ) {
      let row = ScorecardRow(name: WeekScoreRow.name, card: card)
      return (row, WeekScoreRow.lines(row, last: last, searched: tally.numbers, scored: scored).joined(separator: "\n"))
    }

    /// The row played as a stream. `detect` is what the phone finds in the first seconds of an
    /// episode, with this row's layer last.
    func streamed(
      episodes: [TeachingEpisode], habits: ShowHabits, tuning: ShowTuning, speech: Double?,
      detect: (TeachingEpisode, Transcript) -> [FoundAd]
    ) -> StreamNumbers {
      StreamScore.run(
        episodes: episodes, habits: habits, settings: AdSkipSettings(), models: nil, tuning: tuning,
        speech: speech, whole: { kept.ads(for: $0.id) ?? [] }, detect: detect
      ).finders
    }
  }

  // MARK: The report

  /// The go rule against the last finder row, in a sentence that starts with the verdict.
  static func verdict(last: BarTotals, week: BarTotals) -> (go: Bool, line: String) {
    let more = week.passed - last.passed
    let skips = week.noAdSkips - last.noAdSkips
    let go = more >= neededMore && skips <= mostMoreSkips
    func change(_ number: Int, _ noun: String) -> String {
      number < 0 ? "\(-number) fewer \(noun)" : "\(number) more \(noun)"
    }
    return (
      go,
      (go ? "Verdict: go. " : "Verdict: no go. ")
        + "\(change(more, "breaks pass")) than the last finder row (\(neededMore) more are needed), with \(change(skips, "skips")) with no ad (\(mostMoreSkips) more is the most)."
    )
  }

  /// The lines about the row: what it searched and found, its bar and why breaks fail in it, and the
  /// verdict against the last finder row by the scorecard (the stream's own verdict comes with the
  /// stream replay).
  static func lines(
    _ row: ScorecardRow, last: ScorecardRow?, searched: (searched: Int, hits: Int, skips: Int),
    scored: Int
  ) -> [String] {
    var out = [
      "\(name): \(searched.searched) of \(scored) scored episodes have an MP3 file and were searched with the ad sounds of the episodes published 1 to 7 days before them (the sound bank, sound-bank/<id>.json): \(searched.hits) hits, \(searched.skips) of them skip by the show's settings. An episode with no earlier week in the folder is searched with nothing."
    ]
    if let bar = row.bar {
      out.append("  " + StreamReport.barLine(bar))
      let failing = BarCause.allCases.map { ($0, bar.count($0)) }.filter { $0.1 > 0 }
        .sorted { $0.1 > $1.1 }
      out.append(
        "  Why breaks fail in this row: "
          + (failing.isEmpty
            ? "no break fails." : failing.map { "\($0.0.label) \($0.1)" }.joined(separator: ", ") + "."))
      if let before = last?.bar { out.append("  " + verdict(last: before, week: bar).line) }
    }
    out.append(
      "  The sounds come from the Mac's marks, which on the shelf are also the truth the row is scored against; an episode never hears its own ad, only ads of other days.")
    return out
  }

  /// The sentence when the row cannot be made.
  static let leftOut =
    "\(name) is left out: it needs the audio code of podcast-teach and at least one episode with an MP3 file in the teaching folder."
}
