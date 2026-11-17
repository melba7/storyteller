import { syncApplePodcasts } from "./appleSync"
import { archivesByItself, episodesToArchive } from "./archive"
// LOFI-FORK: the podcasts section's automatic downloads and clean-up (see FORK.md).
//
// What the app does by itself when it comes to the front and in the background task: follow
// what the Mac wrote from Apple Podcasts (appleSync.ts), read every feed, download each show's
// newest new episode (always on Wi-Fi), put new episodes in Up Next where a show says so,
// delete played downloads after a day and archive what each show's rules say. The rules are
// in automatic.ts and archive.ts. Not imported by any test, because the database and the
// native module are not there.
import {
  type AutomaticSettings,
  downloadsToDelete,
  episodesForUpNext,
  episodesToDownload,
  refreshDue,
} from "./automatic"
import { loadLastRun, loadSettings, saveLastRun } from "./automaticSettings"
import { getShow, listEpisodes, listEpisodesByIds, listShows } from "./db"
import { refreshAllShows } from "./dbFeeds"
import { archiveEpisodes, syncShowSettings } from "./dbSettings"
import { deleteDownload, listDownloads, startDownload } from "./downloadsNative"
import { player } from "./playerInstance"
import { listUpNext, queueEpisode } from "./upNextNative"

let running: Promise<void> | null = null

type Added = Awaited<ReturnType<typeof refreshAllShows>>["added"]

async function startNew(added: Added, settings: AutomaticSettings) {
  const shows = await listShows()
  const downloads = new Map(shows.map((s) => [s.id, s.settings.autoDownload]))
  for (const episode of episodesToDownload(added, settings, downloads)) {
    try {
      const show = await getShow(episode.showId)
      await startDownload(
        episode.id,
        episode.audioUrl,
        episode.audioType,
        true,
        show?.language ?? null,
      )
    } catch (cause) {
      console.warn("Couldn't start an automatic download", cause)
    }
  }
}

/** Puts new episodes in Up Next for the shows that ask for it, through the native queue. */
async function queueNew(added: Added) {
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

/** Archives what each show's rules say, never the loaded episode or one in Up Next. */
async function archiveByRules(now: number) {
  const shows = (await listShows()).filter((s) => archivesByItself(s.settings))
  if (shows.length === 0) return
  const context = {
    now,
    loadedId: player.getView().episode?.id ?? null,
    queuedIds: new Set((await listUpNext()).map((item) => item.id)),
  }
  for (const show of shows) {
    try {
      const ids = episodesToArchive(
        await listEpisodes(show.id),
        show.settings,
        context,
      )
      await archiveEpisodes(ids)
    } catch (cause) {
      console.warn("Couldn't archive episodes automatically", cause)
    }
  }
}

async function deletePlayed(now: number, settings: AutomaticSettings) {
  if (!settings.deletePlayed) return
  const finished = (await listDownloads())
    .filter((info) => info.state === "downloaded")
    .map((info) => info.episodeId)
  const episodes = await listEpisodesByIds(finished)
  const ids = downloadsToDelete(
    episodes.map((episode) => ({
      id: episode.id,
      played: episode.played,
      lastPlayedAt: episode.lastPlayedAt,
    })),
    now,
    player.getView().episode?.id ?? null,
    settings,
  )
  for (const id of ids) {
    try {
      await deleteDownload(id)
    } catch (cause) {
      console.warn("Couldn't delete a played download", cause)
    }
  }
}

/**
 * Refreshes the feeds, starts the new downloads, queues new episodes where asked, deletes the
 * played downloads and archives by the shows' rules.
 */
export function runAutomatic(): Promise<void> {
  running ??= (async () => {
    try {
      const now = Date.now()
      const settings = await loadSettings()
      // First, so a show followed on the Mac is in the library when the feeds are read.
      await syncApplePodcasts()
      const { added } = await refreshAllShows()
      await syncShowSettings().catch((cause) =>
        console.warn("Couldn't save the show settings for the player", cause),
      )
      await startNew(added, settings)
      await queueNew(added)
      await deletePlayed(now, settings)
      await archiveByRules(now)
      await saveLastRun(now)
    } finally {
      running = null
    }
  })()
  return running
}

/**
 * The same, when the last run was 30 or more minutes ago. Otherwise only the Apple Podcasts
 * follow list is read, which is cheap, so a show followed on the Mac shows up on every open.
 */
export async function runIfDue(): Promise<void> {
  if (!refreshDue(await loadLastRun(), Date.now())) {
    await syncApplePodcasts()
    // In full at startup, so the player has every show's settings even on a quiet open.
    await syncShowSettings().catch((cause) =>
      console.warn("Couldn't save the show settings for the player", cause),
    )
    return
  }
  await runAutomatic()
}
