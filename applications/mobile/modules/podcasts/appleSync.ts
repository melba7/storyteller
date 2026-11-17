// LOFI-FORK: the podcasts section's follow list from Apple Podcasts (see FORK.md).
//
// Reads `Podcasts/apple-podcasts.json` through the linked sounds folder, subscribes to the
// shows followed there that this phone has not seen, and marks the episodes finished there as
// played. The rules are in applePodcasts.ts. Nothing is downloaded for what it subscribes to:
// `subscribe` stores every episode of a new show directly, so none counts as newly added.
// Not imported by any test, because the database and the native modules are not there.
import AsyncStorage from "@react-native-async-storage/async-storage"

import { LofiScore } from "@/modules/lofi-score"

import {
  feedKey,
  parseAppleExport,
  parseSeen,
  planFollows,
  planPlayedOnce,
} from "./applePodcasts"
import { notifyLibraryChanged } from "./changes"
import { database, listShows } from "./db"
import { subscribe } from "./dbFeeds"
import { feedShows } from "./localFiles"

const FILE = "Podcasts/apple-podcasts.json"
const SEEN_KEY = "podcasts.apple.seen"
const APPLIED_KEY = "podcasts.apple.played"

async function readFile(): Promise<string | null> {
  try {
    return (await LofiScore?.readLinkedFolderFile(FILE)) ?? null
  } catch {
    return null
  }
}

async function markPlayed(showId: string, guids: string[]): Promise<number> {
  const db = await database()
  let changed = 0
  for (const guid of guids) {
    const result = await db.execute(
      "UPDATE episodes SET played = 1 WHERE show_id = ? AND guid = ? AND played = 0",
      [showId, guid],
    )
    changed += result.rowsAffected
  }
  return changed
}

let running: Promise<void> | null = null

/**
 * Follows what the Mac wrote. A missing file or folder is skipped quietly, a show that
 * can't be reached now is tried again next time, and nothing here throws.
 */
export function syncApplePodcasts(): Promise<void> {
  running ??= (async () => {
    try {
      const file = parseAppleExport(await readFile())
      if (file === null) return

      const seen = parseSeen(await AsyncStorage.getItem(SEEN_KEY))
      const plan = planFollows(
        file,
        seen,
        feedShows(await listShows()).map((show) => show.feedUrl),
      )
      const keys = new Set(plan.seen)
      for (const show of plan.subscribe) {
        try {
          await subscribe(show.feed)
          keys.add(feedKey(show.feed))
        } catch (cause) {
          console.warn("Couldn't follow a show from Apple Podcasts", cause)
        }
      }
      await AsyncStorage.setItem(SEEN_KEY, JSON.stringify([...keys]))

      // Each finished episode is marked once, so one marked unplayed here stays unplayed.
      const once = planPlayedOnce(
        file,
        await listShows(),
        parseSeen(await AsyncStorage.getItem(APPLIED_KEY)),
      )
      let changed = 0
      for (const { showId, guids } of once.plays) {
        changed += await markPlayed(showId, guids)
      }
      await AsyncStorage.setItem(APPLIED_KEY, JSON.stringify(once.applied))
      if (changed > 0) notifyLibraryChanged()
    } catch (cause) {
      console.warn("Couldn't read the Apple Podcasts follow list", cause)
    } finally {
      running = null
    }
  })()
  return running
}
