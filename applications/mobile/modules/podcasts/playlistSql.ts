// LOFI-FORK: the podcasts section's playlists (see FORK.md).
//
// The SQL behind saving playlists, kept apart from db.ts so tests can run it on a real
// database.

export const LIST_PLAYLISTS_SQL =
  "SELECT * FROM playlists ORDER BY position, created_at, id"

/**
 * Saves a playlist, adding it or changing its title, rules, sort and auto-download. An
 * upsert, not a replace, because replacing a row would drop the rows that point at it.
 * Params: id, title, position, rules, sort, auto download (1 or 0), created at, kind
 * ("smart" or "manual"; a playlist keeps the kind it was made with).
 */
export const SAVE_PLAYLIST_SQL = `INSERT INTO playlists (id, title, position, rules, sort, auto_download, created_at, kind)
  VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET title = excluded.title, rules = excluded.rules,
    sort = excluded.sort, auto_download = excluded.auto_download`

export const DELETE_PLAYLIST_SQL = "DELETE FROM playlists WHERE id = ?"

/** The place for a new playlist: after the last one. */
export const NEXT_POSITION_SQL =
  "SELECT COALESCE(MAX(position) + 1, 0) AS next FROM playlists"

// MARK: Hand-filled playlists

/**
 * Puts an episode at the end of a playlist; one already in it stays where it is. Params:
 * playlist id, episode id, playlist id, snapshot (see manualPlaylist.ts), added at.
 */
export const ADD_ITEM_SQL = `INSERT INTO playlist_items (playlist_id, episode_id, position, snapshot, added_at)
  VALUES (?, ?, (SELECT COALESCE(MAX(position) + 1, 0) FROM playlist_items WHERE playlist_id = ?), ?, ?)
  ON CONFLICT(playlist_id, episode_id) DO NOTHING`

/** Params: playlist id, episode id. */
export const REMOVE_ITEM_SQL =
  "DELETE FROM playlist_items WHERE playlist_id = ? AND episode_id = ?"

/** Params: position, playlist id, episode id. */
export const SET_ITEM_POSITION_SQL =
  "UPDATE playlist_items SET position = ? WHERE playlist_id = ? AND episode_id = ?"

/** A playlist's items in order. Param: playlist id. */
export const LIST_ITEMS_SQL =
  "SELECT episode_id, snapshot FROM playlist_items WHERE playlist_id = ? ORDER BY position, added_at, episode_id"

/** The ids of the hand-filled playlists holding an episode. Param: episode id. */
export const PLAYLISTS_WITH_SQL =
  "SELECT playlist_id FROM playlist_items WHERE episode_id = ?"

/** How many items each playlist holds. */
export const ITEM_COUNTS_SQL =
  "SELECT playlist_id, COUNT(*) AS items FROM playlist_items GROUP BY playlist_id"
