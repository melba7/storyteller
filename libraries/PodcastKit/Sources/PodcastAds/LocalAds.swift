// LOFI-FORK: the ads the phone finds by itself, without Apple's model (see FORK.md).
import Foundation
import PodcastTranscripts

/// The finders that need no model of Apple's and no network: the word rules for sponsor ads and
/// the hosts' own plugs (`AdHeadRules`), the word rules for promos (`AdPromoRules`) and the small
/// model the Mac trained (`AdWordModel`), when the phone has one.
public struct LocalAds: Sendable {
  /// Which finders take part. The scorecard turns them on one at a time.
  public struct Layers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let rules = Layers(rawValue: 1)
    public static let promoRules = Layers(rawValue: 2)
    public static let model = Layers(rawValue: 4)
    public static let all: Layers = [.rules, .promoRules, .model]
  }

  public var model: AdWordModel?
  public var layers: Layers

  public init(model: AdWordModel? = nil, layers: Layers = .all) {
    self.model = model
    self.layers = layers
  }

  /// The runs of lines that are an ad, a promo, a plug or credits. `episodeDuration` is the
  /// length of the whole episode when it is known (the lines may be only its start).
  public func ranges(
    lines: [NumberedLine], sponsors: [SponsorName] = [], episodeDuration: Double? = nil
  ) -> [AdRange] {
    layers.contains(.rules) ? AdHeadRules.find(lines: lines, sponsors: sponsors) : []
  }

  /// The same as ads in seconds, cleaned up the way a detector's answers are.
  public func ads(
    transcript: Transcript, sponsors: [SponsorName] = [], episodeDuration: Double? = nil
  ) -> [FoundAd] {
    let lines = AdChunker.number(transcript.lines)
    return AdCleanup.run(
      ranges: ranges(lines: lines, sponsors: sponsors, episodeDuration: episodeDuration),
      transcript: transcript)
  }
}
