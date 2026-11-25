// LOFI-FORK: the scorecard's row "Plus the Mac's marks from the night before" (see FORK.md,
// AheadAds.swift and AnswerScoreRow.swift). Foundation only.
//
// HONEST VALUE. On the shelf the marks are made of Claude's own labels, which are also the truth the
// row is scored against, so this row proves only that the matching works: that the words of a
// marked ad are found again in the transcript and give its edges. The real number comes from the
// exam, where an episode is marked once the night before and scored against another marking.
import Foundation
import PodcastTranscripts

enum AheadScoreRow {
  static let name = "Plus the Mac's marks from the night before"
  /// The go rule: this many more breaks pass than the last finder row, with at most this many more
  /// skips with no ad.
  static let neededMore = 20
  static let mostMoreSkips = 1
  /// A mark keeps the first and the last words of its ad, as many as the Mac's file does.
  static let wordsKept = 40

  /// What the marks of the scored episodes are made of, for the report.
  struct Made {
    var file = AheadFile()
    /// The episodes that have at least one mark.
    var episodes = 0
    /// The marked ads in the file, and those left out because a second download of their episode
    /// shows the host put them in.
    var used = 0
    var leftOut = 0
    /// The scored episodes that have a second download (`copies/<id>.truth.txt`).
    var withSecondDownload = 0
  }

  // MARK: The marks

  /// The marks of every scored episode: Claude's own labels of it (`labels/`, whatever label set the
  /// run scores), each with the first and last words of its stretch from the episode's transcript.
  /// Credits are not marked. A marked ad that overlaps, by half of its own length or more, a stretch
  /// where the episode's two downloads differ is left out: that spot is not in both downloads, so
  /// the phone's copy may not carry it. An episode with no second download keeps all its marks.
  /// The file goes through its own text, so it is read as the phone reads the Mac's.
  static func marks(in folder: URL, episodes: [TeachingEpisode], now: Date) -> Made {
    var made = Made()
    var entries: [AheadEntry] = []
    for episode in episodes {
      let differing = differingStretches(in: folder, id: episode.id)
      if differing != nil { made.withSecondDownload += 1 }
      var ads: [AheadMark] = []
      for label in claudeLabels(in: folder, id: episode.id) {
        if differing?.contains(where: { shared(label, $0) * 2 >= label.end - label.start }) == true {
          made.leftOut += 1
        } else {
          ads.append(mark(label, words: episode.transcript.words))
        }
      }
      guard !ads.isEmpty else { continue }
      made.used += ads.count
      entries.append(
        AheadEntry(
          feed: episode.feed, guid: episode.id, title: episode.title,
          marked: now.timeIntervalSince1970, ads: ads))
    }
    made.episodes = entries.count
    let file = AheadFile(writtenAt: now.timeIntervalSince1970, episodes: entries)
    made.file = file.encoded().map { AheadFile(data: $0) } ?? file
    return made
  }

  private struct Label {
    var kind: AdKind
    var confidence: AheadMark.Confidence
    var start: Double
    var end: Double
  }

  /// The stretches of Claude's own label file that are ads of a kind the Mac marks, with their
  /// confidence (low ones too). Nothing when the file cannot be read.
  private static func claudeLabels(in folder: URL, id: String) -> [Label] {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent("labels/\(id).json")),
      let file = try? JSONDecoder().decode(LabelFile.self, from: data)
    else { return [] }
    return file.segments.compactMap { item in
      guard let segment = item.value, let sort = segment.sort, let kind = AdKind(sort: sort),
        kind != .credits, let start = segment.start, let end = segment.end, start.isFinite,
        end.isFinite, end > start, let text = segment.confidence,
        let confidence = AheadMark.Confidence(rawValue: text)
      else { return nil }
      return Label(kind: kind, confidence: confidence, start: start, end: end)
    }
  }

  /// The mark of a label: its first and last words in the transcript (those whose middle lies in
  /// the stretch).
  private static func mark(_ label: Label, words: [TranscriptWord]) -> AheadMark {
    let inside = words.filter {
      (label.start...label.end).contains(($0.start + $0.end) / 2)
    }.map(\.text)
    return AheadMark(
      kind: label.kind, confidence: label.confidence, start: label.start, end: label.end,
      startWords: inside.prefix(wordsKept).joined(separator: " "),
      endWords: inside.suffix(wordsKept).joined(separator: " "))
  }

  private static func shared(_ label: Label, _ stretch: (start: Double, end: Double)) -> Double {
    max(0, min(label.end, stretch.end) - max(label.start, stretch.start))
  }

  // MARK: The second download

  /// The stretches the second download showed the host put in (`copies/<id>.truth.txt`, one stretch
  /// to a line as two times such as `0:33.480 1:02.120`, notes after "#"), or nil when the episode
  /// has no such file. A line that is not two times is left out.
  static func differingStretches(in folder: URL, id: String) -> [(start: Double, end: Double)]? {
    let url = folder.appendingPathComponent("copies/\(id).truth.txt")
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    return text.split(whereSeparator: \.isNewline).compactMap { row in
      let line = row.trimmingCharacters(in: .whitespaces)
      guard !line.hasPrefix("#") else { return nil }
      let times = line.split(whereSeparator: \.isWhitespace).compactMap { clock(String($0)) }
      guard times.count == 2, times[1] > times[0] else { return nil }
      return (times[0], times[1])
    }
  }

  /// Seconds in "12:30", "1:02:03" or "12:30.5"; nil for anything else.
  private static func clock(_ text: String) -> Double? {
    let parts = text.split(separator: ":", omittingEmptySubsequences: false)
    guard (2...3).contains(parts.count) else { return nil }
    var total = 0.0
    for part in parts {
      guard let value = Double(part), value.isFinite, value >= 0 else { return nil }
      total = total * 60 + value
    }
    return total
  }

  // MARK: The row

  /// The row: the last finder row's ads (`finders` keeps them for each whole episode) plus what the
  /// finder gives, sorted by the show's settings before any join, and cut back to the parts
  /// outside the ads of the row it stands on, as every new finder is. On the first look at an
  /// episode's start it stands on the row before it. `kept` keeps the row's ads for each whole
  /// episode, for the stream replay.
  static func layer(
    _ file: AheadFile, tuning: ShowTuning, now: Date, standingOn finders: ScoreEpisodeAds,
    kept: ScoreEpisodeAds
  ) -> AdScoreLayer {
    .rewriting(name: name) { input, soFar in
      let episode = input.episode
      let base = input.isHead ? soFar : finders.ads(for: episode.id) ?? soFar
      var made = base
      if let entry = file.entry(
        guid: episode.id, feed: episode.feed, title: episode.title, now: now)
      {
        let found = AheadAds.find(entry, words: input.transcript.words).ads
        let skips = tuning.apply(to: found, show: episode.feed).skip
        made = AdJoin.join(base + ScoreAds.outside(skips, of: base))
      }
      if !input.isHead { kept.put(made, for: episode.id) }
      return made
    }
  }

  // MARK: What a run of the scorecard adds

  /// Everything `--ahead` adds to one run: the marks, the row's layer and what it kept for the
  /// stream replay.
  struct Run {
    let made: Made
    let layer: AdScoreLayer
    private let kept = ScoreEpisodeAds()

    init(
      folder: URL, episodes: [TeachingEpisode], tuning: ShowTuning, now: Date,
      standingOn finders: ScoreEpisodeAds
    ) {
      made = AheadScoreRow.marks(in: folder, episodes: episodes, now: now)
      layer = AheadScoreRow.layer(
        made.file, tuning: tuning, now: now, standingOn: finders, kept: kept)
    }

    /// The row made of its scorecard, and the text about it.
    func report(_ card: Scorecard, last: ScorecardRow?, scored: Int) -> (
      row: ScorecardRow, text: String
    ) {
      let row = ScorecardRow(name: AheadScoreRow.name, card: card)
      let lines = AheadScoreRow.lines(row, last: last, made: made, scored: scored)
      return (row, lines.joined(separator: "\n"))
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
  static func verdict(last: BarTotals, ahead: BarTotals) -> (go: Bool, line: String) {
    let more = ahead.passed - last.passed
    let skips = ahead.noAdSkips - last.noAdSkips
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

  private static func ads(_ count: Int) -> String { "\(count) marked ad\(count == 1 ? "" : "s")" }

  /// The lines about the row: what the marks are made of and which spots were used, its bar and why
  /// breaks fail in it, the verdict against the last finder row, and what the row is worth.
  static func lines(
    _ row: ScorecardRow, last: ScorecardRow?, made: Made, scored: Int
  ) -> [String] {
    var out = [
      "\(name): \(made.episodes) of \(scored) scored episodes have marks, made of Claude's own labels (labels/) and the words of each transcript, and found again by the phone's finder (AheadAds): \(ads(made.used)) used, \(ads(made.leftOut)) left out."
    ]
    if made.withSecondDownload == 0 {
      out.append(
        "  The scored episodes have no second download, so every marked ad of an episode is used: nothing says which spots the host put into one download only.")
    } else {
      out.append(
        "  \(made.withSecondDownload) of \(scored) scored episodes have a second download (copies/<id>.truth.txt): a marked ad that the host put into one download and not the other (it overlaps a differing stretch by half of its length or more) is left out, as the phone's copy may not carry it. The other episodes have no second download, so all their marked ads are used."
      )
    }
    if let bar = row.bar {
      out.append("  " + StreamReport.barLine(bar))
      let failing = BarCause.allCases.map { ($0, bar.count($0)) }.filter { $0.1 > 0 }
        .sorted { $0.1 > $1.1 }
      out.append(
        "  Why breaks fail in this row: "
          + (failing.isEmpty
            ? "no break fails." : failing.map { "\($0.0.label) \($0.1)" }.joined(separator: ", ") + "."))
      if let before = last?.bar { out.append("  " + verdict(last: before, ahead: bar).line) }
    }
    out.append(
      "  On the shelf the marks are also the truth the row is scored against, so this row proves only that the matching works; the real number comes from the exam (episodes marked the night before, scored against another marking).")
    return out
  }
}
