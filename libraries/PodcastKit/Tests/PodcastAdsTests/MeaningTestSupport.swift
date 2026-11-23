import Foundation

@testable import PodcastAds

/// An embedder made for tests: each sentence maps to a fixed vector from a table, and a sentence
/// that is not in the table has no vector. It counts its calls and can run a hook on each call
/// (a test uses it to move a fake clock).
final class MadeEmbedder: LineEmbedder, @unchecked Sendable {
  let dimension: Int
  let revision: Int
  private let lock = NSLock()
  private var table: [String: [Double]]
  private var asked: [String] = []
  private var hook: (@Sendable () -> Void)?

  init(dimension: Int = 4, revision: Int = 7, table: [String: [Double]]) {
    self.dimension = dimension
    self.revision = revision
    self.table = table
  }

  /// The sentences asked for so far, in order.
  var calls: [String] {
    lock.lock()
    defer { lock.unlock() }
    return asked
  }

  /// The sentences it knows and their vectors.
  var known: [String: [Double]] {
    lock.lock()
    defer { lock.unlock() }
    return table
  }

  func onCall(_ run: @escaping @Sendable () -> Void) {
    lock.lock()
    hook = run
    lock.unlock()
  }

  func set(_ text: String, to vector: [Double]?) {
    lock.lock()
    table[text] = vector
    lock.unlock()
  }

  func vector(for text: String) -> [Double]? {
    lock.lock()
    asked.append(text)
    let run = hook
    let found = table[text]
    lock.unlock()
    run?()
    return found
  }
}

/// A clock that only moves when a test says so.
final class FakeClock: @unchecked Sendable {
  private let lock = NSLock()
  private var seconds = 0.0

  func advance(_ by: Double) {
    lock.lock()
    seconds += by
    lock.unlock()
  }

  func now() -> Double {
    lock.lock()
    defer { lock.unlock() }
    return seconds
  }
}

/// The made sentences of the tests and the model files made from them.
enum Made {
  static let probeOne = "Probe sentence one."
  static let probeTwo = "Probe sentence two."
  /// A line that asks the listener for a favour and one that is plain talk.
  static let ask = "Please leave us a review, it really helps the show."
  static let ask2 = "Tell a friend about us, that is how we grow."
  static let talk = "Rivers carry water down to the sea."
  static let talk2 = "The valley floor was covered in fog."
  /// A line with ad words in it ("go to", a web address, a code) that sits at the ask vector.
  static let adCopy = "Go to example.com/show and use code SHOW."

  static let table: [String: [Double]] = [
    probeOne: [0.5, 0.5, 0.5, 0.5], probeTwo: [0.5, -0.5, 0.5, -0.5],
    ask: [1, 0.1, 0, 0], ask2: [0.9, 0, 0.1, 0],
    talk: [0, 0.1, 1, 0], talk2: [0.1, 0, 0.9, 0.1], adCopy: [0.95, 0.05, 0, 0],
  ]

  static func embedder(revision: Int = 7) -> MadeEmbedder {
    MadeEmbedder(dimension: 4, revision: revision, table: table)
  }

  /// A model file by hand: "host_ask" rises with the first number of a vector and "none" with the
  /// third. `edit` may change the dictionary before it is written.
  static func file(
    dimension: Int = 4, revision: Int = 7, language: String = "en",
    weights: [Float]? = nil, biases: [Double] = [0, 0, 0, 0, 0],
    probes: [(String, [Double])]? = nil, edit: (inout [String: Any]) -> Void = { _ in }
  ) -> Data {
    var rows = [Float](repeating: 0, count: 5 * dimension)
    rows[2] = 5  // none: the third number
    rows[3 * dimension] = 5  // host_ask: the first number
    let chosen = weights ?? rows
    let bytes = chosen.flatMap { value -> [UInt8] in
      let bits = value.bitPattern
      return (0..<4).map { UInt8(truncatingIfNeeded: bits >> (8 * UInt32($0))) }
    }
    let wanted = probes ?? [
      (probeOne, [0.5, 0.5, 0.5, 0.5]), (probeTwo, [0.5, -0.5, 0.5, -0.5]),
    ]
    var json: [String: Any] = [
      "version": 1, "language": language, "revision": revision, "dimension": dimension,
      "classes": AdWordModel.classes,
      "thresholds": ["start": 0.6, "stay": 0.4, "sure": 0.85],
      "weights": Data(bytes).base64EncodedString(), "biases": biases,
      "probes": wanted.map { ["text": $0.0, "vector": $0.1] as [String: Any] },
      "trained": ["episodes": 3],
    ]
    edit(&json)
    return try! JSONSerialization.data(withJSONObject: json)
  }

  /// `count` lines of ten seconds each, with the given texts (the last one repeated if short).
  static func lines(_ texts: [String]) -> [NumberedLine] {
    texts.enumerated().map {
      NumberedLine(
        number: $0.offset + 1, start: Double($0.offset) * 10, end: Double($0.offset) * 10 + 9,
        text: $0.element)
    }
  }
}
