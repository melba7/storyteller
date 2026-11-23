// LOFI-FORK: the small model that reads what a transcript line means (see FORK.md). Foundation only.
import Foundation

/// Turns a line of text into a list of numbers that stand for its meaning. On the phone and the
/// Mac it is Apple's English sentence embedding (`AppleLineEmbedder` in PodcastAdsOnDevice); the
/// tests use one made from a table. It may be slow, so the model times it (`AdMeaningModel.timedLines`).
public protocol LineEmbedder: Sendable {
  /// How many numbers a line has.
  var dimension: Int { get }
  /// Which revision of the embedding this is. Another revision gives other numbers.
  var revision: Int { get }
  /// The numbers for one line, or nil for a line that is empty or that the embedding does not know.
  func vector(for text: String) -> [Double]?
}

/// Whether the meaning layer can run with an embedder, and if not, why, in a plain sentence.
public enum MeaningState: Sendable, Equatable {
  case ready
  case off(String)
}

/// The class probabilities of an episode's lines from the meaning model, in the shape the word
/// model gives them: one row of five numbers for each line, in the order of the lines (the order
/// of `AdWordModel.classes`, "none" first). `rows` is empty unless `state` is ready.
public struct MeaningRows: Sendable, Equatable {
  public var state: MeaningState
  public var rows: [[Double]]
  /// The seconds a line took, over the first lines (`AdMeaningModel.timedLines`), for the diary.
  public var secondsPerLine: Double?
}

/// A softmax regression over the meaning of a line. The Mac trains it (`MeaningTrainer`) on the
/// vectors of the lines of marked episodes and writes `ad-meaning.json`. The phone loads that file
/// here and says, for each line, how likely it is a sponsor read, a network promo, a host ask,
/// intro or credits, or none of these. It is meant for host-read plugs that use no ad words.
///
/// The contract with the Mac: a line's vector is scaled to length 1 first; the scores are
/// `bias[c] + sum(weights[c * dimension + i] * vector[i])` for each class `c`; the probabilities
/// are their softmax. A line the embedder has no vector for is plain talk. The spans come from
/// the decoder the word model uses (`AdWordModel.decode`).
public struct AdMeaningModel: Sendable, Equatable {
  /// Where the Mac puts the trained file.
  public static let fileName = "ad-meaning.json"
  /// A larger file is refused unread. It is the limit of every teaching file.
  public static let maxBytes = 5_000_000
  /// The most numbers a line may have in a file.
  public static let maxDimension = 4096
  /// The classes, in the order of the weights in the file: the word model's.
  public static let classes = AdWordModel.classes
  /// The only language: Apple's English embedding.
  public static let supportedLanguage = "en"
  /// An embedder's vector for a probe sentence may be this far (straight-line distance between
  /// vectors of length 1) from the one in the file, and no further.
  public static let probeLimit = 0.02
  /// The phone times this many lines at the start of an episode...
  public static let timedLines = 50
  /// ...and leaves the layer out for the episode above this many seconds a line.
  public static let slowSecondsPerLine = 0.030
  /// The two sentences the file carries with their vectors, so the phone can tell at install
  /// time whether its embedding gives the same numbers as the Mac's.
  public static let probeSentences = [
    "Welcome back to the show, today we are talking about how rivers shape the land.",
    "Before we go on, a quick favour: if you enjoy this, please leave us a review.",
  ]

  /// A sentence and the vector the Mac's embedding gave for it.
  public struct Probe: Sendable, Equatable {
    public var text: String
    public var vector: [Double]

    public init(text: String, vector: [Double]) {
      self.text = text
      self.vector = vector
    }
  }

  public let language: String
  public let revision: Int
  public let dimension: Int
  let thresholds: AdWordModel.Thresholds
  /// One row of `dimension` numbers for each class, row by row.
  let weights: [Float]
  let biases: [Double]
  public let probes: [Probe]

  /// What the file holds. Anything else in it (such as `trained`) is ignored.
  private struct FileContents: Decodable {
    var version: Int
    var language: String
    var revision: Int
    var dimension: Int
    var classes: [String]
    var thresholds: [String: Double]?
    var weights: String
    var biases: [Double]
    var probes: [FileProbe]
  }

  private struct FileProbe: Decodable {
    var text: String
    var vector: [Double]
  }

  /// A model from its numbers, or nil when they cannot be trusted: a size that does not fit, a
  /// number that is not finite or is absurdly large, no weights at all (an untrained model would
  /// call every line an ad), or probes that are not two sentences with a vector of the right size.
  init?(
    revision: Int, dimension: Int, thresholds: AdWordModel.Thresholds = AdWordModel.Thresholds(),
    weights: [Float], biases: [Double], probes: [Probe]
  ) {
    let limit = 1_000_000.0
    guard revision >= 0, (1...Self.maxDimension).contains(dimension),
      weights.count == Self.classes.count * dimension,
      weights.allSatisfy({ $0.isFinite && abs(Double($0)) <= limit }),
      weights.contains(where: { $0 != 0 }),
      biases.count == Self.classes.count, biases.allSatisfy({ $0.isFinite && abs($0) <= limit }),
      probes.count == 2,
      probes.allSatisfy({
        !$0.text.isEmpty && $0.vector.count == dimension && $0.vector.allSatisfy { abs($0) <= limit }
          && MeaningVectors.unit($0.vector) != nil
      })
    else { return nil }
    self.language = Self.supportedLanguage
    self.revision = revision
    self.dimension = dimension
    self.thresholds = thresholds
    self.weights = weights
    self.biases = biases
    self.probes = probes
  }

  /// Reads a model file. Returns nil when the file cannot be trusted (see the checks in `init`),
  /// is not version 1 or not English, or is over `maxBytes`.
  public init?(data: Data) {
    guard data.count <= Self.maxBytes,
      let file = try? JSONDecoder().decode(FileContents.self, from: data),
      file.version == 1, file.language == Self.supportedLanguage, file.classes == Self.classes,
      (1...Self.maxDimension).contains(file.dimension),
      let cutoffs = AdWordModel.thresholds(from: file.thresholds),
      let bytes = Data(base64Encoded: file.weights),
      bytes.count == Self.classes.count * file.dimension * 4,
      let weights = Float32Bytes.decode(bytes)
    else { return nil }
    self.init(
      revision: file.revision, dimension: file.dimension, thresholds: cutoffs, weights: weights,
      biases: file.biases, probes: file.probes.map { Probe(text: $0.text, vector: $0.vector) })
  }

  /// Loads the model at `url`, or nil when there is no file or it cannot be trusted.
  public static func load(from url: URL) -> AdMeaningModel? {
    guard let data = try? Data(contentsOf: url), data.count <= maxBytes else { return nil }
    return AdMeaningModel(data: data)
  }

  /// The model as the text of `ad-meaning.json`, keys in order, so the same model gives the
  /// same bytes. `trained` is what the Mac wants to remember about the run (its numbers are
  /// never read back here). Empty data when `trained` holds something a file cannot hold.
  public func fileData(trained: [String: Any]) -> Data {
    let json: [String: Any] = [
      "version": 1, "language": language, "revision": revision, "dimension": dimension,
      "classes": Self.classes,
      "thresholds": ["start": thresholds.start, "stay": thresholds.stay, "sure": thresholds.sure],
      "weights": Float32Bytes.encode(weights).base64EncodedString(), "biases": biases,
      "probes": probes.map { ["text": $0.text, "vector": $0.vector] as [String: Any] },
      "trained": trained,
    ]
    guard JSONSerialization.isValidJSONObject(json),
      let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    else { return Data() }
    return data
  }
}
