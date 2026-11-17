import Foundation

/// The order of the transcript and ad queues. The episode that is loaded in the player is
/// "urgent": it goes first, and the episode being worked on stops at its next piece to make
/// way for it. Everything else keeps the order it was queued in.
public enum QueueOrder {
  /// The id to work on next: the urgent one when it is waiting, otherwise the first.
  public static func next(waiting: [String], urgent: String?) -> String? {
    if let urgent, waiting.contains(urgent) { return urgent }
    return waiting.first
  }

  /// Where a paused episode goes back in `waiting`: the front, but behind the urgent one when
  /// that is waiting.
  public static func insertIndex(waiting: [String], urgent: String?) -> Int {
    guard let urgent, let index = waiting.firstIndex(of: urgent) else { return 0 }
    return index + 1
  }

  /// Whether the episode being worked on should stop at its next piece: another episode is
  /// urgent and waiting.
  public static func shouldStop(working: String, waiting: [String], urgent: String?) -> Bool {
    guard let urgent, urgent != working else { return false }
    return waiting.contains(urgent)
  }
}
