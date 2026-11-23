// LOFI-FORK: runs the meaning model on a transcript's lines (see FORK.md). Foundation only.
import Foundation

extension AdMeaningModel {
  /// Whether this embedder gives the numbers the model was trained on: the same number of them
  /// for a line, the same revision, and, for the model's two probe sentences, vectors within
  /// `probeLimit` of the file's. If not, the layer is off and the reason is a plain sentence. It
  /// never traps and never guesses: a different embedding would read every line wrongly.
  public func state(for embedder: LineEmbedder) -> MeaningState {
    guard embedder.dimension == dimension else {
      return .off(
        "The phone's sentence embedding has \(embedder.dimension) numbers for a line but the meaning model was trained on \(dimension).")
    }
    guard embedder.revision == revision else {
      return .off(
        "The phone's sentence embedding is revision \(embedder.revision) but the meaning model was trained on revision \(revision).")
    }
    for probe in probes {
      guard let raw = embedder.vector(for: probe.text), raw.count == dimension,
        let now = MeaningVectors.unit(raw), let wanted = MeaningVectors.unit(probe.vector)
      else {
        return .off("The meaning model's probe sentence could not be turned into numbers on this phone.")
      }
      let gap = MeaningVectors.distance(now, wanted)
      guard gap <= Self.probeLimit else {
        return .off(
          "The probe sentences do not give the same numbers here as on the Mac (off by \(String(format: "%.3f", gap)), the limit is \(Self.probeLimit)).")
      }
    }
    return .ready
  }

  /// The class probabilities of each line, from the vectors the embedder gives. It first checks
  /// `state(for:)`. Then it times the first `timedLines` lines (or all of them, when there are
  /// fewer) with `clock`, which tells seconds from any starting point and defaults to the system
  /// uptime, and gives up above `slowSecondsPerLine` a line: no rows, and the state says how slow.
  /// `duration` is not used by this model; it is here so both models are called the same way.
  public func probabilities(
    lines: [NumberedLine], duration: Double?, embedder: LineEmbedder,
    clock: () -> Double = { ProcessInfo.processInfo.systemUptime }
  ) -> MeaningRows {
    let checked = state(for: embedder)
    guard checked == .ready else { return MeaningRows(state: checked, rows: [], secondsPerLine: nil) }
    var vectors: [[Double]?] = []
    vectors.reserveCapacity(lines.count)
    let timed = min(Self.timedLines, lines.count)
    let begun = clock()
    var perLine: Double?
    for (index, line) in lines.enumerated() {
      vectors.append(embedder.vector(for: line.text))
      if index + 1 == timed {
        let seconds = max(0, clock() - begun) / Double(timed)
        perLine = seconds
        if seconds > Self.slowSecondsPerLine {
          let milliseconds = String(format: "%.0f", seconds * 1000)
          return MeaningRows(
            state: .off(
              "The meaning layer is left out for this episode: a line took \(milliseconds) ms and the limit is \(Int(Self.slowSecondsPerLine * 1000)) ms."),
            rows: [], secondsPerLine: perLine)
        }
      }
    }
    return MeaningRows(state: .ready, rows: probabilities(vectors: vectors), secondsPerLine: perLine)
  }

  /// The class probabilities for already made vectors, one row for each. A vector that is nil, of
  /// the wrong size or without a direction makes plain talk: all of the probability on "none".
  func probabilities(vectors: [[Double]?]) -> [[Double]] {
    let count = Self.classes.count
    return vectors.map { raw in
      guard let raw, raw.count == dimension, let vector = MeaningVectors.unit(raw) else {
        return [1] + [Double](repeating: 0, count: count - 1)
      }
      var scores = biases
      for c in 0..<count {
        var sum = 0.0
        let base = c * dimension
        for i in 0..<dimension { sum += Double(weights[base + i]) * vector[i] }
        scores[c] += sum
      }
      let top = scores.max() ?? 0
      let exps = scores.map { exp($0 - top) }
      let total = exps.reduce(0, +)
      return exps.map { $0 / total }
    }
  }

  /// The spans of the lines, through the decoder the word model uses. None when the layer is off.
  public func spans(
    lines: [NumberedLine], duration: Double?, embedder: LineEmbedder,
    clock: () -> Double = { ProcessInfo.processInfo.systemUptime }
  ) -> [AdWordModel.Span] {
    spans(of: probabilities(lines: lines, duration: duration, embedder: embedder, clock: clock), lines: lines)
  }

  /// The same for rows made already (the rows of `lines`, in order).
  public func spans(of run: MeaningRows, lines: [NumberedLine]) -> [AdWordModel.Span] {
    guard run.state == .ready else { return [] }
    return AdWordModel.decode(rows: run.rows, lines: lines, thresholds: thresholds)
  }
}
