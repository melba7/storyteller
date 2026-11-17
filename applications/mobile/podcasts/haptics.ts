// LOFI-FORK: the podcasts section's screens (see FORK.md).
import * as Haptics from "expo-haptics"

function fire(run: () => Promise<void>) {
  try {
    run().catch(() => {})
  } catch {
    // A missing haptic engine must never break a button.
  }
}

/** A light tap, for pressing play, pause or a skip. */
export function tap() {
  fire(() => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light))
}

/** A small tick for choosing a place or a value, such as letting go of the seek bar. */
export function pick() {
  fire(() => Haptics.selectionAsync())
}

/** The success buzz, for something that finished. */
export function done() {
  fire(() =>
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success),
  )
}
