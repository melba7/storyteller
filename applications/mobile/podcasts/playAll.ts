// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Alert } from "react-native"

import {
  type PlaylistEntry,
  playAllPlan,
  runPlayAll,
} from "@/modules/podcasts/manualPlaylist"
import { readableError } from "@/modules/podcasts/nativeError"
import { player } from "@/modules/podcasts/playerInstance"
import { queueEpisode } from "@/modules/podcasts/upNextNative"

/** Plays the first episode of a playlist and puts the rest in Up Next, in order, after it. */
export async function playAll(entries: readonly PlaylistEntry[]) {
  const plan = playAllPlan(entries.map((entry) => entry.episode.id))
  const byId = new Map(entries.map((entry) => [entry.episode.id, entry]))
  try {
    // The first plays before the rest are queued: starting it queues what was playing, and
    // the rest must land ahead of that.
    await runPlayAll(plan, {
      play: async (id) => {
        const entry = byId.get(id)
        if (entry) await player.playEpisode(entry.episode, entry.show)
      },
      queue: async (id, place) => {
        const entry = byId.get(id)
        if (entry) await queueEpisode(entry.episode, entry.show, place)
      },
    })
  } catch (cause) {
    Alert.alert("Couldn't play the playlist", readableError(cause))
  }
}
