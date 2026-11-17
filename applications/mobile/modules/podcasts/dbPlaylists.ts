// LOFI-FORK: the podcasts section's playlists (see FORK.md).
//
// Reading and saving playlists, and the episodes a smart playlist's rules take. Not imported
// by any test, because op-sqlite is native; the SQL is in playlistSql.ts and playlistRules.ts.
import { notifyLibraryChanged } from "./changes"
import { database, rows } from "./db"
import { type StoredEpisode, episodeFromRow } from "./library"
import { playlistQuery, serializeRules } from "./playlistRules"
import {
  DELETE_PLAYLIST_SQL,
  LIST_PLAYLISTS_SQL,
  NEXT_POSITION_SQL,
  SAVE_PLAYLIST_SQL,
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
