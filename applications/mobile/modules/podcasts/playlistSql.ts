// LOFI-FORK: the podcasts section's playlists (see FORK.md).
//
// The SQL behind saving playlists, kept apart from db.ts so tests can run it on a real
// database.

export const LIST_PLAYLISTS_SQL =
  "SELECT * FROM playlists ORDER BY position, created_at, id"

/**
 * Saves a playlist, adding it or changing its title, rules, sort and auto-download. An
 * upsert, not a replace, because replacing a row would drop the rows that point at it.
 * Params: id, title, position, rules, sort, auto download (1 or 0), created at.
 */
export const SAVE_PLAYLIST_SQL = `INSERT INTO playlists (id, title, position, rules, sort, auto_download, created_at)
  VALUES (?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET title = excluded.title, rules = excluded.rules,
    sort = excluded.sort, auto_download = excluded.auto_download`

export const DELETE_PLAYLIST_SQL = "DELETE FROM playlists WHERE id = ?"

/** The place for a new playlist: after the last one. */
export const NEXT_POSITION_SQL =
  "SELECT COALESCE(MAX(position) + 1, 0) AS next FROM playlists"
