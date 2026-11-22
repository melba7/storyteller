// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Moves of the playhead that the player makes itself: starting a finished episode over, the
// rewind after a long pause and the Skip ad button's jump. A listener's seek (`seek(to:)`) tells
// the ad skipping, which may read it as "went back into the ad that was just skipped" and save a
// trim, or as "entered an ad by a seek" and play it. None of these is that, so they move the
// playhead without it.

import Foundation
import PodcastChapters
import PodcastPlayback

@MainActor
extension PodcastPlayer {
  /// Moves the playhead to `seconds` as the player's own move. The sound, the chapters and the
  /// recovery place hear of it as they do of a seek, but the ad skipping does not (and the
  /// sleep timer is left alone, so an end-of-chapter timer still pauses).
  func movePlayheadByPlayer(to seconds: Double) {
    let target = Skip.clamp(seconds, duration: currentDuration)
    sound.seeked(to: target)
    let state = ChapterState.shared
    state.skipper.seeked(to: target, in: state.chapters)
    movePlayhead(to: target)
    recovery.moved(to: target)
    publish(positionOverride: target)
  }

  /// A finished episode starts over: the start is the player's choice, so an ad that holds 0:00
  /// is skipped as it is when an episode is loaded.
  func startOver() {
    movePlayheadByPlayer(to: 0)
    adSkipping.startedOver(at: 0)
  }
}
