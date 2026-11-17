// LOFI-FORK: the podcasts section's playlists (see FORK.md).
//
// Reading and saving playlists, and the episodes a smart playlist's rules take. Not imported
// by any test, because op-sqlite is native; the SQL is in playlistSql.ts and playlistRules.ts.
import { notifyLibraryChanged } from "./changes"
import { database, listEpisodesByIds, listShows, rows } from "./db"
import { type Show, type StoredEpisode, episodeFromRow } from "./library"
import { type PlaylistEntry, resolveItems, snapshotOf } from "./manualPlaylist"
import { playlistQuery, serializeRules } from "./playlistRules"
import {
  ADD_ITEM_SQL,
  DELETE_PLAYLIST_SQL,
  ITEM_COUNTS_SQL,
  LIST_ITEMS_SQL,
  LIST_PLAYLISTS_SQL,
  NEXT_POSITION_SQL,
  PLAYLISTS_WITH_SQL,
  REMOVE_ITEM_SQL,
  SAVE_PLAYLIST_SQL,
  SET_ITEM_POSITION_SQL,
} from "./playlistSql"
import { type Playlist, playlistFromRow } from "./playlists"

export async function listPlaylists(): Promise<Playlist[]> {
  return (await rows(LIST_PLAYLISTS_SQL)).map(playlistFromRow)
}

export async function getPlaylist(id: string): Promise<Playlist | null> {
  return (await listPlaylists()).find((playlist) => playlist.id === id) ?? null
}

/** The place for a new playlist: after the last one. */
export async function nextPlaylistPosition(): Promise<number> {
  return Number((await rows(NEXT_POSITION_SQL))[0]?.["next"] ?? 0)
}

/** Adds a playlist, or changes its title, rules, sort and auto-download. */
export async function savePlaylist(playlist: Playlist): Promise<void> {
  const db = await database()
  await db.execute(SAVE_PLAYLIST_SQL, [
    playlist.id,
    playlist.title,
    playlist.position,
    serializeRules(playlist.rules),
    playlist.sort,
    playlist.autoDownload ? 1 : 0,
    playlist.createdAt,
    playlist.kind,
  ])
  notifyLibraryChanged()
}

export async function deletePlaylist(id: string): Promise<void> {
  const db = await database()
  await db.execute(DELETE_PLAYLIST_SQL, [id])
  notifyLibraryChanged()
}

/**
 * The episodes a smart playlist's rules take, in its order. The "downloaded" rule is not
 * applied here (the database doesn't know): see filterDownloaded.
 */
export async function smartEpisodes(
  playlist: Pick<Playlist, "rules" | "sort">,
  now: number = Date.now(),
): Promise<StoredEpisode[]> {
  const { sql, params } = playlistQuery(playlist.rules, playlist.sort, now)
  return (await rows(sql, params)).map(episodeFromRow)
}

// MARK: Hand-filled playlists

/** Puts an episode at the end of a playlist (nothing happens when it is already in it). */
export async function addToPlaylist(
  playlistId: string,
  episode: StoredEpisode,
  show: Show | null,
): Promise<void> {
  const db = await database()
  await db.execute(ADD_ITEM_SQL, [
    playlistId,
    episode.id,
    playlistId,
    snapshotOf(episode, show),
    Date.now(),
  ])
  notifyLibraryChanged()
}

export async function removeFromPlaylist(
  playlistId: string,
  episodeId: string,
): Promise<void> {
  const db = await database()
  await db.execute(REMOVE_ITEM_SQL, [playlistId, episodeId])
  notifyLibraryChanged()
}

/** Keeps the order of a playlist's items: the ids in their new order. */
export async function saveItemOrder(
  playlistId: string,
  ids: readonly string[],
): Promise<void> {
  const db = await database()
  await db.transaction(async (tx) => {
    for (const [position, id] of ids.entries()) {
      await tx.execute(SET_ITEM_POSITION_SQL, [position, playlistId, id])
    }
  })
  notifyLibraryChanged()
}

/** A hand-filled playlist's episodes in order, ready to show and play. */
export async function listEntries(
  playlistId: string,
): Promise<PlaylistEntry[]> {
  const items = (await rows(LIST_ITEMS_SQL, [playlistId])).map((row) => ({
    episodeId: String(row["episode_id"] ?? ""),
    snapshot: String(row["snapshot"] ?? ""),
  }))
  const live = new Map(
    (await listEpisodesByIds(items.map((item) => item.episodeId))).map((e) => [
      e.id,
      e,
    ]),
  )
  const shows = new Map((await listShows()).map((show) => [show.id, show]))
  return resolveItems(items, live, shows)
}

/** The ids of the playlists that hold this episode. */
export async function playlistsHolding(
  episodeId: string,
): Promise<Set<string>> {
  return new Set(
    (await rows(PLAYLISTS_WITH_SQL, [episodeId])).map((row) =>
      String(row["playlist_id"]),
    ),
  )
}

/** How many items each hand-filled playlist holds, by playlist id. */
export async function itemCounts(): Promise<Map<string, number>> {
  return new Map(
    (await rows(ITEM_COUNTS_SQL)).map((row) => [
      String(row["playlist_id"]),
      Number(row["items"] ?? 0),
    ]),
  )
}
