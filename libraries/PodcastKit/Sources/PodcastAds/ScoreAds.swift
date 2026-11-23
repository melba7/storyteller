// LOFI-FORK: small pure helpers for the scorecard's new rows (see FORK.md and AdScoreLayer.swift).
// Foundation only.
import Foundation

/// A stretch of audio a sound finder gave, in seconds, with the sort of ad it holds ("sponsor",
/// "network_promo", "host_ask" or "intro_credits").
public struct ScoreSpan: Sendable, Equatable {
  public var start: Double
  public var end: Double
  public var sort: String

  public init(start: Double, end: Double, sort: String = "sponsor") {
    self.start = start
    self.end = end
    self.sort = sort
  }
}

/// The names of the scorecard's rows that the new finders add, word for word what
/// `teach_settings.py` reads (its `ROWS`). A row that is renamed here is ignored there without a
/// word, so `ScoreRowsTests` reads that file and checks every name.
public enum ScoreRows {
  public static let ownSounds = "Plus the phone's own sounds"
  public static let repeatedSounds = "Plus repeated sounds"
  public static let repeatedWords = "Plus repeated words"
  public static let meaning = "Plus the meaning model"
  public static let joints = "Plus joints"
  public static let steadyJoints = "Plus joints (steady files too)"
  public static let settings = "Plus per-show settings"

  /// The rows that need the episode's audio.
  public static let needingAudio = [ownSounds, repeatedSounds, joints, steadyJoints]
}

public enum ScoreAds {
  /// A new finder's ad stays this many seconds away from an ad that is there already, so
  /// `AdJoin.join` (which joins ads of one kind that lie within half a second) never fuses the two
  /// and the older ad keeps its borders and its confidence.
  public static let apart = 1.0

  /// The parts of `new` that lie outside `existing` (and `apart` seconds beyond it), so a new
  /// finder only ADDS stretches and never lengthens or upgrades what an older finder found
  /// (rule 2 of the round plan). A part shorter than `AdRules.minLength` is dropped. An ad that is
  /// not a stretch of finite times is dropped. Sorted by start.
  public static func outside(
    _ new: [FoundAd], of existing: [FoundAd], apart: Double = ScoreAds.apart
  ) -> [FoundAd] {
    let holes = existing.filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start }
      .map { (start: $0.start - apart, end: $0.end + apart) }
      .sorted { $0.start < $1.start }
    var parts: [FoundAd] = []
    for ad in new where ad.start.isFinite && ad.end.isFinite && ad.end > ad.start {
      var from = ad.start
      for hole in holes {
        if hole.end <= from { continue }
        if hole.start >= ad.end { break }
        if hole.start > from { parts.append(piece(of: ad, from, hole.start)) }
        from = max(from, hole.end)
      }
      if from < ad.end { parts.append(piece(of: ad, from, ad.end)) }
    }
    return parts.filter { $0.end - $0.start >= AdRules.minLength }.sorted { $0.start < $1.start }
  }

  private static func piece(of ad: FoundAd, _ start: Double, _ end: Double) -> FoundAd {
    var part = ad
    part.start = start
    part.end = end
    return part
  }

  /// The stretches a sound finder gave as ads of its own: `unsure` (so a skip shows the Undo note),
  /// of the kind of their sort (an ad when the sort is not known), with the finder's name in
  /// `source`. Only stretches of the length of an ad (`AdRules.minLength` to `maxLength`) with
  /// finite times from 0 on.
  public static func ads(_ spans: [ScoreSpan], source: String) -> [FoundAd] {
    spans.compactMap { span in
      guard span.start.isFinite, span.end.isFinite, span.start >= 0,
        (AdRules.minLength...AdRules.maxLength).contains(span.end - span.start)
      else { return nil }
      return FoundAd(
        start: span.start, end: span.end, kind: AdKind(sort: span.sort) ?? .ad, advertiser: "",
        confidence: .unsure, firstWords: "", source: source)
    }
  }

  /// What the phone's own sounds may learn from the ads found so far: the SURE ads of the older
  /// finders and of a listener's yes (source "tap"), never a host ask (read live, it does not
  /// repeat as sound, as the Mac's `podcast-teach sounds` also leaves them out) and never a
  /// skip of a new finder, which is only unsure.
  public static func learnable(_ ads: [FoundAd]) -> [ScoreSpan] {
    ads.filter {
      $0.confidence == .sure && $0.kind != .ownPlug && ($0.source == nil || $0.source == "tap")
        && $0.start.isFinite && $0.end.isFinite && $0.end > $0.start
    }.map { ScoreSpan(start: $0.start, end: $0.end, sort: $0.kind.sortName) }
  }

  /// The ads with their borders moved by `move`, which gets the stretches in order of their start
  /// and gives them back in that order (each one moved or not). The ads keep everything else. If
  /// `move` gives another number of stretches, or one that is not a stretch, the ad stays as it was.
  public static func moved(
    _ ads: [FoundAd], by move: ([ScoreSpan]) -> [ScoreSpan]
  ) -> [FoundAd] {
    let ordered = ads.sorted { $0.start < $1.start }
    let given = move(ordered.map { ScoreSpan(start: $0.start, end: $0.end, sort: $0.kind.sortName) })
    guard given.count == ordered.count else { return ordered }
    return zip(ordered, given).map { ad, span in
      guard span.start.isFinite, span.end.isFinite, span.end > span.start else { return ad }
      var changed = ad
      changed.start = span.start
      changed.end = span.end
      return changed
    }
  }
}

/// Ads kept for each episode while a scorecard run goes on. A layer keeps what it found on the
/// whole transcript so the look at the first seconds (the "head" call) can answer from it, and the
/// joints row keeps the ads it was given so the settings row can start from them. It is one
/// layer's own box; the scorecard calls one layer at a time, and the lock is for the compiler.
public final class ScoreEpisodeAds: @unchecked Sendable {
  private let lock = NSLock()
  private var kept: [String: [FoundAd]] = [:]

  public init() {}

  public func put(_ ads: [FoundAd], for episode: String) {
    lock.lock()
    defer { lock.unlock() }
    kept[episode] = ads
  }

  public func ads(for episode: String) -> [FoundAd]? {
    lock.lock()
    defer { lock.unlock() }
    return kept[episode]
  }
}
