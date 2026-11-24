// LOFI-FORK: the scorecard's row "Plus the passage model": the ads that the passage model's answers
// give, on top of the last finder row (see FORK.md, PassageAnswers.swift and AnswerScoreRow.swift).
// A trial: nothing of it is in the app. Foundation only.
import Foundation
import PodcastTranscripts

enum PassageScoreRow {
  static let name = "Plus the passage model"
  /// The `source` of the ads it makes.
  static let source = "passage-model"

  /// The ads of one episode: the rows (one of five chances for each transcript line) go through
  /// the word model's version 2 decoder, and the spans through the same clean-up as every finder's
  /// (`AdCleanup`: edges, merging, length limits). A finder that only a model backs never says
  /// "sure", so every ad is unsure, as the meaning finder's are.
  static func ads(
    rows: [[Double]], thresholds: AdWordModel.Thresholds, transcript: Transcript
  ) -> [FoundAd] {
    let lines = AdChunker.number(transcript.lines)
    let ranges = AdWordModel.decodeTwo(rows: rows, lines: lines, thresholds: thresholds)
      .compactMap { span -> AdRange? in
        guard let kind = AdKind(sort: span.sort) else { return nil }
        return AdRange(
          startLine: span.firstLine, endLine: span.lastLine, advertiser: "", kind: kind,
          confidence: .unsure)
      }
    var found = AdCleanup.run(ranges: ranges, transcript: transcript)
    for index in found.indices {
      found[index].source = source
      found[index].confidence = min(found[index].confidence, .unsure)
    }
    return found
  }

  /// What the answers give for the scored episodes.
  struct Reading {
    /// What made the answers, as the Mac named it.
    var model: String
    /// The ads of each episode that has an answer that fits its transcript, by episode id.
    var ads: [String: [FoundAd]]
    /// How many episodes have an answer with another number of lines than their transcript, which
    /// means the transcript changed after the answers were made. They are left out.
    var stale: Int
  }

  static func reading(_ saved: PassageAnswers, episodes: [TeachingEpisode]) -> Reading {
    var found: [String: [FoundAd]] = [:]
    var stale = 0
    for episode in episodes {
      guard let answer = saved.episodes[episode.id] else { continue }
      guard answer.rows.count == episode.transcript.lines.count else {
        stale += 1
        continue
      }
      found[episode.id] = ads(
        rows: answer.rows, thresholds: saved.thresholds, transcript: episode.transcript)
    }
    return Reading(model: saved.model, ads: found, stale: stale)
  }

  /// The file of `folder` read for the scored episodes: what its answers give (nil when there is no
  /// file), and a plain sentence when the file cannot be read, which leaves the row out.
  static func read(in folder: URL, episodes: [TeachingEpisode]) -> (reading: Reading?, note: String?) {
    switch PassageAnswers.load(in: folder) {
    case .failure(let problem): return (nil, "The passage model's row is left out: \(problem.message)")
    case .success(let saved): return (saved.map { reading($0, episodes: episodes) }, nil)
    }
  }

  /// The lines about the row: how many scored episodes have answers, its bar, and what it is for.
  static func lines(_ row: ScorecardRow, _ reading: Reading, of episodes: Int) -> [String] {
    var out = AnswerScoreRow.lines(
      name, row, answered: reading.ads.count, of: episodes,
      from: "the passage model (\(reading.model))", others: "the last finder row")
    out.append(
      "  The row stands on the last finder row, whatever other rows come before it. This is a trial: it counts only when it passes at least 10 more breaks than the last finder row on both label sets (score on labels and on labels-snapped) and adds at most 2 more skips with no ad."
    )
    if reading.stale > 0 { out.append(staleNote(reading.stale)) }
    return out
  }

  /// The sentence for answers that do not fit their transcripts.
  static func staleNote(_ stale: Int) -> String {
    "\(stale) episode\(stale == 1 ? " has" : "s have") passage answers that do not match the lines of its transcript (it changed after they were made), so \(stale == 1 ? "it stays" : "they stay") as the last finder row. \"Teach the passage model\" makes them again."
  }
}
