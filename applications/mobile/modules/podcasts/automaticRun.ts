import { syncApplePodcasts } from "./appleSync"
// LOFI-FORK: the podcasts section's automatic downloads and clean-up (see FORK.md).
//
// What the app does by itself when it comes to the front and in the background task: follow
// what the Mac wrote from Apple Podcasts (appleSync.ts), read every feed, download each show's
// newest new episode (always on Wi-Fi) and delete played downloads after a day. The rules are in automatic.ts. Not imported by any test, because the
// database and the native module are not there.
import {
  type AutomaticSettings,
  downloadsToDelete,
  episodesToDownload,
  refreshDue,
} from "./automatic"
import { loadLastRun, loadSettings, saveLastRun } from "./automaticSettings"
import { listEpisodesByIds } from "./db"
import { refreshAllShows } from "./dbFeeds"
import { deleteDownload, listDownloads, startDownload } from "./downloadsNative"
import { player } from "./playerInstance"

let running: Promise<void> | null = null

async function startNew(
  added: Awaited<ReturnType<typeof refreshAllShows>>["added"],
  settings: AutomaticSettings,
) {
  for (const episode of episodesToDownload(added, settings)) {
    try {
      await startDownload(episode.id, episode.audioUrl, episode.audioType, true)
    } catch (cause) {
      console.warn("Couldn't start an automatic download", cause)
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

/** Refreshes the feeds, starts the new downloads and deletes the played ones. */
export function runAutomatic(): Promise<void> {
  running ??= (async () => {
    try {
      const now = Date.now()
      const settings = await loadSettings()
      // First, so a show followed on the Mac is in the library when the feeds are read.
      await syncApplePodcasts()
      const { added } = await refreshAllShows()
      await startNew(added, settings)
      await deletePlayed(now, settings)
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
    return
  }
  await runAutomatic()
}
