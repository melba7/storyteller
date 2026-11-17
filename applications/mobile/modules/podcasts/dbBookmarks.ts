// LOFI-FORK: the podcasts section's bookmarks (see FORK.md).
//
// Saving, listing, renaming and deleting bookmarks, and importing the ones the headphones
// made. Not imported by any test, because op-sqlite is native; the SQL is in bookmarkSql.ts
// and the rules in bookmarks.ts.
import { randomUUID } from "expo-crypto"

import {
  ADD_BOOKMARK_SQL,
  ALL_BOOKMARKS_SQL,
  DELETE_BOOKMARK_SQL,
  EPISODE_BOOKMARKS_SQL,
  RENAME_BOOKMARK_SQL,
} from "./bookmarkSql"
import {
  type Bookmark,
  bookmarkFromRow,
  bookmarkTitle,
  parsePending,
  pendingToBookmarks,
} from "./bookmarks"
import { notifyLibraryChanged } from "./changes"
import { database, listEpisodesByIds, rows } from "./db"
import { Podcasts } from "./index"

/** Saves a bookmark at this place in a library episode. `title` empty or missing: the time. */
export async function addBookmark(
  episodeId: string,
  positionSeconds: number,
  title?: string,
): Promise<Bookmark> {
  const bookmark: Bookmark = {
    id: randomUUID(),
    episodeId,
    positionSeconds: Math.max(0, positionSeconds),
    title: bookmarkTitle(title, positionSeconds),
    createdAt: Date.now(),
  }
  const db = await database()
  await db.execute(ADD_BOOKMARK_SQL, [
    bookmark.id,
    bookmark.episodeId,
    bookmark.positionSeconds,
    bookmark.title,
    bookmark.createdAt,
  ])
  notifyLibraryChanged()
  return bookmark
}

/** Changes a bookmark's title; an empty one goes back to the time. */
export async function renameBookmark(
  bookmark: Pick<Bookmark, "id" | "positionSeconds">,
  title: string,
): Promise<void> {
  const db = await database()
  await db.execute(RENAME_BOOKMARK_SQL, [
    bookmarkTitle(title, bookmark.positionSeconds),
    bookmark.id,
  ])
  notifyLibraryChanged()
}

export async function deleteBookmark(id: string): Promise<void> {
  const db = await database()
  await db.execute(DELETE_BOOKMARK_SQL, [id])
  notifyLibraryChanged()
}

export async function listEpisodeBookmarks(
  episodeId: string,
): Promise<Bookmark[]> {
  return (await rows(EPISODE_BOOKMARKS_SQL, [episodeId])).map(bookmarkFromRow)
}

/** Every bookmark, the newest first. */
export async function listAllBookmarks(): Promise<Bookmark[]> {
  return (await rows(ALL_BOOKMARKS_SQL)).map(bookmarkFromRow)
}

let importing: Promise<number> | null = null

/**
 * Saves the bookmarks the headphones made while JavaScript wasn't running, then takes them
 * out of Swift's file. They stay in the file until they are saved, so a failure loses none.
 * Returns how many were saved.
 */
export function importPendingBookmarks(): Promise<number> {
  importing ??= (async () => {
    try {
      if (Podcasts === null) return 0
      const pending = parsePending(await Podcasts.readPendingBookmarks())
      if (pending.length === 0) return 0
      const known = new Set(
        (
          await listEpisodesByIds([...new Set(pending.map((p) => p.episodeId))])
        ).map((episode) => episode.id),
      )
      const saved = pendingToBookmarks(pending, known)
      const db = await database()
      await db.transaction(async (tx) => {
        for (const bookmark of saved) {
          await tx.execute(ADD_BOOKMARK_SQL, [
            bookmark.id,
            bookmark.episodeId,
            bookmark.positionSeconds,
            bookmark.title,
            bookmark.createdAt,
          ])
        }
      })
      await Podcasts.removePendingBookmarks(pending.map((p) => p.id))
      if (saved.length > 0) notifyLibraryChanged()
      return saved.length
    } finally {
      importing = null
    }
  })()
  return importing
}
