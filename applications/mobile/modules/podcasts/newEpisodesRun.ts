// LOFI-FORK: the podcasts section's automatic downloads and clean-up (see FORK.md).
//
// What the app does for the episodes a refresh just added: each show's newest downloads by itself
// where the show says so (unless the Mac is preparing a copy of it, see coming.ts), they go in Up
// Next where the show says so, and the listener is told. automaticRun.ts calls it. Not imported
// by any test, because the database and the native module are not there.
import {
  type AutomaticSettings,
  type NewEpisode,
  episodesForUpNext,
  episodesToDownload,
} from "./automatic"
import { loadSettings } from "./automaticSettings"
import { sortHeld } from "./coming"
import { heldEpisodeIds } from "./comingRun"
import { getShow, listEpisodesByIds, listShows } from "./db"
import { listDownloads, startDownload } from "./downloadsNative"
import { notifyAboutNewEpisodes } from "./newEpisodeNotify"
import { queueEpisode } from "./upNextNative"

/**
 * Of the episodes that waited for the Mac's copy, the ones that need no download any more: the
 * copy came (or another download was started), the episode was played, or it is gone.
 */
async function settled(waited: readonly NewEpisode[]): Promise<Set<string>> {
  if (waited.length === 0) return new Set()
  const ids = waited.map((episode) => episode.id)
  const have = new Set((await listDownloads()).map((info) => info.episodeId))
  const unplayed = new Set(
    (await listEpisodesByIds(ids)).filter((e) => !e.played).map((e) => e.id),
  )
  return new Set(ids.filter((id) => have.has(id) || !unplayed.has(id)))
}

/**
 * Starts the download of each show's newest new episode. Answers the picked episodes that wait
 * for the Mac's copy instead (coming.ts): they are saved and offered here again on the next run,
 * so one whose copy never comes is downloaded once the wait is over.
 */
async function startNew(
  added: readonly NewEpisode[],
  settings: AutomaticSettings,
): Promise<NewEpisode[]> {
  const shows = await listShows()
  const downloads = new Map(shows.map((s) => [s.id, s.settings.autoDownload]))
  // A show unfollowed during or after the refresh is not in the list: nothing of it downloads.
  const followed = added.filter((episode) => downloads.has(episode.showId))
  const { start, waiting } = sortHeld(
    episodesToDownload(followed, settings, downloads),
    await heldEpisodeIds(),
    Date.now(),
  )
  const skip = await settled(start.filter((e) => e.waitingSince !== undefined))
  for (const episode of start) {
    if (skip.has(episode.id)) continue
    try {
      const show = await getShow(episode.showId)
      await startDownload(
        episode.id,
        episode.audioUrl,
        episode.audioType,
        true,
        show?.language ?? null,
        episode.showId,
      )
    } catch (cause) {
      console.warn("Couldn't start an automatic download", cause)
    }
  }
  return waiting
}

/** Puts new episodes in Up Next for the shows that ask for it, through the native queue. */
async function queueNew(added: readonly NewEpisode[]) {
  const shows = new Map((await listShows()).map((s) => [s.id, s]))
  const modes = new Map(
    [...shows].map(([id, s]) => [id, s.settings.autoUpNext]),
  )
  const picks = episodesForUpNext(added, modes)
  if (picks.length === 0) return
  const stored = new Map(
    (await listEpisodesByIds(picks.map((p) => p.episode.id))).map((e) => [
      e.id,
      e,
    ]),
  )
  for (const { episode, place } of picks) {
    const found = stored.get(episode.id)
    if (!found) continue
    try {
      await queueEpisode(found, shows.get(found.showId) ?? null, place)
    } catch (cause) {
      console.warn("Couldn't add a new episode to Up Next", cause)
    }
  }
}

/**
 * Follows up the episodes a refresh just added, and offers the ones that `waited` for the Mac's
 * copy on earlier runs for download again. Answers the episodes that wait now.
 */
export async function followUp(
  added: readonly NewEpisode[],
  settings: AutomaticSettings | undefined,
  waited: readonly NewEpisode[],
): Promise<NewEpisode[]> {
  if (added.length + waited.length === 0) return []
  try {
    const waiting = await startNew(
      [...waited, ...added],
      settings ?? (await loadSettings()),
    )
    if (added.length > 0) {
      await queueNew(added)
      await notifyAboutNewEpisodes(added)
    }
    return waiting
  } catch (cause) {
    console.warn("Couldn't act on the new episodes", cause)
    return [...waited]
  }
}
