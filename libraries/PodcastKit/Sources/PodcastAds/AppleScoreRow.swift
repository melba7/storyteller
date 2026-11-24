// LOFI-FORK: the scorecard's rows that add Apple's model's cached answers to the last row (see
// FORK.md, AppleAnswers.swift, AppleModelAds.swift and AnswerScoreRow.swift). Foundation only.
import Foundation

enum AppleScoreRow {
  /// The phone's row: the answers that skip on each show, as the per-show settings let them.
  static let name = "Plus Apple's model (asked on the Mac)"
  /// What the row would be if every show let Apple's model skip every answer. It stands on the row
  /// before Apple's, whatever the settings say, so the Mac's settings step (teach_settings.py) has
  /// evidence for the shows where the model may skip that does not depend on its own choice.
  static let skippingName = "Plus Apple's model, if every show let it skip"

  /// The model's answers for the scored episodes, or nil when it has none for any of them.
  static func answers(_ saved: AppleAnswers?, episodes: [TeachingEpisode]) -> [String: [FoundAd]]? {
    guard let saved else { return nil }
    let found = saved.ads(among: episodes.map(\.id))
    return found.isEmpty ? nil : found
  }

  /// What the settings make of the answers: the ones that skip, by episode id, and how many
  /// answers ask, skip and are dropped, counted over all the episodes.
  struct Placed {
    var skips: [String: [FoundAd]] = [:]
    var asked = 0
    var skipped = 0
    var dropped = 0
  }

  /// Sorts the answers as the phone does, before any join. The show of an episode is its feed
  /// address, as for the per-show settings row.
  static func place(
    _ answers: [String: [FoundAd]], episodes: [TeachingEpisode], tuning: ShowTuning
  ) -> Placed {
    var placed = Placed()
    for episode in episodes {
      guard let given = answers[episode.id] else { continue }
      let level = tuning.level(forFinder: ShowTuning.appleModel, show: episode.feed)
      let sorted = AppleModelAds.place(given, level: level, tuning: tuning, show: episode.feed)
      placed.skips[episode.id] = sorted.skip
      placed.skipped += sorted.skip.count
      placed.asked += sorted.ask.count
      placed.dropped += given.count - sorted.skip.count - sorted.ask.count
    }
    return placed
  }

  /// The two rows, in this order. The phone's: the answers that skip, joined with the ads of the
  /// row before the way the phone joins them (`AdJoin.join`); an episode whose answers all ask
  /// stays as it was, and the first look is by words only, so the model adds nothing to it. Then
  /// the what-if row: every answer skipping, on the last finder row (`finders`).
  static func layers(
    _ answers: [String: [FoundAd]], placed: Placed, standingOn finders: ScoreEpisodeAds
  ) -> [AdScoreLayer] {
    [
      AnswerScoreRow.layer(name: name, placed.skips),
      AnswerScoreRow.layer(name: skippingName, answers, standingOn: finders),
    ]
  }

  /// The two rows made of their scorecards (`cards` starts with the phone's row and then the
  /// what-if row), and the text about them: how many scored episodes have answers, what the
  /// settings made of them, and each row's bar.
  static func report(
    _ cards: [Scorecard], answered: Int, of episodes: Int, placed: Placed
  ) -> (rows: [ScorecardRow], text: String) {
    let phone = ScorecardRow(name: name, card: cards[0])
    let everyShow = ScorecardRow(name: skippingName, card: cards[1])
    var first = AnswerScoreRow.lines(
      name, phone, answered: answered, of: episodes, from: "the model", others: "the row before")
    var count =
      "  Apple's answers with the per-show settings above (the built-in ones when there is no show-settings.json): \(placed.asked) ask and \(placed.skipped) skip"
    if placed.dropped > 0 { count += ", \(placed.dropped) are dropped" }
    first.append(count + ". Only the ones that skip are in this row: Apple's model asks unless a show is set to skip.")
    var second = AnswerScoreRow.lines(
      skippingName, everyShow, answered: answered, of: episodes, from: "the model",
      others: "the last finder row")
    second.append(
      "  This row lets every answer skip, which is what the phone did before Apple's model asked by default. It is not what the phone does now: it is the evidence the Mac's settings step reads, which lets the model skip on a show only where this row passes at least 3 more breaks than the row before Apple's and adds at most 1 more skip with no ad there.")
    let text = (first + [""] + second).joined(separator: "\n")
    return ([phone, everyShow], text)
  }
}
