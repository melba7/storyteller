// LOFI-FORK: the scorecard's row "Prepared copy" (see FORK.md, PreparedAds.swift and
// AheadScoreRow.swift). Foundation only.
//
// WHAT IT TESTS. On a copy the Mac prepared, the phone plays the very file the Mac marked, so the
// marks' times are used as they are and no finder of the phone adds to them. Here the marks are the
// labels the run scores (`--labels`, so the snapped ones give the times in the copy), made into
// marks as the row of the nightly marks makes them, put into an entry with a made-up copy, and made
// into the ads file by the phone's own rule (`PreparedAds.file`). That file is played with the same
// skipper against the same truth as every other row. On the shelf the marks are also the truth, so
// the row shows what the phone's rule does with them (a low mark only asks, the ends are cut to the
// length, overlapping marks are joined), not how good Claude's marks are.
import Foundation
import PodcastTranscripts

enum PreparedScoreRow {
  static let name = "Prepared copy"

  /// A copy that only has to be valid: nothing is read from it.
  static let copy = PreparedCopy(
    file: "prepared/score.mp3", sha256: String(repeating: "a", count: 64), bytes: 1)

  struct Made {
    /// The marks of the scored episodes, of every sort the Mac marks, and the ones that ask.
    var marks = 0
    var skips = 0
    var questions = 0
  }

  struct Run {
    let made: Made
    let layer: AdScoreLayer

    init(folder: URL, labels: String, episodes: [TeachingEpisode], now: Date) {
      var files: [String: AdsFile] = [:]
      var made = Made()
      for episode in episodes {
        let marks = AheadScoreRow.claudeLabels(in: folder, id: episode.id, labels: labels).map {
          AheadScoreRow.mark($0, words: episode.transcript.words)
        }
        let entry = AheadEntry(
          feed: episode.feed, guid: episode.id, title: episode.title,
          marked: now.timeIntervalSince1970, ads: marks, copy: PreparedScoreRow.copy)
        // The copy is as long as its audio, which the transcript reaches; the length stated in
        // episodes.json can be shorter, and cutting the marks to it would lose the late ads.
        guard let file = PreparedAds.file(for: entry, duration: episode.transcript.duration) else {
          continue
        }
        files[episode.id] = file
        made.marks += marks.count
        made.skips += file.ads.count
        made.questions += file.asks?.count ?? 0
      }
      self.made = made
      let table = files
      // The phone's own finders leave a prepared copy alone, so the row is the file's ads and
      // nothing else. The first seconds of a stream are not replayed for this row.
      layer = .rewriting(name: PreparedScoreRow.name) { input, soFar in
        input.isHead ? soFar : table[input.episode.id]?.ads ?? soFar
      }
    }

    /// The row made of its scorecard, and its lines.
    func report(_ card: Scorecard, last: ScorecardRow?, scored: Int) -> (
      row: ScorecardRow, text: String
    ) {
      let row = ScorecardRow(name: PreparedScoreRow.name, card: card)
      var out = [
        "\(PreparedScoreRow.name): \(scored) scored episodes played on the copy the Mac marked, from the labels the run scores and the phone's own rule (PreparedAds): \(made.marks) marks, \(made.skips) ads that skip, \(made.questions) questions. Only these ads are played, none of the finders'."
      ]
      if let bar = row.bar {
        out.append("  " + StreamReport.barLine(bar))
        let failing = BarCause.allCases.map { ($0, bar.count($0)) }.filter { $0.1 > 0 }
          .sorted { $0.1 > $1.1 }
        out.append(
          "  Why breaks fail in this row: "
            + (failing.isEmpty
              ? "no break fails." : failing.map { "\($0.0.label) \($0.1)" }.joined(separator: ", ") + "."))
        if let before = last?.bar { out.append("  " + AheadScoreRow.verdict(last: before, ahead: bar).line) }
      }
      return (row, out.joined(separator: "\n"))
    }
  }
}
