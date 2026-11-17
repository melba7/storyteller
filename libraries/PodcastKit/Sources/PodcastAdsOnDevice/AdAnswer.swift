// LOFI-FORK: the shape of the on-device model's answer (see FORK.md).
import Foundation
import PodcastAds

#if canImport(FoundationModels) && compiler(>=6.2)
  import FoundationModels

  @available(iOS 26.0, macOS 26.0, *)
  @Generable
  enum AnswerKind {
    case ad
    case ownPlug
  }

  @available(iOS 26.0, macOS 26.0, *)
  @Generable
  enum AnswerConfidence {
    case sure
    case unsure
    case guess
  }

  /// One run of lines the model says is an ad or a plug.
  @available(iOS 26.0, macOS 26.0, *)
  @Generable
  struct AdSegment {
    @Guide(description: "The number in brackets of the first line of the run.")
    var firstLine: Int

    @Guide(description: "The number in brackets of the last line of the run. Not before firstLine.")
    var lastLine: Int

    @Guide(description: "The advertiser or the show being promoted, as the lines say it. Empty when they do not say.")
    var advertiser: String

    @Guide(description: "ad for a sponsor, commercial or other show's promo; ownPlug for the hosts promoting their own things.")
    var kind: AnswerKind

    @Guide(description: "sure when promotional words show it, unsure when they are thin, guess when it is only a feeling.")
    var confidence: AnswerConfidence
  }

  @available(iOS 26.0, macOS 26.0, *)
  @Generable
  struct AdAnswer {
    @Guide(description: "Every ad or plug in these lines, in order. Empty when there is none.", .maximumCount(8))
    var segments: [AdSegment]
  }

  @available(iOS 26.0, macOS 26.0, *)
  extension AdSegment {
    /// The segment as an `AdRange`, or nil when it names lines that are not in the piece.
    func range(inside piece: TranscriptPiece) -> AdRange? {
      let first = min(firstLine, lastLine)
      let last = max(firstLine, lastLine)
      guard first >= piece.firstNumber, last <= piece.lastNumber else { return nil }
      return AdRange(
        startLine: first, endLine: last,
        advertiser: advertiser.trimmingCharacters(in: .whitespacesAndNewlines),
        kind: kind == .ad ? .ad : .ownPlug,
        confidence: { () -> AdConfidence in
          switch confidence {
          case .sure: return .sure
          case .unsure: return .unsure
          case .guess: return .guess
          }
        }())
    }
  }
#endif
