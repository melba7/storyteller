// LOFI-FORK: the logic of `podcast-teach score`, here so tests can call it (see FORK.md). Foundation
// only.
import Foundation
import PodcastTranscripts

public enum AdScoreCommand {
  public struct Options: Equatable {
    public var folder: String
    public var labels = "labels"
    public var all = false
    public var noModel = false
    public var noLibrary = false
    /// Score only the sealed exam episodes (`exam.json`).
    public var exam = false
    /// Where to write what the last row found for each scored episode; empty for nowhere.
    public var dump = ""
    /// Also replay every episode as a stream played from the start (StreamScore.swift).
    public var stream = false
    /// The seconds of audio the phone transcribes in one second, as measured (teach_pace.py):
    /// the stream replay uses it for its standard pace. Nil for the assumed one.
    public var speech: Double?
    /// Also add the row "Plus the Mac's marks from the night before" (AheadScoreRow.swift).
    public var ahead = false
    /// Also add the row "Prepared copy" (PreparedScoreRow.swift).
    public var prepared = false
  }

  public static let usage =
    "Usage: podcast-teach score <teaching folder> [--labels NAME] [--all] [--no-model] [--no-library] [--exam] [--dump FILE] [--stream [--speech N]] [--ahead] [--prepared]"

  /// The options in the arguments, or a plain sentence about what is wrong.
  public static func parse(_ arguments: [String]) -> Result<Options, TeachingFolderError> {
    var options = Options(folder: "")
    var index = 0
    while index < arguments.count {
      switch arguments[index] {
      case "--all": options.all = true
      case "--no-model": options.noModel = true
      case "--no-library": options.noLibrary = true
      case "--exam": options.exam = true
      case "--stream": options.stream = true
      case "--ahead": options.ahead = true
      case "--prepared": options.prepared = true
      case "--speech":
        index += 1
        guard index < arguments.count, let speech = Double(arguments[index]), speech.isFinite,
          speech > 0
        else {
          return .failure(
            TeachingFolderError(
              message: "--speech needs a number above 0: the seconds of audio transcribed in one second."))
        }
        options.speech = speech
      case "--dump":
        index += 1
        guard index < arguments.count, !arguments[index].isEmpty else {
          return .failure(TeachingFolderError(message: "--dump needs a file name."))
        }
        options.dump = arguments[index]
      case "--labels":
        index += 1
        guard index < arguments.count, !arguments[index].isEmpty else {
          return .failure(TeachingFolderError(message: "--labels needs a folder name."))
        }
        options.labels = arguments[index]
      case let flag where flag.hasPrefix("--"):
        return .failure(TeachingFolderError(message: "Unknown option \(flag)."))
      case let path:
        guard options.folder.isEmpty else {
          return .failure(TeachingFolderError(message: "Only one teaching folder can be named."))
        }
        options.folder = path
      }
      index += 1
    }
    guard !options.folder.isEmpty else {
      return .failure(TeachingFolderError(message: "Name the teaching folder."))
    }
    guard options.speech == nil || options.stream else {
      return .failure(TeachingFolderError(message: "--speech goes with --stream: it sets the speed of the replay."))
    }
    return .success(options)
  }

  /// Runs the command. 0 it worked (also when nothing is labelled yet), 2 a set-up problem.
  /// `extras` is what the caller adds for the rows that need audio or Apple's sentence embedding.
  public static func run(
    _ arguments: [String], now: Date = Date(), extras: ScoreExtras = ScoreExtras(),
    out: (String) -> Void, err: (String) -> Void
  ) -> Int32 {
    let options: Options
    switch parse(arguments) {
    case .failure(let problem):
      err("\(problem.message)\n\(usage)")
      return 2
    case .success(let parsed): options = parsed
    }
    let folder = URL(fileURLWithPath: options.folder)
    var notes: [String] = []
    let everyone: [TeachingEpisode]
    do {
      everyone = try TeachingFolder.episodes(in: folder, labels: options.labels, notes: &notes)
    } catch {
      err("\(error.localizedDescription)")
      return 2
    }
    for note in notes { err(note) }
    // The exam is invisible unless asked for: out of the scores and out of what teaches the
    // finders. With --exam it is all that is scored and every other episode only teaches.
    let exam = everyone.filter(\.onExam)
    let labelled = options.exam ? everyone : everyone.filter { !$0.onExam }
    if options.exam && exam.isEmpty {
      err("--exam was asked for, but no labelled episode is named in exam.json in \(folder.path).")
      return 2
    }
    guard !labelled.isEmpty else {
      if !exam.isEmpty {
        out(
          "The only marked episodes in \(folder.path) are on the exam (exam.json); --exam scores them.")
      } else {
        out("No episode in \(folder.path) has both a transcript and a label yet.")
      }
      return 0
    }

    let shelf = labelled.filter(\.onShelf)
    let chosen = options.exam ? exam : options.all || shelf.isEmpty ? labelled : shelf
    let which =
      options.exam ? "the \(chosen.count) sealed exam episodes, every other labelled episode only teaches"
      : options.all ? "all \(chosen.count) labelled episodes"
      : shelf.isEmpty ? "all \(chosen.count) labelled episodes (there is no shelf yet)"
      : "the \(chosen.count) shelf episodes the model never saw"
    let title = "Scorecard for \(folder.lastPathComponent): \(which)"

    let model = options.noModel ? nil : AdWordModel.load(from: folder.appendingPathComponent("ad-model.json"))
    let scoringShelf = options.exam || (!options.all && !shelf.isEmpty)
    let libraryRead =
      options.noLibrary
      ? (known: KnownAds(), file: "")
      : TeachingFolder.library(in: folder, now: now, scoringShelf: scoringShelf)
    let library = libraryRead.known
    let habits = TeachingFolder.habits(in: folder)

    var detectors: [(name: String, local: LocalAds, library: KnownAds?)] = [
      ("Word rules", LocalAds(model: nil, layers: [.rules]), nil),
      ("Plus promo rules", LocalAds(model: nil, layers: [.rules, .promoRules]), nil),
    ]
    if let model { detectors.append(("Plus the trained model", LocalAds(model: model, layers: .all), nil)) }
    if !library.ads.isEmpty {
      detectors.append(("Plus the library", LocalAds(model: model, layers: .all), library))
    }
    var rows: [ScorecardRow] = []
    var cards: [Scorecard] = []
    for detector in detectors {
      let card = AdScoreRun.run(episodes: chosen, habits: habits) { episode, transcript in
        find(episode, transcript, detector.local, detector.library)
      }
      cards.append(card)
      rows.append(ScorecardRow(name: detector.name, card: card))
    }
    guard let last = detectors.last else { return 0 }
    let base: (TeachingEpisode, Transcript) -> [FoundAd] = { episode, transcript in
      find(episode, transcript, last.local, last.library)
    }

    // The rows that stand on the finders: each adds one thing to the row before it.
    let audio = TeachingAudio.files(in: folder)
    // The word finders' own ads for the whole episode, with no library and no join: they tell which
    // ads with no source may be pulled back to a joint.
    let words: ScoreWords = { input in
      last.local.ads(transcript: input.transcript, episodeDuration: input.episode.episodeLength)
    }
    let plan = ScorePlan.make(
      folder: folder, episodes: chosen, audio: audio, now: now, extras: extras, words: words)
    let finalAds = ScoreEpisodeAds()
    // A damaged or newer file leaves the Apple row out; `podcast-teach apple` never overwrites it.
    var appleSaved: AppleAnswers?
    var appleNote: String?
    switch AppleAnswers.load(in: folder) {
    case .failure:
      appleNote =
        "Apple's model row is left out: \(AppleAnswers.fileName) in \(folder.path) could not be read (it is damaged or of another version). After the file is moved away, `podcast-teach apple` can make it again."
    case .success(let loaded): appleSaved = loaded
    }
    let apple = AppleScoreRow.answers(appleSaved, episodes: chosen)
    // The phone sorts Apple's answers by the per-show settings before it joins them: the ones that
    // skip make the Apple row (none under the built-in default, which asks).
    let tuning = plan.tuning ?? ShowTuning()
    let placed = apple.map { AppleScoreRow.place($0, episodes: chosen, tuning: tuning) }
    // The passage model's answers (a trial) make a row of their own, after Apple's, that stands on the
    // last finder row. A file that cannot be read leaves the row out.
    let passage = PassageScoreRow.read(in: folder, episodes: chosen)
    let passageAds = passage.reading.map(\.ads).flatMap { $0.isEmpty ? nil : $0 }
    // The Mac's marks of the night before (--ahead), made of Claude's own labels and found again by
    // the phone's finder, make a row of their own after the others that stands on the last finder row.
    let ahead = options.ahead
      ? AheadScoreRow.Run(
        folder: folder, episodes: chosen, tuning: tuning, now: now, standingOn: finalAds) : nil
    // The row of a prepared copy (--prepared) is the very last: the Mac's marks as they are, played on
    // the file they were made on, with none of the phone's own finders added.
    let prepared = options.prepared
      ? PreparedScoreRow.Run(folder: folder, labels: options.labels, episodes: chosen, now: now)
      : nil
    // The last two rows (CueScoreRows.swift): the Mac's opening lines and filled holes, after all the rest.
    let cueRun = CueScoreRows.Run(
      folder: folder, tuning: tuning, onMarks: ahead != nil, standingOn: finalAds)
    // Own sounds and the repeat finders learn from the earlier episodes of a show. The shelf is one
    // episode of a show, so the labelled episodes that are not scored come first and only teach.
    plan.teach(labelled.filter { episode in !chosen.contains { $0.id == episode.id } }, audio: audio, base: base)
    let layers = [plan.finders.baseRow] + plan.layers + [remembering(finalAds)]
    var allLayers: [AdScoreLayer] =
      layers
      + (apple.flatMap { all in
        placed.map { AppleScoreRow.layers(all, placed: $0, standingOn: finalAds) }
      } ?? [])
      + (passageAds.map {
        [AnswerScoreRow.layer(name: PassageScoreRow.name, $0, standingOn: finalAds)]
      } ?? [])
      + (ahead.map { [$0.layer] } ?? []) + cueRun.layers
    if let prepared { allLayers.append(prepared.layer) }
    let everyRow = AdScoreRun.runLayers(
      episodes: chosen, habits: habits, audio: { audio[$0.id] }, base: base, layers: allLayers)
    // The row of the prepared copy is the last one; the rows before it are as without it.
    let made = prepared == nil ? everyRow : Array(everyRow.dropLast())
    for (layer, card) in zip(plan.layers, made.dropFirst()) {
      cards.append(card)
      rows.append(ScorecardRow(name: layer.name, card: card))
    }
    guard let card = cards.last else { return 0 }

    let historyURL = folder.appendingPathComponent(
      options.exam ? ScorecardHistory.examFileName : ScorecardHistory.fileName)
    var history = ScorecardHistory.load(from: historyURL)
    let reportNotes = (libraryRead.file.isEmpty ? [] : ["Library: \(libraryRead.file)"]) + plan.notes
    var text = AdScoreReport.text(
      card, title: title, results: rows.map { LayerResult(name: $0.name, total: $0.total) },
      notes: reportNotes, previous: history.runs.last)
    var after = AdScoreNotes.rowLines(rows) + plan.meaningLines()
    after += questions(
      model: model, episodes: chosen, finalAds: finalAds, from: plan.tuning?.askThreshold)
    after += AdScoreNotes.habitLines(episodes: labelled, mac: habits, find: { episode, head in
      base(episode, head)
    })
    text += "\n\n" + after.joined(separator: "\n")
    let bar = AdBarReport.lines(rows)
    if !bar.isEmpty { text += "\n\n" + bar.joined(separator: "\n") }
    var saved = rows
    // Apple's two rows, then the passage row, as far as they exist (the Mac's marks row is the last one).
    let extra = Array(made.dropFirst(layers.count).dropLast((ahead == nil ? 0 : 1) + cueRun.layers.count))
    if let apple, let placed, extra.count >= 2 {
      let both = AppleScoreRow.report(extra, answered: apple.count, of: chosen.count, placed: placed)
      text += "\n\n" + both.text
      saved += both.rows
    }
    if let appleNote { text += "\n\n" + appleNote }
    if let reading = passage.reading, passageAds != nil, let card = extra.last {
      let row = ScorecardRow(name: PassageScoreRow.name, card: card)
      text += "\n\n" + PassageScoreRow.lines(row, reading, of: chosen.count).joined(separator: "\n")
      saved.append(row)
    } else if let stale = passage.reading?.stale, stale > 0 {
      text += "\n\n" + PassageScoreRow.staleNote(stale)
    }
    if let note = passage.note { text += "\n\n" + note }
    if let ahead, let card = made.dropLast(cueRun.layers.count).last {
      let shown = ahead.report(card, last: rows.last, scored: chosen.count)
      text += "\n\n" + shown.text
      saved.append(shown.row)
    }
    let cueShown = cueRun.report(
      Array(made.suffix(cueRun.layers.count)), last: ahead == nil ? rows.last : saved.last)
    var cueRows = cueShown.rows
    text += "\n\n" + cueShown.text
    var preparedRow: ScorecardRow?
    if let prepared, let card = everyRow.last {
      let shown = prepared.report(card, last: rows.last, scored: chosen.count)
      text += "\n\n" + shown.text
      preparedRow = shown.row
    }
    if options.stream {
      func detecting(_ more: [AdScoreLayer]) -> (TeachingEpisode, Transcript) -> [FoundAd] {
        { episode, transcript in
          let input = AdScoreInput(episode: episode, transcript: transcript, audio: audio[episode.id])
          var soFar = base(episode, transcript)
          for layer in layers + more { soFar = layer.apply(input, soFar: soFar) }
          return soFar
        }
      }
      let streamed = StreamScore.run(
        episodes: chosen, habits: habits, settings: AdSkipSettings(), models: apple, tuning: tuning,
        speech: options.speech, whole: { finalAds.ads(for: $0.id) ?? [] }, detect: detecting([]))
      var shown = [(name: String, stream: StreamNumbers)]()
      shown.append((rows.last?.name ?? "", streamed.finders))
      saved[rows.count - 1].stream = streamed.finders
      if let more = streamed.withModel, saved.count > rows.count {
        shown.append((saved[rows.count].name, more))
        saved[rows.count].stream = more
      }
      if let ahead {
        let more = ahead.streamed(
          episodes: chosen, habits: habits, tuning: tuning, speech: options.speech,
          detect: detecting([ahead.layer]))
        shown.append((AheadScoreRow.name, more))
        saved[saved.count - 1].stream = more
      }
      let cueStreams = cueRun.streamed(
        episodes: chosen, habits: habits, tuning: tuning, speech: options.speech,
        detect: detecting(ahead.map { [$0.layer] } ?? []))
      for (index, numbers) in cueStreams.enumerated() where index < cueRows.count {
        shown.append((cueRows[index].name, numbers))
        cueRows[index].stream = numbers
      }
      let waiting = (episodes: streamed.waiting, of: chosen.count)
      text += "\n\n" + StreamReport.lines(shown, waiting: waiting).joined(separator: "\n")
    }
    saved += cueRows
    if let preparedRow { saved.append(preparedRow) }
    out(text)
    history.append(
      ScorecardRun(
        at: Int64(now.timeIntervalSince1970 * 1000), title: title, total: card.total, rows: saved))
    do {
      try history.save(to: historyURL)
    } catch {
      err("The scorecard could not be saved to \(historyURL.path): \(error.localizedDescription)")
      return 2
    }
    if !options.dump.isEmpty {
      do {
        try AdScoreDump.write(
          chosen, found: { finalAds.ads(for: $0.id) ?? [] },
          to: URL(fileURLWithPath: options.dump))
      } catch {
        err("The dump could not be written to \(options.dump): \(error.localizedDescription)")
        return 2
      }
    }
    return 0
  }

  /// A last, silent row that keeps what the row before it found for each whole episode (not for
  /// the head), so the questions can be asked outside those ads. It adds nothing and its row is
  /// not saved.
  private static func remembering(_ kept: ScoreEpisodeAds) -> AdScoreLayer {
    AdScoreLayer(name: "") { input, soFar in
      if !input.isHead { kept.put(soFar, for: input.episode.id) }
      return []
    }
  }

  /// The questions line and the starting gate; or a plain sentence when there is no word model
  /// to ask them.
  private static func questions(
    model: AdWordModel?, episodes: [TeachingEpisode], finalAds: ScoreEpisodeAds, from: Double?
  ) -> [String] {
    guard let model else {
      return ["Questions: not counted, there is no word model (ad-model.json) to ask them."]
    }
    let asked = AdScoreNotes.questions(
      model: model, episodes: episodes, finalAds: { finalAds.ads(for: $0.id) ?? [] },
      from: from ?? AdAsks.askFrom)
    return AdScoreNotes.questionLines(asked)
  }

  /// What the phone would find in this transcript: the local finders and, when there is a library,
  /// its whole matches, joined.
  static func find(
    _ episode: TeachingEpisode, _ transcript: Transcript, _ local: LocalAds, _ library: KnownAds?
  ) -> [FoundAd] {
    let ads = local.ads(transcript: transcript, episodeDuration: episode.episodeLength)
    guard let library else { return AdJoin.join(ads) }
    let hits = KnownAds().find(in: transcript.words, show: episode.feed, seeds: library)
    let use = KnownAdUse.from(hits, words: transcript.words)
    return AdJoin.join(ads + use.ads.filter { !use.provisional.contains($0) })
  }
}
