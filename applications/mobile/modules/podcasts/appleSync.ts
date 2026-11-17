// LOFI-FORK: the podcasts section's follow list from Apple Podcasts (see FORK.md).
//
// Reads `Podcasts/apple-podcasts.json` through the linked sounds folder, subscribes to the
// shows followed there that this phone has not seen, and marks the episodes finished there as
// played. The rules are in applePodcasts.ts. Nothing is downloaded for what it subscribes to:
// `subscribe` stores every episode of a new show directly, so none counts as newly added.
// A file iCloud has not put on the phone yet is asked for again a little later while the app
// is open, and what the last read found is kept for the screen (appleStatus.ts).
// Not imported by any test, because the database and the native modules are not there.
import { AppState } from "react-native"

import { LofiScore, type LinkedFileRead } from "@/modules/lofi-score"

import { withAppleLists } from "./appleLists"
import {
  APPLIED_KEY,
  PENDING_KEY,
  SEEN_KEY,
  loadFailures,
  loadList,
  saveFailures,
  saveList,
} from "./appleMemory"
import {
  appliedKey,
  dueShows,
  feedKey,
  parseAppleExport,
  planFollows,
  planPlayedOnce,
  withLibraryFeeds,
} from "./applePodcasts"
import { problemFor, retryDelay, setAppleSyncStatus } from "./appleStatus"
import { notifyLibraryChanged } from "./changes"
import { database, listShows, rows } from "./db"
import { subscribe } from "./dbFeeds"
import { MARK_PLAYED_FROM_APPLE_SQL } from "./episodeSql"
import { feedShows } from "./localFiles"
import { readableError } from "./nativeError"

const FILE = "Podcasts/apple-podcasts.json"

async function readFile(): Promise<LinkedFileRead> {
  try {
    return (
      (await LofiScore?.readLinkedFolderFileStatus(FILE)) ?? {
        status: "unreadable",
        message: "Needs the iOS app",
      }
    )
  } catch (cause) {
    return { status: "unreadable", message: readableError(cause) }
  }
}

/** The (feed key, guid) of every episode the phone has for the shows the file marks finished. */
async function episodesOnPhone(
  library: Awaited<ReturnType<typeof listShows>>,
  finishedFeeds: Set<string>,
): Promise<Set<string>> {
  const have = new Set<string>()
  for (const show of feedShows(library)) {
    if (!finishedFeeds.has(feedKey(show.feedUrl))) continue
    for (const row of await rows(
      "SELECT guid FROM episodes WHERE show_id = ?",
      [show.id],
    )) {
      have.add(appliedKey(show.feedUrl, String(row["guid"])))
    }
  }
  return have
}

/** Marks the guids played; returns how many episodes changed. */
async function markPlayed(showId: string, guids: string[]): Promise<number> {
  const db = await database()
  const now = Date.now()
  let changed = 0
  for (const guid of guids) {
    const result = await db.execute(MARK_PLAYED_FROM_APPLE_SQL, [
      now,
      showId,
      guid,
    ])
    changed += result.rowsAffected
  }
  return changed
}

let running: Promise<void> | null = null
let retries = 0
let retryTimer: ReturnType<typeof setTimeout> | undefined

/** iCloud is still downloading the file: asks again a few times while the app is open. */
function askAgainLater() {
  const delay = retryDelay(retries)
  if (delay === null) return
  retries += 1
  clearTimeout(retryTimer)
  retryTimer = setTimeout(() => {
    if (AppState.currentState === "active") void syncApplePodcasts()
  }, delay)
}

async function syncOnce(): Promise<void> {
  const read = await readFile()
  if (read.status === "notDownloaded") askAgainLater()
  else {
    retries = 0
    clearTimeout(retryTimer)
  }
  if (read.status !== "found") {
    setAppleSyncStatus({ reading: false, problem: problemFor(read) })
    return
  }
  const file = parseAppleExport(read.text)
  if (file === null) {
    setAppleSyncStatus({
      reading: false,
      problem: "The file is not one this app can read",
    })
    return
  }

  const seen = await loadList(SEEN_KEY)
  const library = await listShows()
  const plan = planFollows(
    file,
    seen,
    feedShows(library).map((show) => show.feedUrl),
    feedShows(library).map((show) => show.title),
  )
  const keys = new Set(plan.seen)
  const failures = await loadFailures()
  const now = Date.now()
  let followed = 0
  // A show that failed is tried again after a day, not at every open.
  for (const show of dueShows(plan.subscribe, failures, now)) {
    try {
      await subscribe(show.feed)
      keys.add(feedKey(show.feed))
      delete failures[feedKey(show.feed)]
      followed += 1
    } catch (cause) {
      failures[feedKey(show.feed)] = now
      console.warn("Couldn't follow a show from Apple Podcasts", cause)
    }
  }
  await saveList(SEEN_KEY, [...keys])
  await saveFailures(failures)

  // Each finished episode is marked once, so one marked unplayed here stays unplayed. One the
  // phone does not have yet waits (pending) and is marked when the feed brings it.
  const shows = await listShows()
  // A show the library has under another address is found by its title.
  const finished = withLibraryFeeds(file, shows)
  const have = await episodesOnPhone(
    shows,
    new Set(finished.finished.map((item) => feedKey(item.feed))),
  )
  // The lists are read and written beside refreshes settling arrived episodes: one at a time.
  const changed = await withAppleLists(async () => {
    const once = planPlayedOnce(
      finished,
      shows,
      await loadList(APPLIED_KEY),
      (feed, guid) => have.has(appliedKey(feed, guid)),
    )
    let marked = 0
    for (const { showId, guids } of once.plays) {
      marked += await markPlayed(showId, guids)
    }
    await saveList(APPLIED_KEY, once.applied)
    await saveList(PENDING_KEY, once.pending)
    return marked
  })
  if (changed > 0 || followed > 0) notifyLibraryChanged()
  setAppleSyncStatus({
    reading: false,
    readAt: Date.now(),
    shows: file.shows.length,
    followed,
    problem: null,
  })
}

/**
 * Follows what the Mac wrote. A missing file or folder is skipped quietly (and shown in the
 * status), a show that can't be reached now is tried again tomorrow, and nothing here throws.
 */
export function syncApplePodcasts(): Promise<void> {
  running ??= (async () => {
    setAppleSyncStatus({ reading: true })
    try {
      await syncOnce()
    } catch (cause) {
      console.warn("Couldn't read the Apple Podcasts follow list", cause)
      setAppleSyncStatus({ reading: false, problem: readableError(cause) })
    } finally {
      running = null
    }
  })()
  return running
}

/** The read, but the caller waits for it no more than 30 seconds (it carries on by itself). */
export async function syncApplePodcastsBriefly(): Promise<void> {
  let timer: ReturnType<typeof setTimeout> | undefined
  await Promise.race([
    syncApplePodcasts(),
    new Promise<void>((resolve) => {
      timer = setTimeout(resolve, 30_000)
    }),
  ])
  clearTimeout(timer)
}
