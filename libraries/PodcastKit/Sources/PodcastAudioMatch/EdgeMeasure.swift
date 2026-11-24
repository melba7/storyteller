// LOFI-FORK: how well the strongest change in the sound lines up with exactly placed ad edges
// (see FORK.md and EdgeSound.swift). Foundation only.
import Foundation

/// One episode's peaks and the exact edges of its ad spots, all in seconds.
public struct EdgeEpisode: Sendable, Equatable {
  public var id: String
  public var seconds: Double
  public var peaks: [EdgePeak]
  public var edges: [Double]

  public init(id: String, seconds: Double, peaks: [EdgePeak], edges: [Double]) {
    self.id = id
    self.seconds = seconds
    self.peaks = peaks
    self.edges = edges
  }
}

/// For a set of points: how many have the strongest change within 10 seconds no further than 1, 2
/// and 5 seconds away (`hits` follows `EdgeMeasure.reaches`). A point with no change near it counts
/// for none.
public struct EdgeShares: Sendable, Equatable {
  public var points: Int
  public var hits: [Int]

  public init(points: Int = 0, hits: [Int] = [Int](repeating: 0, count: EdgeMeasure.reaches.count))
  {
    self.points = points
    self.hits = hits
  }

  /// The share of the points that are hit at the reach `reach` of `EdgeMeasure.reaches` (0 with no
  /// points).
  public func share(_ reach: Int) -> Double {
    points == 0 ? 0 : Double(hits[reach]) / Double(points)
  }

  mutating func add(_ times: [Double], peaks: [EdgePeak]) {
    for time in times {
      points += 1
      guard let peak = EdgeSound.strongest(near: time, in: peaks) else { continue }
      for (index, reach) in EdgeMeasure.reaches.enumerated() where abs(peak.time - time) <= reach {
        hits[index] += 1
      }
    }
  }
}

public enum EdgeVerdict: String, Sendable {
  case go = "go"
  case noGo = "no go"
  case undecided = "no verdict"
}

public struct EdgeResult: Sendable, Equatable {
  /// Episodes with at least one exact edge that was counted.
  public var episodes: Int
  /// The exact edges, and as many random points.
  public var edges: EdgeShares
  public var random: EdgeShares
  /// Exact edges not counted, because 3 seconds before or after them run past the episode.
  public var leftOut: Int
  public var verdict: EdgeVerdict
}

/// A small random number generator that gives the same numbers for a seed on every machine.
struct EdgeRandom {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  /// A number from 0 up to, not including, 1.
  mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

public enum EdgeMeasure {
  /// The seed of the random points, so that a run can be repeated.
  public static let seed: UInt64 = 20_261_124
  /// How near, in seconds, the strongest change has to be to count.
  public static let reaches: [Double] = [1, 2, 5]
  /// The plan's go rule, in words.
  public static let rule =
    "the strongest change within 10 seconds lies within 1 second of at least 70% of exact edges, and of at most 10% of random points"

  private static let sorts: Set<String> = ["sponsor", "network_promo", "host_ask", "intro_credits"]

  /// Go when at least 70% of the edges and at most 10% of the random points are hit within 1
  /// second (counted in whole numbers, so 7 of 10 is enough and 2 of 10 random is too many).
  static func verdict(edges: EdgeShares, random: EdgeShares) -> EdgeVerdict {
    guard edges.points > 0 else { return .undecided }
    return edges.hits[0] * 10 >= edges.points * 7 && random.hits[0] * 10 <= random.points
      ? .go : .noGo
  }

  /// Measures the episodes in the order of their ids, so the result does not depend on the order
  /// they come in. Each exact edge whose windows fit is looked at, and as many random points are
  /// drawn in the same episode.
  public static func measure(_ episodes: [EdgeEpisode], seed: UInt64 = seed) -> EdgeResult {
    var generator = EdgeRandom(seed: seed)
    var result = EdgeResult(
      episodes: 0, edges: EdgeShares(), random: EdgeShares(), leftOut: 0, verdict: .undecided)
    for episode in episodes.sorted(by: { $0.id < $1.id }) {
      let fitting = episode.edges.filter { EdgeSound.fits($0, seconds: episode.seconds) }
      result.leftOut += episode.edges.count - fitting.count
      guard !fitting.isEmpty else { continue }
      result.episodes += 1
      result.edges.add(fitting, peaks: episode.peaks)
      result.random.add(
        randomPoints(fitting.count, seconds: episode.seconds, using: &generator),
        peaks: episode.peaks)
    }
    result.verdict = verdict(edges: result.edges, random: result.random)
    return result
  }

  /// `count` points anywhere in an episode where the 3 seconds each side fit.
  static func randomPoints(_ count: Int, seconds: Double, using generator: inout EdgeRandom)
    -> [Double]
  {
    let low = EdgeSound.windowSeconds
    let span = seconds - 2 * low
    return (0..<count).map { _ in low + generator.unit() * span }
  }

  // MARK: Which borders are exact

  /// The starts and ends, in order and each once, that the second download placed: the borders of
  /// a marked ad (high or medium confidence) in `snapped` (`labels-snapped/<id>.json`) that
  /// Claude's own label (`labels/<id>.json`) does not have, and both borders of a stretch that
  /// only the second download found (`"origin": "copy"`). Claude's borders are never exact. When
  /// Claude's label cannot be read, only the added stretches are.
  static func exactEdges(snapped: Data?, claude: Data?) -> [Double] {
    let own = segments(claude)
    let starts = own?.compactMap { number($0["start"]) } ?? []
    let ends = own?.compactMap { number($0["end"]) } ?? []
    func moved(_ time: Double, from borders: [Double]) -> Bool {
      !borders.contains { abs($0 - time) < 0.0005 }
    }
    var found: [Double] = []
    for segment in segments(snapped) ?? [] {
      guard let sort = segment["sort"] as? String, sorts.contains(sort),
        let confidence = segment["confidence"] as? String, ["high", "medium"].contains(confidence),
        let start = number(segment["start"]), let end = number(segment["end"]), end > start
      else { continue }
      let added = segment["origin"] as? String == "copy"
      if added || (own != nil && moved(start, from: starts)) { found.append(start) }
      if added || (own != nil && moved(end, from: ends)) { found.append(end) }
    }
    var once: [Double] = []
    for time in found.sorted() where once.last.map({ time - $0 >= 0.5 }) ?? true {
      once.append(time)
    }
    return once
  }

  private static func segments(_ data: Data?) -> [[String: Any]]? {
    guard let data, let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let list = top["segments"] as? [Any]
    else { return nil }
    return list.compactMap { $0 as? [String: Any] }
  }

  private static func number(_ value: Any?) -> Double? {
    guard let found = (value as? NSNumber)?.doubleValue, found.isFinite else { return nil }
    return found
  }
}
