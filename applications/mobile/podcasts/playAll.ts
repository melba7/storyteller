// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Alert } from "react-native"

import {
  type PlaylistEntry,
  playAllPlan,
} from "@/modules/podcasts/manualPlaylist"
import { readableError } from "@/modules/podcasts/nativeError"
import { player } from "@/modules/podcasts/playerInstance"
import { queueEpisode } from "@/modules/podcasts/upNextNative"

/** Plays the first episode of a playlist and puts the rest in Up Next, in order, after it. */
export async function playAll(entries: readonly PlaylistEntry[]) {
  const plan = playAllPlan(entries.map((entry) => entry.episode.id))
  const byId = new Map(entries.map((entry) => [entry.episode.id, entry]))
  try {
    // The rest go first, so a failure to play leaves them waiting rather than half done.
    for (const step of plan.queue) {
      const entry = byId.get(step.id)
      if (entry) await queueEpisode(entry.episode, entry.show, step.place)
    }
    const first = plan.play === null ? undefined : byId.get(plan.play)
    if (first) await player.playEpisode(first.episode, first.show)
  } catch (cause) {
    Alert.alert("Couldn't play the playlist", readableError(cause))
  }
}
