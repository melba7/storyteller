// LOFI-FORK: the scorecard's row that adds Apple's model's cached answers to the last row (see
// FORK.md, AppleAnswers.swift and AnswerScoreRow.swift). Foundation only.
import Foundation

enum AppleScoreRow {
  static let name = "Plus Apple's model (asked on the Mac)"

  /// The row: the answers of each episode that has one, joined with the ads of the row before
  /// the way the phone joins them (`AdJoin.join`). An episode with no answer stays as it was.
  /// The first look is by words only, so the model adds nothing to it.
  static func layer(_ answers: [String: [FoundAd]]) -> AdScoreLayer {
    AnswerScoreRow.layer(name: name, answers)
  }

  /// The model's answers for the scored episodes, or nil when it has none for any of them.
  static func answers(_ saved: AppleAnswers?, episodes: [TeachingEpisode]) -> [String: [FoundAd]]? {
    guard let saved else { return nil }
    let found = saved.ads(among: episodes.map(\.id))
    return found.isEmpty ? nil : found
  }

  /// The lines about the row: how many scored episodes have answers, and its bar.
  static func lines(_ row: ScorecardRow, answered: Int, of episodes: Int) -> [String] {
    AnswerScoreRow.lines(
      name, row, answered: answered, of: episodes, from: "the model", others: "the row before")
  }
}
