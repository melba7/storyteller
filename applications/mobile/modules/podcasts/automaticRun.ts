import { syncApplePodcastsBriefly } from "./appleSync"
import { archivesByItself, episodesToArchive } from "./archive"
// LOFI-FORK: the podcasts section's automatic downloads and clean-up (see FORK.md).
//
// What the app does by itself when it comes to the front and in the background task: follow
// what the Mac wrote from Apple Podcasts (appleSync.ts), have the phone look at Up Next and
// fetch the next two episodes ahead (on Wi-Fi), read every feed, download each show's
// newest new episode (always on Wi-Fi), download the first episodes of the playlists that
// ask for it, put new episodes in Up Next where a show says so,
// delete played downloads after a day and archive what each show's rules say. The rules are
// in automatic.ts and archive.ts. Not imported by any test, because the database and the
// native module are not there.
import {
  type AutomaticSettings,
  EXCHANGE_WAIT_MS,
  downloadsToDelete,
  episodesForUpNext,
  episodesToDownload,
  mergeFollowUps,
  refreshDue,
  waitAtMost,
} from "./automatic"
import {
  loadFollowUps,
  loadLastRun,
  loadSettings,
  saveFollowUps,
  saveLastRun,
} from "./automaticSettings"
import { withoutHeld } from "./coming"
import { heldEpisodeIds } from "./comingRun"
import { getShow, listEpisodes, listEpisodesByIds, listShows } from "./db"
import { importPendingBookmarks } from "./dbBookmarks"
import { refreshAllShows } from "./dbFeeds"
import { listPlaylists, smartEpisodes } from "./dbPlaylists"
import { archiveEpisodes, syncShowSettings } from "./dbSettings"
import {
  deleteDownload,
  listDownloads,
  lookAhead,
  startDownload,
} from "./downloadsNative"
import { notifyAboutNewEpisodes } from "./newEpisodeNotify"
import { player } from "./playerInstance"
import { filterDownloaded, playlistDownloads } from "./playlistRules"
import { runTeachingSync, teachingSyncDone } from "./teachingRun"
import { listUpNext, queueEpisode } from "./upNextNative"

let running: Promise<void> | null = null

type Added = Awaited<ReturnType<typeof refreshAllShows>>["added"]

async function startNew(added: Added, settings: AutomaticSettings) {
  const shows = await listShows()
  const downloads = new Map(shows.map((s) => [s.id, s.settings.autoDownload]))
  // A show unfollowed during or after the refresh is not in the list: nothing of it downloads.
  const followed = added.filter((episode) => downloads.has(episode.showId))
  // The Mac's copy of an episode it is preparing is awaited, not downloaded here (coming.ts).
  const wanted = withoutHeld(
    episodesToDownload(followed, settings, downloads),
    await heldEpisodeIds(),
  )
  for (const episode of wanted) {
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
}

/**
 * Downloads the first few episodes of each playlist that asks for it, on Wi-Fi only. What
 * is already on the phone, on its way or failed is left alone.
 */
async function downloadForPlaylists(now: number, settings: AutomaticSettings) {
  const playlists = (await listPlaylists()).filter(
    (p) => p.kind === "smart" && p.autoDownload,
  )
  if (playlists.length === 0) return
  const infos = await listDownloads()
  // With "delete played downloads" on, a played episode would be fetched and deleted again.
  const skipPlayed = settings.deletePlayed
  const known = new Set(infos.map((info) => info.episodeId))
  const onPhone = new Set(
    infos.filter((info) => info.state === "downloaded").map((i) => i.episodeId),
  )
  const matches = new Map<string, Awaited<ReturnType<typeof smartEpisodes>>>()
  for (const playlist of playlists) {
    matches.set(
      playlist.id,
      filterDownloaded(
        await smartEpisodes(playlist, now),
        playlist.rules,
        onPhone,
      ),
    )
  }
  const languages = new Map((await listShows()).map((s) => [s.id, s.language]))
  for (const episode of withoutHeld(
    playlistDownloads(playlists, matches, known, skipPlayed),
    await heldEpisodeIds(),
  )) {
    try {
      await startDownload(
        episode.id,
        episode.audioUrl,
        episode.audioType,
        true,
        languages.get(episode.showId) ?? null,
        episode.showId,
      )
    } catch (cause) {
      console.warn("Couldn't start a playlist download", cause)
    }
  }
}

/**
 * Has the phone look at Up Next and fetch the next episodes ahead, which it does only on Wi-Fi.
 * An episode queued away from home is fetched this way once the app opens or the background
 * refresh runs at home (the phone itself looks when Wi-Fi returns while the app is running). A
 * failure is logged, not thrown.
 */
async function lookAheadInUpNext() {
  await heldEpisodeIds()
    .then((held) => lookAhead([...held]))
    .catch((cause: unknown) =>
      console.warn("Couldn't look ahead in Up Next", cause),
    )
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

/**
 * What happens for episodes a refresh just added: the newest downloads by itself where the
 * show says so, they go in Up Next where it says so, and the listener is told. The automatic
 * run and a pull-to-refresh both end here. A failure is logged, not thrown.
 */
export async function followUpNew(
  added: Added,
  settings?: AutomaticSettings,
): Promise<void> {
  if (added.length === 0) return
  try {
    await startNew(added, settings ?? (await loadSettings()))
    await queueNew(added)
    await notifyAboutNewEpisodes(added)
  } catch (cause) {
    console.warn("Couldn't act on the new episodes", cause)
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
    new Set((await listUpNext()).map((item) => item.id)),
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
      // First, before the feeds: the background task's time may run out in them, and a download
      // that has started carries on after it.
      await lookAheadInUpNext()
      // The headphones' bookmarks, which the background task may be the first to see.
      await importPendingBookmarks().catch((cause) =>
        console.warn("Couldn't import the headphone bookmarks", cause),
      )
      // First, so a show followed on the Mac is in the library when the feeds are read, but
      // the feeds do not wait more than 30 seconds for it.
      await syncApplePodcastsBriefly()
      // The Mac's teaching files come in and the phone's notes go out, in the background.
      runTeachingSync()
      // The new episodes are kept as each show is read, so a run that is cut short (the
      // background task's time ran out) still follows them up next time.
      let todo = await loadFollowUps()
      await refreshAllShows({
        appleSync: false,
        onAdded: async (batch) => {
          todo = mergeFollowUps(todo, batch)
          await saveFollowUps(todo)
        },
      })
      await syncShowSettings().catch((cause) =>
        console.warn("Couldn't save the show settings for the player", cause),
      )
      await followUpNew(todo, settings)
      await saveFollowUps([])
      await downloadForPlaylists(now, settings).catch((cause) =>
        console.warn("Couldn't download for the playlists", cause),
      )
      await deletePlayed(now, settings)
      await archiveByRules(now)
      await saveLastRun(now)
      // The exchange with the Mac was started without waiting: the background task is not ended
      // in the middle of it, but is not held for more than a short while either.
      await waitAtMost(teachingSyncDone(), EXCHANGE_WAIT_MS)
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
    await lookAheadInUpNext()
    await syncApplePodcastsBriefly()
    runTeachingSync()
    // In full at startup, so the player has every show's settings even on a quiet open.
    await syncShowSettings().catch((cause) =>
      console.warn("Couldn't save the show settings for the player", cause),
    )
    return
  }
  await runAutomatic()
}
