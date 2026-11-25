// LOFI-FORK: the sound at the edges of ad spots (see FORK.md). Foundation only.
//
// An ad that a host or a network drops into an episode is often spoken or mixed differently from
// the show around it, so the sound itself may say where the ad starts and ends. This file measures
// whether it does. For every half second of an episode it works out the loudness, a 24-band
// spectrum and whether it is a pause. A change score compares the 3 seconds before a point with
// the 3 seconds after it, and the peaks of that score are where the sound changes most.
// `EdgeMeasure` then asks how often the strongest change within 10 seconds of an exactly placed
// ad edge lies within a second of it, and `EdgeCommand` runs it on the teaching folder.
//
// What the code calls (a scorecard row that snaps edges onto the peaks would use the same):
//
//   EdgeMeter(sampleRate:)                    mono samples in, in pieces of any size
//     mutating func add(_ samples: [Float])
//     func finish() -> EdgeBlocks             what each half second sounds like
//   EdgeSound.analyse(_ blocks) -> EdgeAnalysis    (seconds, peaks)
//   EdgeSound.strongest(near:in:) -> EdgePeak?     the strongest peak within 10 seconds
import Foundation

/// What each half second of an episode sounds like.
public struct EdgeBlocks: Sendable, Equatable {
  /// The loudness in decibels (20 log10 of the root mean square, 0 dB is full scale; -100 is the
  /// quietest it says).
  public var loudness: [Float] = []
  /// The level of each of the 24 bands in decibels, 24 for each half second one after the other.
  public var bands: [Float] = []
  /// Whether the half second is a pause: 22 dB or more below the episode's speech level.
  public var pause: [Bool] = []

  public init() {}

  public var count: Int { loudness.count }
  public var seconds: Double { Double(count) * EdgeSound.blockSeconds }
}

/// A point where the sound changes more than anywhere near it.
public struct EdgePeak: Sendable, Equatable {
  /// Seconds from the start of the episode.
  public var time: Double
  /// The change score there: about the number of decibels the sound moves.
  public var strength: Float

  public init(time: Double, strength: Float) {
    self.time = time
    self.strength = strength
  }
}

public struct EdgeAnalysis: Sendable, Equatable {
  /// The length of the sound that was read, in whole half seconds.
  public var seconds: Double
  /// The strongest changes, in order of time.
  public var peaks: [EdgePeak]
}

public enum EdgeSound {
  /// Bumped when the way the score is made changes, so that `edges.json` is made again.
  public static let version = 1
  public static let blockSeconds = 0.5
  public static let bandCount = 24
  /// The seconds before and after a point that are compared.
  public static let windowSeconds = 3.0
  /// How far from an edge the strongest change is looked for.
  public static let searchSeconds = 10.0
  /// A change under this many decibels is not a change.
  public static let weakest: Float = 3
  /// At most this many peaks are kept for an hour of sound (and ten for any episode).
  public static let peaksPerHour = 300
  /// How many decibels under the speech level a half second is a pause.
  static let pauseDrop: Float = 22
  /// Under this loudness (about 0.002) the episode has no speech to measure a pause against.
  static let noSpeech: Float = -54
  /// What a pause share of 1 weighs, in decibels. A first guess: it has not been tuned on the shelf.
  static let pauseWeight: Float = 6
  /// A band more than this far under the loudness of its half second is not told apart from it.
  static let shapeFloor: Float = -60
  /// The windows each side of a point, in half seconds.
  private static let window = Int(windowSeconds / blockSeconds)

  /// The edges of the 24 bands in hertz (25 numbers) for a sample rate.
  public static func bandEdges(sampleRate: Double) -> [Double] {
    EdgeSpectrum.edges(sampleRate: sampleRate)
  }

  /// Whether the 3 seconds before and after a point both lie inside an episode of `seconds`.
  public static func fits(_ time: Double, seconds: Double) -> Bool {
    time.isFinite && time >= windowSeconds && time <= seconds - windowSeconds
  }

  public static func analyse(_ blocks: EdgeBlocks) -> EdgeAnalysis {
    EdgeAnalysis(seconds: blocks.seconds, peaks: peaks(scores(blocks), seconds: blocks.seconds))
  }

  // MARK: The change score

  /// The change score at each boundary between half seconds: `scores[k]` is the point at `k / 2`
  /// seconds. It is 0 where the 3 seconds before or after run past the episode. Otherwise it puts
  /// together, in decibels, how much louder or quieter the half seconds with sound in them are,
  /// how differently they are coloured (the 24 bands, with their loudness taken out), and how
  /// different the share of pauses is.
  public static func scores(_ blocks: EdgeBlocks) -> [Float] {
    var result = [Float](repeating: 0, count: blocks.count + 1)
    guard blocks.count >= 2 * window else { return result }
    var before = [Float](repeating: 0, count: bandCount)
    var after = before
    for point in window...(blocks.count - window) {
      let first = profile(blocks, point - window..<point, into: &before)
      let second = profile(blocks, point..<point + window, into: &after)
      var louder: Float = 0
      var colour: Float = 0
      if first.sounding > 0, second.sounding > 0 {
        louder = abs(second.level - first.level)
        for band in 0..<bandCount {
          colour += (after[band] - before[band]) * (after[band] - before[band])
        }
        colour = (colour / Float(bandCount)).squareRoot()
      }
      let pauses = abs(second.pauses - first.pauses) * pauseWeight
      result[point] = (louder * louder + colour * colour + pauses * pauses).squareRoot()
    }
    return result
  }

  /// The mean loudness and the mean colour (in `shape`) of the half seconds with sound in them,
  /// how many there are, and the share of the others, which are pauses.
  private static func profile(
    _ blocks: EdgeBlocks, _ range: Range<Int>, into shape: inout [Float]
  ) -> (level: Float, sounding: Int, pauses: Float) {
    for band in 0..<bandCount { shape[band] = 0 }
    var level: Float = 0
    var sounding = 0
    for index in range where !blocks.pause[index] {
      level += blocks.loudness[index]
      sounding += 1
      for band in 0..<bandCount {
        shape[band] += max(
          blocks.bands[index * bandCount + band] - blocks.loudness[index], shapeFloor)
      }
    }
    if sounding > 0 {
      level /= Float(sounding)
      for band in 0..<bandCount { shape[band] /= Float(sounding) }
    }
    return (level, sounding, Float(range.count - sounding) / Float(range.count))
  }

  /// The points that are the strongest within 1.5 seconds each side and at least `weakest`, in
  /// order of time. A tie goes to the earlier point. An episode keeps its strongest
  /// `peaksPerHour` for each hour (and ten at least), so the list stays small.
  public static func peaks(_ scores: [Float], seconds: Double) -> [EdgePeak] {
    let reach = 3
    var found: [EdgePeak] = []
    for point in scores.indices where scores[point] >= weakest {
      let lower = max(0, point - reach)
      let upper = min(scores.count - 1, point + reach)
      let beaten =
        (lower..<point).contains { scores[$0] >= scores[point] }
        || stride(from: point + 1, through: upper, by: 1).contains { scores[$0] > scores[point] }
      if !beaten {
        found.append(
          EdgePeak(
            time: Double(point) * blockSeconds, strength: (scores[point] * 100).rounded() / 100))
      }
    }
    let keep = max(10, Int((seconds / 3600 * Double(peaksPerHour)).rounded(.up)))
    if found.count > keep {
      found = found.sorted { ($1.strength, $0.time) < ($0.strength, $1.time) }.prefix(keep).sorted {
        $0.time < $1.time
      }
    }
    return found
  }

  /// The strongest peak within 10 seconds of `time` (the nearer one when two are as strong), or
  /// nil when there is none.
  public static func strongest(near time: Double, in peaks: [EdgePeak]) -> EdgePeak? {
    var best: EdgePeak?
    for peak in peaks where abs(peak.time - time) <= searchSeconds {
      guard let held = best else {
        best = peak
        continue
      }
      if peak.strength > held.strength
        || (peak.strength == held.strength && abs(peak.time - time) < abs(held.time - time))
      {
        best = peak
      }
    }
    return best
  }

  /// The half seconds that are pauses: 22 dB or more under the 90th percentile of the loudness,
  /// as in the player's silence trimming. None when the episode has no speech to measure against.
  static func pauses(_ loudness: [Float]) -> [Bool] {
    let sorted = loudness.sorted()
    guard !sorted.isEmpty else { return [] }
    let level = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.9))]
    guard level >= noSpeech else { return [Bool](repeating: false, count: loudness.count) }
    return loudness.map { $0 < level - pauseDrop }
  }
}

/// Measures sound as it arrives: mono samples in pieces of any size, half seconds out.
public struct EdgeMeter: Sendable {
  private let blockSamples: Int
  private var spectrum: EdgeSpectrum
  private var pending: [Float] = []
  private var blocks = EdgeBlocks()

  /// A rate that is not a number, or under 1,000 hertz, counts as 16,000.
  public init(sampleRate: Double) {
    let rate = sampleRate.isFinite && sampleRate >= 1000 ? sampleRate : 16000
    blockSamples = Int((rate * EdgeSound.blockSeconds).rounded())
    spectrum = EdgeSpectrum(sampleRate: rate, blockSamples: blockSamples)
  }

  /// A last piece shorter than half a second is never measured. A sample that is not a number
  /// counts as silence.
  public mutating func add(_ samples: [Float]) {
    var at = 0
    while at < samples.count {
      let take = min(blockSamples - pending.count, samples.count - at)
      pending.append(contentsOf: samples[at..<at + take])
      at += take
      if pending.count == blockSamples { measure() }
    }
  }

  /// The half seconds so far, with the pauses marked.
  public func finish() -> EdgeBlocks {
    var done = blocks
    done.pause = EdgeSound.pauses(done.loudness)
    return done
  }

  private mutating func measure() {
    var squares = 0.0
    for index in pending.indices {
      if !pending[index].isFinite { pending[index] = 0 }
      squares += Double(pending[index]) * Double(pending[index])
    }
    let root = (squares / Double(blockSamples)).squareRoot()
    blocks.loudness.append(Float(20 * log10(max(root, 1e-5))))
    blocks.bands.append(contentsOf: spectrum.bands(of: pending))
    pending.removeAll(keepingCapacity: true)
  }
}
