// LOFI-FORK: the podcasts section's playback settings (see FORK.md).
//
// The settings as the screens and the player controller see them: read once from Swift,
// changed through it. Swift keeps them in UserDefaults and uses them with the screen locked.
// Not imported by any test, because the native module is not there; the rules are in
// playbackSettings.ts.
import { Podcasts } from "./index"
import {
  DEFAULT_PLAYBACK_SETTINGS,
  type PlaybackSettings,
  parsePlaybackSettings,
} from "./playbackSettings"

let current: PlaybackSettings = DEFAULT_PLAYBACK_SETTINGS
let started = false
const listeners = new Set<() => void>()

function publish(next: PlaybackSettings) {
  current = next
  for (const listener of [...listeners]) listener()
}

function start() {
  if (started || Podcasts === null) return
  started = true
  Podcasts.getPlaybackSettings().then(
    (value) => publish(parsePlaybackSettings(value)),
    () => {
      started = false
    },
  )
}

export function getPlaybackSettings(): PlaybackSettings {
  start()
  return current
}

export function subscribePlaybackSettings(listener: () => void): () => void {
  start()
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

/** Shows the new settings at once and saves them; on a failure the old ones come back. */
export async function changePlaybackSettings(
  patch: Partial<PlaybackSettings>,
): Promise<void> {
  const before = current
  const next = { ...before, ...patch }
  publish(next)
  try {
    if (Podcasts !== null) {
      publish(parsePlaybackSettings(await Podcasts.setPlaybackSettings(next)))
    }
  } catch (cause) {
    publish(before)
    throw cause
  }
}
