// LOFI-FORK: the lines the scorecard prints besides its rows (see FORK.md and the round plan, ideas
// 3, 5, 6 and 7). Foundation only. Each function returns plain sentences and reads no file.
import Foundation
import PodcastTranscripts

enum AdScoreNotes {
  /// Wrong seconds may rise by one in a hundred and the joints still pay (as `teach_settings.py`
  /// judges them).
  private static let wrongAllowed = 1.01
  private static let epsilon = 1e-6

  private static func time(_ seconds: Double) -> String { AdScoreReport.time(seconds) }

  /// The right seconds of a row: the marked ad time that is skipped. The wrong seconds are the
  /// show time cut by mistake.
  private static func right(_ row: ScorecardRow) -> Double {
    row.total.adSeconds - row.total.heardSeconds
  }

  // MARK: What the joints and the settings did (ideas 5 and 7)

  /// One line for each finder row (own sounds, repeated sounds, repeated words, the meaning model),
  /// one for the joints row, one for the steady row and one for the settings row, each against the
  /// row before it in `rows`. A row that is not there, or has nothing before it, gets no line.
  static func rowLines(_ rows: [ScorecardRow]) -> [String] {
    var lines: [String] = []
    for (index, row) in rows.enumerated() where index > 0 {
      let before = rows[index - 1]
      switch row.name {
      case ScoreRows.joints:
        lines.append(
          jointsLine(
            "Joints", row, before, pays: "Joints pay.", fails: "Joints do not pay"))
      case ScoreRows.steadyJoints:
        lines.append(
          jointsLine(
            "Joints in steady files too", row, before, pays: "Steady files should be used too.",
            fails: "Steady files should not be used too"))
      case ScoreRows.settings:
        lines.append(settingsLine(row, before))
      default:
        if let finder = finders[row.name] { lines.append(finderLine(row, before, finder: finder)) }
      }
    }
    return lines
  }

  /// The finder of each row, by the name `show-settings.json` uses.
  private static let finders = [
    ScoreRows.ownSounds: ShowTuning.ownSound, ScoreRows.repeatedSounds: ShowTuning.repeatSound,
    ScoreRows.repeatedWords: ShowTuning.repeatWords, ScoreRows.meaning: ShowTuning.meaning,
  ]
  /// What `teach_settings.py` asks of a finder before it judges it, and its two rules, over what
  /// the row added to the row before it: more wrong than right seconds turns the finder off for
  /// every show, and under 85 percent of the added seconds being ad turns a finder that skips by
  /// default into one that only asks.
  private static let judgedOverEpisodes = 3
  private static let precisionPercent = 85.0

  /// What a finder row added to the row before it, and what the Mac will do about it the next time
  /// it chooses the settings (the same rule, read from the same numbers).
  private static func finderLine(_ row: ScorecardRow, _ before: ScorecardRow, finder: String) -> String {
    let right = Self.right(row) - Self.right(before)
    let wrong = row.total.cutSeconds - before.total.cutSeconds
    let more = { (seconds: Double, noun: String) in
      seconds < 0 ? "\(time(-seconds)) fewer \(noun)" : "\(time(seconds)) more \(noun)"
    }
    let verdict: String
    if row.total.episodes < judgedOverEpisodes {
      verdict = "The Mac judges a finder only over \(judgedOverEpisodes) or more marked episodes, so it stays as it is."
    } else if wrong - right > epsilon {
      verdict = "The next Teach the phone again turns it off for every show."
    } else if right + wrong > epsilon, right * 100 < precisionPercent * (right + wrong),
      ShowTuning().level(forFinder: finder, show: "") == .skip
    {
      verdict = "The next Teach the phone again makes it only ask on every show."
    } else {
      verdict = "It stays as it is overall."
    }
    return "\(row.name): found \(more(right, "right seconds")) and \(more(wrong, "wrong seconds")). \(verdict)"
  }

  /// The gate of idea 5: more right seconds, and the wrong seconds not up by more than one in a
  /// hundred.
  private static func jointsLine(
    _ label: String, _ row: ScorecardRow, _ before: ScorecardRow, pays: String, fails: String
  ) -> String {
    let gained = right(row) - right(before)
    let verdict: String
    if gained <= epsilon {
      verdict = "\(fails): no more of the ad time is skipped."
    } else if row.total.cutSeconds > before.total.cutSeconds * wrongAllowed + epsilon {
      verdict = "\(fails): show time cut by mistake rose by more than one in a hundred."
    } else {
      verdict = pays
    }
    return "\(label): right seconds \(time(right(row))) (\(time(right(before))) before), "
      + "wrong seconds \(time(row.total.cutSeconds)) (\(time(before.total.cutSeconds)) before), "
      + "caught ads heard before the skip \(time(row.total.heardBeforeSeconds)) "
      + "(\(time(before.total.heardBeforeSeconds))) and after it \(time(row.total.heardAfterSeconds)) "
      + "(\(time(before.total.heardAfterSeconds))). \(verdict)"
  }

  /// The settings row must not be worse than the row above it in right seconds and must be better
  /// or equal in wrong seconds (idea 7). The line says so in either case, with the numbers.
  private static func settingsLine(_ row: ScorecardRow, _ before: ScorecardRow) -> String {
    let lost = right(before) - right(row)
    let more = row.total.cutSeconds - before.total.cutSeconds
    var problems: [String] = []
    if lost > epsilon { problems.append("right seconds fell by \(time(lost))") }
    if more > epsilon { problems.append("wrong seconds rose by \(time(more))") }
    let verdict =
      problems.isEmpty
      ? "The check holds." : "The check does not hold: \(problems.joined(separator: " and "))."
    return "Per-show settings: right seconds \(time(right(row))) (\(time(right(before))) in the row above), "
      + "wrong seconds \(time(row.total.cutSeconds)) (\(time(before.total.cutSeconds))). \(verdict)"
  }

  // MARK: Questions (idea 3)

  /// The questions the word model would ask over some episodes, against the labels.
  struct Questions: Equatable {
    var count = 0
    /// How many of them lie, for at least half of their length, in a marked ad.
    var wereAds = 0
    /// The transcript time the questions were asked over, in hours.
    var hours = 0.0
  }

  /// The starting gate of the question note: at most this many questions an hour, and at least
  /// this share of them ads.
  static let gateMostAnHour = 2.0
  static let gateLeastShare = 0.5

  /// Asks the word model's questions of each episode (`AdAsks.questions`), outside the ads the last
  /// row of the scorecard has for it (`finalAds`), from the chance `from`, and counts the ones
  /// that were ads by the rule of a caught ad (`AdScore.caughtShare`: half of the question).
  static func questions(
    model: AdWordModel, episodes: [TeachingEpisode], finalAds: (TeachingEpisode) -> [FoundAd],
    from: Double, settings: AdSkipSettings = AdSkipSettings()
  ) -> Questions {
    var result = Questions()
    for episode in episodes {
      let seconds = episode.transcript.duration
      guard seconds.isFinite, seconds > 0 else { continue }
      result.hours += seconds / 3600
      let asked = AdAsks.questions(
        model: model, lines: AdChunker.number(episode.transcript.lines),
        duration: episode.episodeLength, from: from, outside: finalAds(episode), source: "word-model")
      result.count += asked.count
      let marked = Spans(
        AdScore.counted(episode, settings).map { (start: $0.start, end: $0.end) }, limit: seconds)
      result.wereAds += asked.filter { question in
        let own = Spans([(start: question.start, end: question.end)], limit: seconds)
        return own.length > 0 && own.overlap(marked) >= AdScore.caughtShare * own.length - epsilon
      }.count
    }
    return result
  }

  /// What happens after the gate, in plain words. Nothing on the Mac raises the cutoff by itself,
  /// so a failed gate says what the phone does meanwhile and who can change it.
  private static let met =
    "Met. The phone asks with the cutoff in \(ShowTuning.fileName) (\(ShowTuning.defaultAsk) unless the Mac chose another)."
  private static let notMet =
    "The phone still asks, at most \(AdAsks.most) an episode, and every ad it was unsure of is still "
    + "skipped with Undo, so nothing is lost; tell Claude and the cutoff will be raised (the Mac does "
    + "not change it by itself yet)."

  /// "Questions per hour" and "share of questions that were ads", and the starting gate.
  static func questionLines(_ asked: Questions) -> [String] {
    guard asked.hours > 0 else { return ["Questions: there is no transcript time to count over."] }
    let seconds = asked.hours * 3600
    guard asked.count > 0 else {
      return ["Questions: none in \(time(seconds)) of transcript, so the word model would ask nothing."]
    }
    let perHour = Double(asked.count) / asked.hours
    let share = Double(asked.wereAds) / Double(asked.count)
    var failed: [String] = []
    if perHour > gateMostAnHour { failed.append("too many questions an hour") }
    if share < gateLeastShare { failed.append("too few of them ads") }
    return [
      "Questions: \(asked.count) question\(asked.count == 1 ? "" : "s") over \(time(seconds)) of transcript "
        + "(\(String(format: "%.1f", perHour)) an hour), \(asked.wereAds) of \(asked.count) were ads "
        + "(\(Int((share * 100).rounded()))%). Only the word model's questions are counted, not the "
        + "repeat finders' or the meaning model's.",
      "Starting gate for the question note: at most 2 an hour and at least half of them ads. "
        + (failed.isEmpty ? met : "Not met: \(failed.joined(separator: " and ")). \(notMet)")
    ]
  }

  // MARK: The phone's own habits (idea 6)

  /// The phone's habits need this many episodes of a show, as the Mac's do.
  private static let leastEpisodes = 3
  /// Two opening ends this close (the phone's first look adds ten seconds to the end) agree.
  private static let endWithin = 10.0

  /// "Own habits agree with the Mac's habits for N of M shows": the phone's `ShowStarts` is
  /// replayed over the episodes in order with `find` (what the phone finds in the head of a
  /// transcript), and the habits it gives are set beside the Mac's `mac`, show by show. A show
  /// counts when both sides have at least three episodes of it; the two agree when both say it
  /// usually opens with an ad, or neither does, and, when both do, the usual end is within ten
  /// seconds.
  static func habitLines(
    episodes: [TeachingEpisode], mac: ShowHabits, find: (TeachingEpisode, Transcript) -> [FoundAd]
  ) -> [String] {
    guard !mac.shows.isEmpty else {
      return ["Own habits were not compared: there is no habits.json for the Mac's side."]
    }
    let reached = AdHeadRules.steps.last ?? 180
    var starts = ShowStarts()
    for episode in episodes where !episode.feed.isEmpty {
      let head = AdScoreRun.head(of: episode.transcript, seconds: reached)
      starts.record(show: episode.feed, ads: find(episode, head), reached: reached)
    }
    let own = starts.habits()
    let feeds = episodes.map(\.feed).reduce(into: [String]()) {
      if !$1.isEmpty, !$0.contains($1) { $0.append($1) }
    }
    var counted = 0
    var agreed = 0
    var left = 0
    for feed in feeds {
      guard let theirs = mac.shows.first(where: { $0.id == feed }) else { continue }
      guard let ours = own.shows.first(where: { $0.id == feed }), ours.episodes >= leastEpisodes,
        theirs.episodes >= leastEpisodes
      else {
        left += 1
        continue
      }
      counted += 1
      let usual = own.usuallyOpensWithAd(show: feed)
      guard usual == mac.usuallyOpensWithAd(show: feed) else { continue }
      if usual, let a = own.openingEnd(show: feed), let b = mac.openingEnd(show: feed),
        abs(a - b) > endWithin
      {
        continue
      }
      agreed += 1
    }
    var line = "Own habits agree with the Mac's habits for \(agreed) of \(counted) show\(counted == 1 ? "" : "s")"
    if left > 0 {
      line += " (\(left) show\(left == 1 ? " has" : "s have") fewer than \(leastEpisodes) episodes on the phone's side or the Mac's, and \(left == 1 ? "is" : "are") left out)"
    }
    return [line + "."]
  }
}
