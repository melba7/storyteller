// LOFI-FORK: the logic of `podcast-teach meaning`, here so tests can call it (see FORK.md).
// Foundation only; the embedder is given to it.
import Foundation
import PodcastTranscripts

public enum MeaningCommand {
  public struct Options: Equatable {
    public var folder: String
    public var labels = "labels"
    public var minEpisodes = 20
    public var epochs = 5
  }

  public static let usage =
    "Usage: podcast-teach meaning <teaching folder> [--labels NAME] [--min-episodes N] [--epochs N]"

  /// What is printed on a machine that has no sentence embedding (Linux, or a Mac without English).
  public static let needsAMac =
    "podcast-teach meaning needs a Mac with Apple's English sentence embedding (the NaturalLanguage framework). It cannot run here."

  /// The options in the arguments, or a plain sentence about what is wrong.
  public static func parse(_ arguments: [String]) -> Result<Options, TeachingFolderError> {
    var options = Options(folder: "")
    var index = 0
    func number() -> Int? {
      index += 1
      guard index < arguments.count, let value = Int(arguments[index]), value >= 1 else { return nil }
      return value
    }
    while index < arguments.count {
      switch arguments[index] {
      case "--min-episodes":
        guard let value = number() else {
          return .failure(TeachingFolderError(message: "--min-episodes needs a whole number from 1."))
        }
        options.minEpisodes = value
      case "--epochs":
        guard let value = number() else {
          return .failure(TeachingFolderError(message: "--epochs needs a whole number from 1."))
        }
        options.epochs = value
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

  /// Runs the command: trains the meaning model on the folder's marked episodes that are not on
  /// the shelf, checks it on the shelf, and writes `<folder>/ad-meaning.json`. Returns 0 when it
  /// worked (also when there is too little to train on, and then no file is written) and 2 for a
  /// set-up problem (no embedder, a bad argument or folder, no vector for any line, no usable
  /// model). The meaning model is optional: whoever runs this as one step of a longer teaching run
  /// (`teach-finish.sh`) must not let an exit code of 2 stop the steps after it. `embedder` is nil
  /// where there is no sentence embedding.
  public static func run(
    _ arguments: [String], embedder: LineEmbedder?, now: Date = Date(),
    out: (String) -> Void, err: (String) -> Void
  ) -> Int32 {
    guard let embedder else {
      err(needsAMac)
      return 2
    }
    let options: Options
    switch parse(arguments) {
    case .failure(let problem):
      err("\(problem.message)\n\(usage)")
      return 2
    case .success(let parsed): options = parsed
    }
    guard (1...AdMeaningModel.maxDimension).contains(embedder.dimension) else {
      err(
        "The sentence embedding says it has \(embedder.dimension) numbers for a line; the meaning model takes 1 to \(AdMeaningModel.maxDimension).")
      return 2
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
    guard !shelf.isEmpty else {
      out(
        "There is no shelf yet (shelf.json is made when the word model is trained), so there are no held-out episodes to check the model on, and no model was written.")
      return 0
    }
    var learning = labelled.filter { !$0.onShelf }
    let repeats = MeaningOverlap.repeating(learning, shelf: shelf)
    if !repeats.isEmpty {
      learning = learning.filter { !repeats.contains($0.id) }
      out(
        "Left \(repeats.count) episode\(repeats.count == 1 ? "" : "s") out of training because \(repeats.count == 1 ? "it is" : "they are") the same as one on the shelf.")
    }
    guard learning.count >= options.minEpisodes else {
      out(
        "Only \(learning.count) episodes are marked and not on the shelf; at least \(options.minEpisodes) are needed to train, so no model was written.")
      return 0
    }

    // The two probe sentences go in the file, so the phone can tell whether its embedding agrees.
    var probes: [AdMeaningModel.Probe] = []
    for sentence in AdMeaningModel.probeSentences {
      guard let raw = embedder.vector(for: sentence), raw.count == embedder.dimension,
        let unit = MeaningVectors.unit(raw)
      else {
        err("The sentence embedding gave no vector for the probe sentence \"\(sentence)\".")
        return 2
      }
      probes.append(
        AdMeaningModel.Probe(text: sentence, vector: unit.map { ($0 * 1_000_000).rounded() / 1_000_000 }))
    }

    // The vectors of every line of every episode we need, kept in meaning-cache/.
    let cache = MeaningCache(
      folder: folder.appendingPathComponent("meaning-cache"), revision: embedder.revision,
      dimension: embedder.dimension, signature: MeaningCache.signature(ofProbe: probes.first?.vector ?? []))
    let wanted = learning + shelf
    var vectors: [String: [[Float]?]] = [:]
    var found = 0
    for (number, episode) in wanted.enumerated() {
      out("Embedding episode \(number + 1) of \(wanted.count): \(episode.id) (\(episode.transcript.lines.count) lines).")
      let rows = cache.vectors(
        id: episode.id, texts: episode.transcript.lines.map(\.text), embedder: embedder)
      found += rows.filter { $0 != nil }.count
      vectors[episode.id] = rows
    }
    guard found > 0 else {
      err("The sentence embedding gave no vector for any line, so nothing could be trained.")
      return 2
    }

    var examples: [MeaningExample] = []
    for episode in learning {
      let classes = MeaningTrainer.lineClasses(for: episode)
      for (line, vector) in (vectors[episode.id] ?? []).enumerated() {
        if let vector, line < classes.count, let index = classes[line] {
          examples.append(MeaningExample(classIndex: index, vector: vector))
        }
      }
    }
    out("Training on \(learning.count) episodes (\(examples.count) lines), with \(shelf.count) on the shelf.")
    guard
      let trained = MeaningTrainer.train(
        examples: examples, dimension: embedder.dimension, epochs: options.epochs, progress: out),
      let model = AdMeaningModel(
        revision: embedder.revision, dimension: embedder.dimension, weights: trained.weights,
        biases: trained.biases, probes: probes)
    else {
      err("Training gave no usable model: there was no marked line with a vector, or the numbers were not finite.")
      return 2
    }

    let held = MeaningHeldOut.check(model: model, episodes: shelf.map { heldEpisode($0, vectors[$0.id] ?? []) })
    let trainedInfo: [String: Any] = [
      "writtenAt": Int((now.timeIntervalSince1970 * 1000).rounded()), "episodes": learning.count,
      "lines": examples.count, "shelf": shelf.count, "heldOut": held.json,
    ]
    let data = model.fileData(trained: trainedInfo)
    // The phone must accept what is written: read it back before it goes out.
    guard AdMeaningModel(data: data) == model else {
      err("The model that was made would not be accepted by the phone, so it was not written.")
      return 2
    }
    let path = folder.appendingPathComponent(AdMeaningModel.fileName)
    do {
      try data.write(to: path, options: .atomic)
    } catch {
      err("The teaching folder cannot be written to: \(error.localizedDescription)")
      return 2
    }
    for line in held.checkLines { out(line) }
    out("Wrote \(path.path) with \(AdMeaningModel.classes.count) rows of \(model.dimension) numbers.")
    return 0
  }

  /// A shelf episode for the check. The lines end as `MeaningTrainer.lineEnds` says (where the next
  /// one starts, five seconds for the last), as the Mac's own check counts them, so both give the
  /// same seconds.
  private static func heldEpisode(_ episode: TeachingEpisode, _ vectors: [[Float]?]) -> MeaningHeldEpisode {
    let source = episode.transcript.lines
    let ends = MeaningTrainer.lineEnds(of: source)
    let lines = source.enumerated().map { index, line in
      NumberedLine(number: index + 1, start: line.start, end: ends[index], text: line.text)
    }
    return MeaningHeldEpisode(
      id: episode.id, feed: episode.feed, lines: lines,
      classes: MeaningTrainer.lineClasses(for: episode),
      vectors: vectors.map { row in row.map { numbers in numbers.map { Double($0) } } })
  }
}
