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
  }

  public static let usage =
    "Usage: podcast-teach score <teaching folder> [--labels NAME] [--all] [--no-model] [--no-library] [--exam] [--dump FILE] [--stream]"

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
    let plan = ScorePlan.make(folder: folder, episodes: chosen, audio: audio, now: now, extras: extras)
    let finalAds = ScoreEpisodeAds()
    let appleSaved: AppleAnswers?
    switch AppleAnswers.load(in: folder) {
    case .failure(let problem):
      err(problem.message)
      return 2
    case .success(let loaded): appleSaved = loaded
    }
    let apple = AppleScoreRow.answers(appleSaved, episodes: chosen)
    // Own sounds and the repeat finders learn from the earlier episodes of a show. The shelf is one
    // episode of a show, so the labelled episodes that are not scored come first and only teach.
    plan.teach(labelled.filter { episode in !chosen.contains { $0.id == episode.id } }, audio: audio, base: base)
    let layers = [plan.finders.baseRow] + plan.layers + [remembering(finalAds)]
    let allLayers = layers + (apple.map { [AppleScoreRow.layer($0)] } ?? [])
    let made = AdScoreRun.runLayers(
      episodes: chosen, habits: habits, audio: { audio[$0.id] }, base: base, layers: allLayers)
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
    if let apple, let card = made.last {
      let row = ScorecardRow(name: AppleScoreRow.name, card: card)
      text += "\n\n" + AppleScoreRow.lines(row, answered: apple.count, of: chosen.count).joined(separator: "\n")
      saved.append(row)
    }
    if options.stream {
      let detect: (TeachingEpisode, Transcript) -> [FoundAd] = { episode, transcript in
        let input = AdScoreInput(episode: episode, transcript: transcript, audio: audio[episode.id])
        var soFar = base(episode, transcript)
        for layer in layers { soFar = layer.apply(input, soFar: soFar) }
        return soFar
      }
      let streamed = StreamScore.run(
        episodes: chosen, habits: habits, settings: AdSkipSettings(), models: apple,
        whole: { finalAds.ads(for: $0.id) ?? [] }, detect: detect)
      var shown = [(name: String, ready: BarTotals?, stream: StreamNumbers)]()
      shown.append((rows.last?.name ?? "", rows.last?.bar, streamed.finders))
      saved[rows.count - 1].stream = streamed.finders
      if let more = streamed.withModel, let row = saved.last, saved.count == rows.count + 1 {
        shown.append((row.name, row.bar, more))
        saved[rows.count].stream = more
      }
      text += "\n\n" + StreamReport.lines(shown).joined(separator: "\n")
    }
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
