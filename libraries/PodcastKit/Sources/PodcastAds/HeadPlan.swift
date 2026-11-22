// LOFI-FORK: how a stream's head scan follows what the Mac taught (see FORK.md).
//
// The scan's steps and its counting of the model's answers follow the show's habits (`ShowHabits`),
// and the diary line of the local layers is made here so it can be tested. Foundation only.
import Foundation

/// How a stream's head scan follows what the Mac taught about the show: a show that usually opens
/// with an ad gets a first look that covers its usual opening, and its unsure answers count from
/// the first step. Any other show (and a show nothing is taught about) gets the usual steps.
public struct HeadPlan: Equatable, Sendable {
  /// The seconds of audio after which each step ends.
  public let steps: [Double]
  /// The steps after which the model is asked.
  public let modelSteps: Set<Double>
  /// Whether the show usually opens with an ad.
  public let opensWithAd: Bool

  public init(habits: ShowHabits, show: String?) {
    let look = show.flatMap { habits.firstLook(show: $0) }
    steps = AdHeadRules.steps(firstLook: look)
    modelSteps = AdHeadRules.modelSteps(firstLook: look)
    opensWithAd = show.map { habits.usuallyOpensWithAd(show: $0) } ?? false
  }

  /// The model's answer at `step`, as far as it counts for this show.
  public func counted(_ answer: [AdRange], atStep step: Double) -> [AdRange] {
    AdHeadRules.counted(answer, atStep: step, opensWithAd: opensWithAd)
  }
}

/// The diary lines of a head scan that are worth testing.
public enum HeadNotes {
  /// What the local layers (word rules, promo rules, the small model) and the taught sounds found
  /// at one step, and how long they took.
  public static func local(ads: Int, sounds: Int, milliseconds: Int) -> String {
    let one = { (count: Int) in "\(count) ad\(count == 1 ? "" : "s")" }
    return "local: \(one(ads)), sounds: \(one(sounds)) in \(milliseconds) ms"
  }
}
