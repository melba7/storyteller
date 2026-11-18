// LOFI-FORK: the podcast player's rules (see FORK.md). Plain values, no AVFoundation.
import Foundation

/// Where the player says the episode is while a seek may still be on its way.
public enum Playhead {
  /// The place to show, save and skip from. The player's clock (`reported`) is the old place
  /// until a seek lands, and for a stream resumed far into the episode that is until the bytes
  /// up to the place have arrived. So while a seek is pending, where it is going is the place.
  /// A target that is not a usable number is ignored, and a clock that is not one reads 0.
  public static func place(reported: Double, seekPending: Bool, seekTarget: Double) -> Double {
    if seekPending, seekTarget.isFinite { return max(0, seekTarget) }
    return reported.isFinite ? max(0, reported) : 0
  }
}
