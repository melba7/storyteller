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
    var found: [AdRange] = []
    if layers.contains(.rules) { found += AdHeadRules.find(lines: lines, sponsors: sponsors) }
    if layers.contains(.promoRules) { found += AdPromoRules.find(lines: lines) }
    // What the rules say about each line, by index.
    let byRules: [Label?] = lines.map { line in
      let covering = found.filter { $0.startLine <= line.number && line.number <= $0.endLine }
      guard let kind = covering.map(\.kind).min(by: { AdJoin.rank($0) < AdJoin.rank($1) }) else {
        return nil
      }
      let same = covering.filter { $0.kind == kind }
      return Label(
        kind: kind, confidence: same.map(\.confidence).max() ?? .unsure,
        advertiser: same.first { !$0.advertiser.isEmpty }?.advertiser ?? "")
    }
    var labels = byRules
    if layers.contains(.model), let model {
      for span in model.spans(lines: lines, duration: episodeDuration) {
        guard let kind = AdKind(sort: span.sort) else { continue }
        let inside = lines.indices.filter {
          span.firstLine <= lines[$0].number && lines[$0].number <= span.lastLine
        }
        let ruled = inside.filter { byRules[$0] != nil }
        for at in inside {
          if var rule = byRules[at] {
            if span.sure { rule.confidence = .sure }
            labels[at] = rule
          } else if let first = ruled.first {
            let near = ruled.last { $0 < at } ?? first
            labels[at] = Label(kind: byRules[near]!.kind, confidence: .unsure, advertiser: "")
          } else {
            labels[at] = Label(kind: kind, confidence: .unsure, advertiser: "")
          }
        }
      }
    }
    return Self.runs(of: labels, lines: lines)
  }

  /// What is known about one line.
  private struct Label {
    var kind: AdKind
    var confidence: AdConfidence
    var advertiser: String
  }

  /// Neighbouring lines of one kind as one range.
  private static func runs(of labels: [Label?], lines: [NumberedLine]) -> [AdRange] {
    var result: [AdRange] = []
    var at = 0
    while at < labels.count {
      guard let first = labels[at] else {
        at += 1
        continue
      }
      var last = at
      var range = AdRange(
        startLine: lines[at].number, endLine: lines[at].number, advertiser: first.advertiser,
        kind: first.kind, confidence: first.confidence)
      while last + 1 < labels.count, let next = labels[last + 1], next.kind == first.kind {
        last += 1
        if range.advertiser.isEmpty { range.advertiser = next.advertiser }
        range.confidence = max(range.confidence, next.confidence)
      }
      range.endLine = lines[last].number
      result.append(range)
      at = last + 1
    }
    return result
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
