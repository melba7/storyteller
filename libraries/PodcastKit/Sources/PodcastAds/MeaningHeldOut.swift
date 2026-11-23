// LOFI-FORK: the check of the meaning model on the held-out episodes (see FORK.md). Foundation only.
import Foundation

/// One held-out episode with its lines' vectors and true classes.
public struct MeaningHeldEpisode: Sendable {
  public var id: String
  public var feed: String
  public var lines: [NumberedLine]
  /// The true class of each line (an index in `AdWordModel.classes`), nil where the labels are unsure.
  public var classes: [Int?]
  /// The vector of each line, nil where the embedding had none.
  public var vectors: [[Double]?]

  public init(
    id: String, feed: String, lines: [NumberedLine], classes: [Int?], vectors: [[Double]?]
  ) {
    self.id = id
    self.feed = feed
    self.lines = lines
    self.classes = classes
    self.vectors = vectors
  }
}

/// The numbers saved under `trained.heldOut` in `ad-meaning.json`, in the shape of the word
/// model's (`teach_shelf.py`'s `evaluate`), so one gate reads both: how many episodes, shows and
/// lines were checked; the seconds the phone would cut and the seconds of real ads; precision and
/// recall in seconds of the spans the phone would cut (`anyAd`); the same for single lines
/// (`lineAnyAd`); and for each class. A ratio with nothing to divide by is nil (null in the file).
public struct MeaningHeldOut: Sendable, Equatable {
  public struct Scores: Sendable, Equatable {
    public var precision: Double?
    public var recall: Double?
  }

  public var episodes: Int
  public var shows: Int
  public var lines: Int
  public var predictedAdSeconds: Double
  public var adSeconds: Double
  public var anyAd: Scores
  public var lineAnyAd: Scores
  public var classes: [String: Scores]

  /// The sorts the phone skips by default: a cut second is right only when the line's true sort is one of these.
  private static let skipped: Set<Int> = [1, 2, 3]

  private static func ratio(_ part: Double, _ whole: Double) -> Double? {
    whole > 0 ? (part / whole * 10_000).rounded() / 10_000 : nil
  }

  private static func scores(_ right: Double, predicted: Double, actual: Double) -> Scores {
    Scores(precision: ratio(right, predicted), recall: ratio(right, actual))
  }

  /// Scores the episodes. The spans are decoded exactly as the phone decodes them. An episode
  /// whose vectors, classes and lines do not match in number is left out.
  public static func check(model: AdMeaningModel, episodes: [MeaningHeldEpisode]) -> MeaningHeldOut {
    let classCount = AdMeaningModel.classes.count
    var checked = 0
    var lineCount = 0
    var hit = 0.0
    var predicted = 0.0
    var actual = 0.0
    var guessed = [Double](repeating: 0, count: classCount)
    var marked = guessed
    var right = guessed
    var cut = 0.0
    var cutRight = 0.0
    var real = 0.0
    var feeds: Set<String> = []
    for episode in episodes {
      let rows = model.probabilities(vectors: episode.vectors)
      guard rows.count == episode.lines.count, episode.classes.count == rows.count else { continue }
      checked += 1
      feeds.insert(episode.feed.isEmpty ? episode.id : episode.feed)
      for (row, known) in zip(rows, episode.classes) {
        guard let truth = known, (0..<classCount).contains(truth) else { continue }
        lineCount += 1
        var guess = 0
        for c in 1..<classCount where row[c] > row[guess] { guess = c }
        if row[0] < 0.5 {
          predicted += 1
          if truth != 0 { hit += 1 }
        }
        if truth != 0 { actual += 1 }
        guessed[guess] += 1
        marked[truth] += 1
        if guess == truth { right[truth] += 1 }
      }
      for (k, truth) in episode.classes.enumerated() {
        if let truth, skipped.contains(truth) { real += episode.lines[k].end - episode.lines[k].start }
      }
      let spans = AdWordModel.decode(rows: rows, lines: episode.lines, thresholds: model.thresholds)
      for span in spans where skipped.contains(AdMeaningModel.classes.firstIndex(of: span.sort) ?? 0) {
        for (k, line) in episode.lines.enumerated()
        where span.firstLine <= line.number && line.number <= span.lastLine {
          let seconds = line.end - line.start
          cut += seconds
          if let truth = episode.classes[k], skipped.contains(truth) { cutRight += seconds }
        }
      }
    }
    var byClass: [String: Scores] = [:]
    for c in 1..<classCount {
      byClass[AdMeaningModel.classes[c]] = scores(right[c], predicted: guessed[c], actual: marked[c])
    }
    return MeaningHeldOut(
      episodes: checked, shows: feeds.count, lines: lineCount,
      predictedAdSeconds: (cut * 10).rounded() / 10, adSeconds: (real * 10).rounded() / 10,
      anyAd: scores(cutRight, predicted: cut, actual: real),
      lineAnyAd: scores(hit, predicted: predicted, actual: actual), classes: byClass)
  }

  /// The numbers as they go into the file.
  public var json: [String: Any] {
    func one(_ value: Scores) -> [String: Any] {
      [
        "precision": value.precision.map { $0 as Any } ?? NSNull(),
        "recall": value.recall.map { $0 as Any } ?? NSNull(),
      ]
    }
    return [
      "episodes": episodes, "shows": shows, "lines": lines,
      "predictedAdSeconds": predictedAdSeconds, "adSeconds": adSeconds, "anyAd": one(anyAd),
      "lineAnyAd": one(lineAnyAd), "classes": classes.mapValues(one),
    ]
  }

  /// The check in plain sentences for the Mac's terminal.
  public var checkLines: [String] {
    func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0 * 100) } ?? "n/a" }
    var found = [
      "Check on \(episodes) held-out episodes from \(shows) shows (\(lines) lines): the phone would cut \(String(format: "%.0f", predictedAdSeconds)) seconds of them, precision \(percent(anyAd.precision)), recall \(percent(anyAd.recall))."
    ]
    for name in AdMeaningModel.classes.dropFirst() {
      guard let one = classes[name] else { continue }
      found.append("  \(name): precision \(percent(one.precision)), recall \(percent(one.recall)).")
    }
    return found
  }
}
