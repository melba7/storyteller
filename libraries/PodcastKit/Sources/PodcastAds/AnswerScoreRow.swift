// LOFI-FORK: the scorecard rows that add the answers of a model asked on the Mac: Apple's model
// (`AppleScoreRow`) and the passage model (`PassageScoreRow`). One place for how such a row is made
// and described (see FORK.md, AdScoreLayer.swift). Foundation only.
import Foundation

enum AnswerScoreRow {
  /// A row that adds `answers` (by episode id) to the row before it, the way the phone joins them
  /// (`AdJoin.join`). An episode with no answer stays as it was. The first look is by words only,
  /// so a model adds nothing to it.
  static func layer(name: String, _ answers: [String: [FoundAd]]) -> AdScoreLayer {
    AdScoreLayer(name: name) { input, _ in
      input.isHead ? [] : answers[input.episode.id] ?? []
    }
  }

  /// A row that adds `answers` to what the last finder row found (`finders` keeps that for each
  /// whole episode), whatever rows lie between the two. It is what a model's row needs when
  /// another model's row comes before it: the numbers of the one row never hold the other's ads,
  /// so each can be compared with the last finder row. Returns the whole list of its row, so it is
  /// a rewriting layer. The head of an episode is left as the row before has it.
  static func layer(
    name: String, _ answers: [String: [FoundAd]], standingOn finders: ScoreEpisodeAds
  ) -> AdScoreLayer {
    .rewriting(name: name) { input, soFar in
      guard !input.isHead else { return soFar }
      let base = finders.ads(for: input.episode.id) ?? soFar
      guard let found = answers[input.episode.id], !found.isEmpty else { return base }
      return AdJoin.join(base + found)
    }
  }

  /// The lines about a row: how many scored episodes have an answer and what the others stay as,
  /// and its bar.
  static func lines(
    _ name: String, _ row: ScorecardRow, answered: Int, of episodes: Int, from model: String,
    others: String
  ) -> [String] {
    var out = [
      "\(name): \(answered) of \(episodes) scored episodes have an answer from \(model); the others stay as \(others)."
    ]
    if let bar = row.bar { out.append("  " + StreamReport.barLine(bar)) }
    return out
  }
}
