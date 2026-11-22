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
  }

  public static let usage =
    "Usage: podcast-teach score <teaching folder> [--labels NAME] [--all] [--no-model] [--no-library]"

  /// The options in the arguments, or a plain sentence about what is wrong.
  public static func parse(_ arguments: [String]) -> Result<Options, TeachingFolderError> {
    var options = Options(folder: "")
    var index = 0
    while index < arguments.count {
      switch arguments[index] {
      case "--all": options.all = true
      case "--no-model": options.noModel = true
      case "--no-library": options.noLibrary = true
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
  public static func run(
    _ arguments: [String], now: Date = Date(), out: (String) -> Void, err: (String) -> Void
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
    let labelled: [TeachingEpisode]
    do {
      labelled = try TeachingFolder.episodes(in: folder, labels: options.labels, notes: &notes)
    } catch {
      err("\(error.localizedDescription)")
      return 2
    }
    for note in notes { err(note) }
    guard !labelled.isEmpty else {
      out("No episode in \(folder.path) has both a transcript and a label yet.")
      return 0
    }

    let shelf = labelled.filter(\.onShelf)
    let chosen = options.all || shelf.isEmpty ? labelled : shelf
    let which =
      options.all ? "all \(chosen.count) labelled episodes"
      : shelf.isEmpty ? "all \(chosen.count) labelled episodes (there is no shelf yet)"
      : "the \(chosen.count) shelf episodes the model never saw"
    let title = "Scorecard for \(folder.lastPathComponent): \(which)"

    let model = options.noModel ? nil : AdWordModel.load(from: folder.appendingPathComponent("ad-model.json"))
    let library = options.noLibrary ? KnownAds() : TeachingFolder.library(in: folder, now: now)
    let habits = TeachingFolder.habits(in: folder)

    var detectors: [(name: String, local: LocalAds, library: KnownAds?)] = [
      ("Word rules", LocalAds(model: nil, layers: [.rules]), nil),
      ("Plus promo rules", LocalAds(model: nil, layers: [.rules, .promoRules]), nil),
    ]
    if let model { detectors.append(("Plus the trained model", LocalAds(model: model, layers: .all), nil)) }
    if !library.ads.isEmpty {
      detectors.append(("Plus the library", LocalAds(model: model, layers: .all), library))
    }
    var cards: [Scorecard] = []
    for detector in detectors {
      cards.append(
        AdScoreRun.run(episodes: chosen, habits: habits) { episode, transcript in
          find(episode, transcript, detector.local, detector.library)
        })
    }
    let layers = zip(detectors, cards).map {
      (name: $0.0.name, caughtShare: share($0.1.total.caught, $0.1.total.ads))
    }
    guard let card = cards.last else { return 0 }

    let historyURL = folder.appendingPathComponent(ScorecardHistory.fileName)
    var history = ScorecardHistory.load(from: historyURL)
    out(AdScoreReport.text(card, title: title, layers: layers, previous: history.runs.last))
    history.append(
      ScorecardRun(at: Int64(now.timeIntervalSince1970 * 1000), title: title, total: card.total))
    do {
      try history.save(to: historyURL)
    } catch {
      err("The scorecard could not be saved to \(historyURL.path): \(error.localizedDescription)")
      return 2
    }
    return 0
  }

  private static func share(_ part: Int, _ whole: Int) -> Double {
    whole == 0 ? 0 : Double(part) / Double(whole)
  }

  /// What the phone would find in this transcript: the local finders and, when there is a library,
  /// its whole matches, joined.
  static func find(
    _ episode: TeachingEpisode, _ transcript: Transcript, _ local: LocalAds, _ library: KnownAds?
  ) -> [FoundAd] {
    let ads = local.ads(transcript: transcript, episodeDuration: episode.transcript.duration)
    guard let library else { return AdJoin.join(ads) }
    let hits = KnownAds().find(in: transcript.words, show: episode.feed, seeds: library)
    let use = KnownAdUse.from(hits, words: transcript.words)
    return AdJoin.join(ads + use.ads.filter { !use.provisional.contains($0) })
  }
}
