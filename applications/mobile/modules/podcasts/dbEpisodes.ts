// LOFI-FORK: the podcasts section's episode actions (see FORK.md).
//
// Starring, marking played and the listening history. Not imported by any test, because
// op-sqlite is native; the SQL is in episodeSql.ts and tested there.
import { notifyLibraryChanged } from "./changes"
import { database, rows } from "./db"
import {
  CLEAR_HISTORY_SQL,
  HISTORY_SQL,
  SET_PLAYED_SQL,
  SET_STARRED_SQL,
  STAR_ORDER_SQL,
} from "./episodeSql"
import { type StoredEpisode, episodeFromRow } from "./library"

/** Stars or unstars episodes, all in one transaction. */
export async function setStarred(
  ids: readonly string[],
  starred: boolean,
): Promise<void> {
  if (ids.length === 0) return
  const db = await database()
  const at = Date.now()
  await db.transaction(async (tx) => {
    for (const id of ids) {
      await tx.execute(SET_STARRED_SQL, [starred ? at : null, id])
    }
  })
  notifyLibraryChanged()
}

/** Marks episodes played (keeping their place) or unplayed (forgetting it). */
export async function setPlayed(
  ids: readonly string[],
  played: boolean,
): Promise<void> {
  if (ids.length === 0) return
  const db = await database()
  const flag = played ? 1 : 0
  await db.transaction(async (tx) => {
    for (const id of ids)
      await tx.execute(SET_PLAYED_SQL, [flag, flag, flag, Date.now(), id])
  })
  notifyLibraryChanged()
}

/** The starred episodes, the one starred last first. */
export async function listStarred(): Promise<StoredEpisode[]> {
  return (await rows(STAR_ORDER_SQL)).map(episodeFromRow)
}

/** The episodes listened to, the most recent first. */
export async function listHistory(): Promise<StoredEpisode[]> {
  return (await rows(HISTORY_SQL)).map(episodeFromRow)
}

/** Empties the listening history. Places and played marks stay. */
export async function clearHistory(): Promise<void> {
  const db = await database()
  await db.execute(CLEAR_HISTORY_SQL)
  notifyLibraryChanged()
}
