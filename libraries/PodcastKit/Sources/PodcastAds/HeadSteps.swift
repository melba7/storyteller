// LOFI-FORK: the steps of a stream's head scan (see FORK.md).
//
// The scan grows its copy of the file step by step (15, 30, 60 seconds and so on). When a
// remembered ad opens at the end of the transcript, the next step ends where that ad should end
// plus a little, so the whole ad is in the next transcript. Foundation only.
import Foundation

public struct HeadSteps: Equatable, Sendable {
  private let steps: [Double]
  private var index = 0
  /// A step made by a jump replaces the plain one for now; the plain steps go on after it.
  private var current: Double?
  private var asked: Double?

  public init(steps: [Double] = AdHeadRules.steps) { self.steps = steps }

  /// The seconds of audio the step now at hand ends at, or nil when the scan is over.
  public var target: Double? { current ?? (index < steps.count ? steps[index] : nil) }

  /// Asks for the next step to end at `seconds` instead of at its own place. Only a place further
  /// than `reached` counts, and never one past the last step. Of several asks the furthest wins.
  public mutating func jump(to seconds: Double, reached: Double) {
    guard let last = steps.last, seconds > reached + 1 else { return }
    asked = max(asked ?? 0, min(seconds, last))
  }

  /// The step at hand is over: on to the next one, which is the jump when one was asked for.
  public mutating func advance() {
    if let place = asked {
      asked = nil
      current = place
      index = steps.firstIndex { $0 > place } ?? steps.count
    } else if current != nil {
      current = nil
    } else if index < steps.count {
      index += 1
    }
  }
}
