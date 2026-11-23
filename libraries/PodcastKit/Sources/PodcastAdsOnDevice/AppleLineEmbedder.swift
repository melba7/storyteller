// LOFI-FORK: Apple's English sentence embedding as a LineEmbedder (see FORK.md).
//
// Written from Apple's documentation of NLEmbedding (NaturalLanguage; `sentenceEmbedding(for:)`
// and `sentenceEmbedding(for:revision:)` are iOS 14 and macOS 11, `vector(for:)` returns
// `[Double]?`, and `dimension` and `revision` are Int). It is compiled only in Fork CI and on a
// Mac, never on Linux, where the NaturalLanguage framework does not exist and this file is empty.
// `NLContextualEmbedding` is not used: it has to download its assets first.
#if canImport(NaturalLanguage)
  import Foundation
  import NaturalLanguage
  import PodcastAds

  /// The meaning model's way to turn a line into numbers on a Mac or a phone.
  ///
  /// Apple says one `NLEmbedding` is not safe for use from several threads at once (it can
  /// crash), so every call into it is made under one lock.
  public final class AppleLineEmbedder: LineEmbedder, @unchecked Sendable {
    public let dimension: Int
    public let revision: Int
    private let embedding: NLEmbedding
    private let lock = NSLock()

    /// The English sentence embedding of this system: its current revision when `revision` is
    /// nil, otherwise that one (the phone asks for the revision the model file was trained on).
    /// Nil when this system has no such embedding.
    public init?(revision: Int? = nil) {
      let candidate: NLEmbedding?
      if let wanted = revision {
        candidate = NLEmbedding.sentenceEmbedding(for: NLLanguage.english, revision: wanted)
      } else {
        candidate = NLEmbedding.sentenceEmbedding(for: NLLanguage.english)
      }
      guard let found = candidate, found.dimension > 0 else { return nil }
      embedding = found
      dimension = found.dimension
      self.revision = found.revision
    }

    /// The numbers for a line, or nil for a line with nothing in it or one the embedding does not know.
    public func vector(for text: String) -> [Double]? {
      let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else { return nil }
      lock.lock()
      defer { lock.unlock() }
      guard let numbers = embedding.vector(for: line), numbers.count == dimension else { return nil }
      return numbers
    }
  }
#endif
