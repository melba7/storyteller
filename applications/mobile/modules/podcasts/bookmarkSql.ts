// LOFI-FORK: the podcasts section's bookmarks (see FORK.md).
//
// The SQL behind bookmarks, kept apart from db.ts so tests can run it on a real database.

/**
 * Saves a bookmark; one with an id that is saved already is left alone, so importing the
 * headphones' bookmarks twice saves them once. Params: id, episode id, place in seconds,
 * title, created at.
 */
export const ADD_BOOKMARK_SQL =
  "INSERT OR IGNORE INTO bookmarks (id, episode_id, position_seconds, title, created_at) VALUES (?, ?, ?, ?, ?)"

/** Params: title, id. */
export const RENAME_BOOKMARK_SQL = "UPDATE bookmarks SET title = ? WHERE id = ?"

export const DELETE_BOOKMARK_SQL = "DELETE FROM bookmarks WHERE id = ?"

/** One episode's bookmarks, in the order of the episode. Param: episode id. */
export const EPISODE_BOOKMARKS_SQL =
  "SELECT * FROM bookmarks WHERE episode_id = ? ORDER BY position_seconds, created_at, id"

/** Every bookmark, the newest first. */
export const ALL_BOOKMARKS_SQL =
  "SELECT * FROM bookmarks ORDER BY created_at DESC, id"
