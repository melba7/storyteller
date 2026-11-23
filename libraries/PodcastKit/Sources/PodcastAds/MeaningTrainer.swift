// LOFI-FORK: trains the meaning model on the Mac (see FORK.md). Foundation only.
import Foundation
import PodcastTranscripts

/// One line of a marked episode: its vector (length 1) and the index of its class in
/// `AdWordModel.classes`.
public struct MeaningExample: Sendable, Equatable {
  public var classIndex: Int
  public var vector: [Float]

  public init(classIndex: Int, vector: [Float]) {
    self.classIndex = classIndex
    self.vector = vector
  }
}

/// Softmax regression with AdaGrad over line vectors, the way `teach_train.py` trains the word
/// model: rate 0.5, L2 of 1e-6 on the weights, and each example's loss weighted by
/// min(5, none count / class count). It is deterministic: the same examples, epochs and seed
/// give the same numbers.
public enum MeaningTrainer {
  public static let rate = 0.5
  public static let epsilon = 1e-8
  public static let l2 = 1e-6

  /// What training gives: `weights` (a row of `dimension` numbers for each class) and one bias for each class.
  public struct Trained: Sendable, Equatable {
    public var weights: [Float]
    public var biases: [Double]
  }

  /// The numbers, or nil when there is nothing to learn from (no usable example) or the sizes
  /// make no sense. An example with a class that does not exist, a vector of another size or a
  /// number that is not finite is left out. `progress` hears one sentence after each pass.
  public static func train(
    examples: [MeaningExample], dimension: Int, epochs: Int = 5, seed: UInt64 = 1,
    progress: (String) -> Void = { _ in }
  ) -> Trained? {
    let classCount = AdMeaningModel.classes.count
    guard (1...AdMeaningModel.maxDimension).contains(dimension), epochs >= 1 else { return nil }
    let usable = examples.filter {
      (0..<classCount).contains($0.classIndex) && $0.vector.count == dimension
        && $0.vector.allSatisfy(\.isFinite)
    }
    guard !usable.isEmpty else { return nil }

    var counts = [Int](repeating: 0, count: classCount)
    for example in usable { counts[example.classIndex] += 1 }
    // How much each class's loss counts: "none" 1, the others min(5, none count / class count).
    let cost = (0..<classCount).map { c -> Double in
      if c == 0 { return 1 }
      return counts[c] > 0 && counts[0] > 0 ? min(5, Double(counts[0]) / Double(counts[c])) : 5
    }

    var weights = [Double](repeating: 0, count: classCount * dimension)
    var biases = [Double](repeating: 0, count: classCount)
    var weightSquares = weights
    var biasSquares = biases
    var order = Array(usable.indices)
    var random = SplitMix64(seed: seed)

    for pass in 1...epochs {
      let started = ProcessInfo.processInfo.systemUptime
      // A shuffle that depends only on the seed.
      for i in stride(from: order.count - 1, to: 0, by: -1) {
        order.swapAt(i, Int(random.next() % UInt64(i + 1)))
      }
      var loss = 0.0
      for index in order {
        let example = usable[index]
        var scores = biases
        for c in 0..<classCount {
          var sum = 0.0
          let base = c * dimension
          for i in 0..<dimension { sum += weights[base + i] * Double(example.vector[i]) }
          scores[c] += sum
        }
        let top = scores.max() ?? 0
        let exps = scores.map { exp($0 - top) }
        let total = exps.reduce(0, +)
        let weight = cost[example.classIndex]
        loss -= weight * log(max(exps[example.classIndex] / total, 1e-12))
        for c in 0..<classCount {
          var slope = weight * exps[c] / total
          if c == example.classIndex { slope -= weight }
          biasSquares[c] += slope * slope
          biases[c] -= rate * slope / (biasSquares[c].squareRoot() + epsilon)
          let base = c * dimension
          for i in 0..<dimension {
            let gradient = slope * Double(example.vector[i]) + l2 * weights[base + i]
            weightSquares[base + i] += gradient * gradient
            weights[base + i] -= rate * gradient / (weightSquares[base + i].squareRoot() + epsilon)
          }
        }
      }
      progress(
        String(
          format: "Pass %d of %d: mean loss %.4f, %.1f seconds.", pass, epochs,
          loss / Double(max(order.count, 1)), ProcessInfo.processInfo.systemUptime - started))
    }

    let limit = 1_000_000.0
    guard weights.allSatisfy({ $0.isFinite && abs($0) <= limit }),
      biases.allSatisfy({ $0.isFinite && abs($0) <= limit })
    else { return nil }
    return Trained(weights: weights.map { Float($0) }, biases: biases)
  }

  // MARK: The class of each line

  /// How long the last line of a transcript counts as lasting.
  static let lastLineSeconds = 5.0

  /// Where each line ends for the training and the check: at the start of the next line, and
  /// `lastLineSeconds` after the last line's start (as `teach_train.py` and `teach_spans.py` count).
  static func lineEnds(of lines: [TranscriptLine]) -> [Double] {
    lines.indices.map { lines.indices.contains($0 + 1) ? lines[$0 + 1].start : lines[$0].start + lastLineSeconds }
  }

  /// For each line of the episode the index of its class in `AdWordModel.classes`: the sort of
  /// the first stretch marked with high or medium confidence that covers it, 0 ("none") when no
  /// stretch does, and nil when only a low-confidence stretch covers it (such a line is left out
  /// of training and of the check). This is the rule of `teach_train.py`'s `line_classes`. The
  /// stretches come with times as well as line numbers, and the times are rounded to a tenth,
  /// so a line belongs to a stretch when the middle of the line falls inside it. The line ends
  /// are the ones the check uses (`lineEnds`), so a stretch that runs to the last line covers it
  /// even when the episode goes on for a long time after that line starts.
  public static func lineClasses(for episode: TeachingEpisode) -> [Int?] {
    let lines = episode.transcript.lines
    let ends = lineEnds(of: lines)
    return lines.indices.map { index in
      let middle = (lines[index].start + ends[index]) / 2
      func covers(_ stretch: TeachingTruth) -> Bool { middle >= stretch.start && middle < stretch.end }
      if let strong = episode.truth.first(where: covers),
        let found = AdMeaningModel.classes.firstIndex(of: strong.sort)
      {
        return found
      }
      return episode.maybe.contains(where: covers) ? nil : 0
    }
  }
}

/// A small random number generator that gives the same numbers for a seed on every machine.
struct SplitMix64 {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
