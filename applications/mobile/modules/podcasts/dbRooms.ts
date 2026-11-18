// LOFI-FORK: the podcasts section's Library rooms (see FORK.md).
//
// Reads for Library's "Latest Episodes" and "Recently Updated". Not imported by any test,
// because op-sqlite is native; the SQL is in roomsSql.ts and tested there.
import { rows } from "./db"
import { type StoredEpisode, episodeFromRow } from "./library"
import { type RecentShow, recentShowsFromRows } from "./rooms"
import { LATEST_SQL, RECENT_SHOWS_SQL } from "./roomsSql"

/** The newest episodes of the followed shows, not archived, newest first. */
export async function listLatest(): Promise<StoredEpisode[]> {
  return (await rows(LATEST_SQL)).map(episodeFromRow)
}

/** The followed shows with their newest episode's date, the most recently updated first. */
export async function listRecentShows(): Promise<RecentShow[]> {
  return recentShowsFromRows(await rows(RECENT_SHOWS_SQL))
}
