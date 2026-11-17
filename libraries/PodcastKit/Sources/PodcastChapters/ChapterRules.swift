// LOFI-FORK: which chapter is playing and where the chapter buttons go (see FORK.md).
import Foundation

public enum ChapterRules {
  /// "Previous" goes to the start of this chapter when more than this many seconds into it.
  public static let previousGrace = 3.0

  /// The chapter playing at `position`: the last one that has started. Nil before the first
  /// one starts, with no chapters, or after a chapter's own end when it has a gap after it.
  public static func current(at position: Double, in chapters: [Chapter]) -> Int? {
    guard position.isFinite, let index = chapters.lastIndex(where: { $0.start <= position })
    else { return nil }
    if let end = chapters[index].end, position >= end,
      !chapters.indices.contains(index + 1) || chapters[index + 1].start > end
    { return nil }
    return index
  }

  /// Where a chapter ends: its own end time, else where the next starts, else the episode's end.
  public static func end(of index: Int, in chapters: [Chapter], duration: Double?) -> Double? {
    guard chapters.indices.contains(index) else { return nil }
    if let end = chapters[index].end { return end }
    if chapters.indices.contains(index + 1) { return chapters[index + 1].start }
    guard let duration, duration.isFinite, duration > chapters[index].start else { return nil }
    return duration
  }

  /// The previous chapter button: the start of this chapter when more than 3 seconds into it,
  /// else the start of the one before (the start of the episode from the first chapter).
  public static func previousTarget(at position: Double, in chapters: [Chapter]) -> Double {
    guard let index = current(at: position, in: chapters) else { return 0 }
    if position - chapters[index].start > previousGrace { return chapters[index].start }
    return index > 0 ? chapters[index - 1].start : 0
  }

  /// The next chapter button: the start of the next chapter, nil in the last one.
  public static func nextTarget(at position: Double, in chapters: [Chapter]) -> Double? {
    guard position.isFinite else { return nil }
    return chapters.first(where: { $0.start > position + 0.001 })?.start
  }
}

/// Skipping the chapters the listener switched off. The player calls `check` as it plays and
/// `seeked` whenever the playhead is moved; a chapter the listener seeked into plays.
public struct ChapterSkipper: Sendable {
  /// Chapters' `key`s that are skipped.
  public private(set) var skipped: Set<Int>
  /// Chapters (by key) the playhead was put in by a seek, until it leaves them.
  private var enteredBySeek: Set<Int> = []

  public init(skipped: Set<Int> = []) { self.skipped = skipped }

  public mutating func set(_ key: Int, skipped on: Bool) {
    if on { skipped.insert(key) } else { skipped.remove(key) }
  }

  /// The playhead was moved to `position`.
  public mutating func seeked(to position: Double, in chapters: [Chapter]) {
    enteredBySeek = []
    if let index = ChapterRules.current(at: position, in: chapters) {
      enteredBySeek.insert(chapters[index].key)
    }
  }

  /// Playback is at `position`. The place to jump to when it is in a skipped chapter that the
  /// listener did not seek into: the end of that chapter and of any skipped ones right after it.
  public mutating func check(
    position: Double, in chapters: [Chapter], duration: Double?
  ) -> Double? {
    guard let index = ChapterRules.current(at: position, in: chapters) else {
      enteredBySeek = []
      return nil
    }
    let key = chapters[index].key
    // Leaving the chapter the listener seeked into ends that permission.
    enteredBySeek = enteredBySeek.filter { $0 == key }
    guard skipped.contains(key), !enteredBySeek.contains(key) else { return nil }
    var last = index
    while chapters.indices.contains(last + 1), skipped.contains(chapters[last + 1].key),
      ChapterRules.end(of: last, in: chapters, duration: duration) == chapters[last + 1].start
    { last += 1 }
    guard let end = ChapterRules.end(of: last, in: chapters, duration: duration), end > position
    else { return nil }
    // A skip to the very end lands just before it so the episode ends as it would have.
    if let duration, duration.isFinite, end >= duration - 0.5 { return max(position, duration - 0.05) }
    return end
  }
}
