// LOFI-FORK: the podcasts section's library file (see FORK.md).
//
// Shows and episodes live in their own SQLite file, `podcasts.db`, next to the books'
// database. Storyteller's own database, its migrations and its store are not touched.
// Not imported by any test, because op-sqlite is native.
import {
  ANDROID_DATABASE_PATH,
  type DB,
  IOS_DOCUMENT_PATH,
  open,
} from "@op-engineering/op-sqlite"
import { Platform } from "react-native"

import { rememberUnsubscribed } from "./appleMemory"
import { notifyLibraryChanged } from "./changes"
import { deleteDownloads } from "./downloadsNative"
import { RECORD_LISTEN_SQL } from "./episodeSql"
import {
  type Show,
  type StoredEpisode,
  episodeFromRow,
  showFromRow,
  sortEpisodes,
} from "./library"
import { type ActivityByShow } from "./libraryView"
import { migrationStatements } from "./schema"
import { type EpisodeHit, hitFromRow, localSearchQuery } from "./search"
import { removeManyFromUpNext } from "./upNextNative"

let opened: Promise<DB> | null = null

/** Opens the file the first time it is needed and creates or upgrades its tables. */
export function database(): Promise<DB> {
  opened ??= (async () => {
    const db = open({
      name: "podcasts.db",
      location:
        Platform.OS === "android"
          ? ANDROID_DATABASE_PATH
          : `${IOS_DOCUMENT_PATH}/SQLite`,
    })
    await db.execute("PRAGMA foreign_keys = ON")
    const result = await db.execute("PRAGMA user_version")
    const version = Number(result.rows[0]?.["user_version"] ?? 0)
    const statements = migrationStatements(version)
    if (statements.length > 0) {
      await db.transaction(async (tx) => {
        for (const statement of statements) await tx.execute(statement)
      })
    }
    return db
  })()
  // A failed open is tried again next time.
  opened.catch(() => {
    opened = null
  })
  return opened
}

export async function rows(sql: string, params: (string | number)[] = []) {
  const db = await database()
  return (await db.execute(sql, params)).rows
}

// MARK: Reading

export async function listShows(): Promise<Show[]> {
  const found = await rows("SELECT * FROM shows ORDER BY title COLLATE NOCASE")
  return found.map(showFromRow)
}

/**
 * Per show: when its newest dated episode came out, whether that episode is played, and how
 * many unplayed, unarchived episodes came out at or after the show was followed. Episodes with no date
 * never count as newer. One query for the whole library, for ordering and badges.
 */
export async function listShowActivity(): Promise<ActivityByShow> {
  const found = await rows(
    `SELECT s.id AS show_id,
       MAX(e.published_at) AS newest_at,
       (SELECT n.played FROM episodes n
         WHERE n.show_id = s.id AND n.published_at IS NOT NULL
         ORDER BY n.published_at DESC LIMIT 1) AS newest_played,
       COUNT(CASE WHEN e.played = 0 AND e.archived = 0
         AND e.published_at >= s.added_at THEN 1 END)
         AS unplayed_since
     FROM shows s LEFT JOIN episodes e ON e.show_id = s.id
     GROUP BY s.id`,
  )
  const activity: ActivityByShow = {}
  for (const row of found) {
    const newest = row["newest_at"]
    activity[String(row["show_id"])] = {
      newestAt: typeof newest === "number" ? newest : null,
      newestPlayed: row["newest_played"] !== 0,
      unplayedSince: Number(row["unplayed_since"] ?? 0),
    }
  }
  return activity
}

/** Keeps "Your order": the shows' places, 0 for the first, saved in one transaction. */
export async function saveOwnOrder(ids: string[]): Promise<void> {
  const db = await database()
  await db.transaction(async (tx) => {
    for (const [position, id] of ids.entries()) {
      await tx.execute("UPDATE shows SET own_position = ? WHERE id = ?", [
        position,
        id,
      ])
    }
  })
  notifyLibraryChanged()
}

export async function getShow(id: string): Promise<Show | null> {
  const found = await rows("SELECT * FROM shows WHERE id = ?", [id])
  return found[0] ? showFromRow(found[0]) : null
}

/** A show's episodes, newest first. */
export async function listEpisodes(showId: string): Promise<StoredEpisode[]> {
  const found = await rows("SELECT * FROM episodes WHERE show_id = ?", [showId])
  return sortEpisodes(found.map(episodeFromRow))
}

/** The episodes with these ids that are in the library. Ids the library lacks are left out. */
export async function listEpisodesByIds(
  ids: readonly string[],
): Promise<StoredEpisode[]> {
  if (ids.length === 0) return []
  const marks = ids.map(() => "?").join(", ")
  const found = await rows(`SELECT * FROM episodes WHERE id IN (${marks})`, [
    ...ids,
  ])
  return found.map(episodeFromRow)
}

export async function getEpisode(id: string): Promise<StoredEpisode | null> {
  const found = await rows("SELECT * FROM episodes WHERE id = ?", [id])
  return found[0] ? episodeFromRow(found[0]) : null
}

/** Episodes of followed shows with every word in the title or notes (see search.ts). */
export async function searchEpisodes(input: string): Promise<EpisodeHit[]> {
  const query = localSearchQuery(input)
  if (!query) return []
  return (await rows(query.sql, query.params)).map(hitFromRow)
}

// MARK: Playing

/**
 * Keeps where the listener is in an episode, and whether it counts as played. `notify` is
 * false for a save that no list could show yet, so the open screens do not read again.
 */
export async function savePlayback(
  episodeId: string,
  position: number,
  played: boolean,
  notify = true,
): Promise<void> {
  const db = await database()
  const now = Date.now()
  await db.execute(RECORD_LISTEN_SQL, [
    Math.max(0, position),
    played ? 1 : 0,
    now,
    now,
    episodeId,
  ])
  if (notify) notifyLibraryChanged()
}

/** The episode played most recently, for the mini player after the app restarts. */
export async function lastPlayedEpisode(): Promise<StoredEpisode | null> {
  const found = await rows(
    "SELECT * FROM episodes WHERE last_played_at IS NOT NULL ORDER BY last_played_at DESC LIMIT 1",
  )
  return found[0] ? episodeFromRow(found[0]) : null
}

/** Keeps the main colour of a show's artwork, worked out once by the player. */
export async function saveArtworkColor(
  showId: string,
  color: string,
): Promise<void> {
  const db = await database()
  await db.execute("UPDATE shows SET artwork_color = ? WHERE id = ?", [
    color,
    showId,
  ])
  notifyLibraryChanged()
}

/**
 * Removes the show and its episodes from the library, and the episodes' downloads and
 * places in Up Next. The
 * downloads go first: if one can't be removed the show stays, so no file is left behind
 * that nothing points to.
 */
export async function unsubscribe(id: string): Promise<void> {
  const db = await database()
  const show = await getShow(id)
  const found = await rows("SELECT id FROM episodes WHERE show_id = ?", [id])
  const ids = found.map((row) => String(row["id"]))
  await deleteDownloads(ids)
  await removeManyFromUpNext(ids)
  await db.transaction(async (tx) => {
    await tx.execute("DELETE FROM episodes WHERE show_id = ?", [id])
    await tx.execute("DELETE FROM shows WHERE id = ?", [id])
  })
  // The Apple Podcasts list never adds a show the listener dropped.
  if (show) await rememberUnsubscribed(show.feedUrl, show.title)
  notifyLibraryChanged()
}
