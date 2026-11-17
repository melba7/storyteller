// LOFI-FORK: the podcasts section's player (see FORK.md).
//
// The one player the screens share: playback.ts's controller wired to the native module and
// the library database. Not imported by any test, because op-sqlite is native.
import { useEffect, useSyncExternalStore } from "react"

import { onLibraryChanged } from "./changes"
import {
  getEpisode,
  getShow,
  listEpisodes,
  lastPlayedEpisode,
  saveArtworkColor,
  savePlayback,
} from "./db"
import { setPlayed } from "./dbEpisodes"
import { Podcasts } from "./index"
import { type PlayerView, createPlayback } from "./playback"
import { getPlaybackSettings } from "./playbackSettingsStore"
import { isPreviewId } from "./preview"

export const player = createPlayback({
  native: Podcasts,
  savePlayback,
  saveArtworkColor,
  lastPlayedEpisode,
  getShow,
  getEpisode,
  setInterval: (callback, ms) => setInterval(callback, ms),
  clearInterval: (handle) =>
    clearInterval(handle as ReturnType<typeof setInterval>),
  playedWithin: () => getPlaybackSettings().markPlayedWhenLeft,
  report: (cause) => console.warn("Couldn't save the place", cause),
})

// A rename of the loaded episode shows in the mini player.
onLibraryChanged(() => {
  player.refreshEpisode().catch(() => {})
})

/** Marks episodes played or unplayed, and tells the player so its next save keeps the mark. */
export async function markPlayed(
  ids: readonly string[],
  played: boolean,
): Promise<void> {
  await setPlayed(ids, played)
  await player.episodesMarked(ids, played)
}

/** After following a show: a preview episode that is playing becomes its library episode. */
export async function adoptFollowedPreview(showId: string): Promise<void> {
  const current = player.getView().episode
  if (!current || !isPreviewId(current.id)) return
  const [show, episodes] = await Promise.all([
    getShow(showId),
    listEpisodes(showId),
  ])
  player.adoptLibrary(episodes, show)
}

/** The player's state, read again whenever it changes. */
export function usePlayer(): PlayerView {
  return useSyncExternalStore(player.subscribe, player.getView)
}

/**
 * One value from the player's state. `select` must return a plain value (a string, a
 * number, a boolean), so a screen only draws again when that value changes, not on every
 * tick of the clock.
 */
export function usePlayerValue<T extends string | number | boolean | null>(
  select: (view: PlayerView) => T,
): T {
  return useSyncExternalStore(player.subscribe, () => select(player.getView()))
}

/** Reads the last played episode once, so the mini player shows after a restart. */
export function useRestoreLastEpisode() {
  useEffect(() => {
    if (!Podcasts) return
    player.restoreLast().catch(() => {})
  }, [])
}
