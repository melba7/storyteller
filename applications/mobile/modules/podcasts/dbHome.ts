// LOFI-FORK: the podcasts section's Home (see FORK.md).
//
// Reads for Home. Not imported by any test, because op-sqlite is native; the SQL is in
// homeSql.ts and tested there, the order in home.ts.
import { rows } from "./db"
import { type ShelfEntry, orderUpNextShelf } from "./home"
import { SHOW_PLAYS_SQL, UP_NEXT_CANDIDATES_SQL } from "./homeSql"
import { episodeFromRow } from "./library"

/** Home's Up Next shelf, in order. */
export async function listUpNextShelf(): Promise<ShelfEntry[]> {
  const found = await rows(UP_NEXT_CANDIDATES_SQL)
  return orderUpNextShelf(found.map(episodeFromRow))
}

/** When each show was last listened to (show id to milliseconds), from the history. */
export async function listShowPlays(): Promise<Map<string, number>> {
  const plays = new Map<string, number>()
  for (const row of await rows(SHOW_PLAYS_SQL)) {
    const at = row["last_at"]
    if (typeof row["show_id"] === "string" && typeof at === "number") {
      plays.set(row["show_id"], at)
    }
  }
  return plays
}
