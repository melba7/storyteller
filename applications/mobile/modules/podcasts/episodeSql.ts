// LOFI-FORK: the podcasts section's episode actions (see FORK.md).
//
// The SQL behind starring, marking played and the listening history, kept apart from db.ts
// (which needs the native SQLite module) so tests can run it against a real database.

/** Params: when it was starred (null to unstar), episode id. */
export const SET_STARRED_SQL = "UPDATE episodes SET starred_at = ? WHERE id = ?"

/** The starred episodes, the one starred last first. */
export const STAR_ORDER_SQL =
  "SELECT * FROM episodes WHERE starred_at IS NOT NULL ORDER BY starred_at DESC"

/**
 * Params: played (1 or 0), the same again, episode id. Marking played keeps the place;
 * marking unplayed forgets it.
 */
export const SET_PLAYED_SQL =
  "UPDATE episodes SET played = ?, position_seconds = CASE WHEN ? = 1 THEN position_seconds ELSE 0 END WHERE id = ?"

/**
 * Saves where the listener is and when they listened. Params: place, played (1 or 0),
 * last played time, history time, episode id.
 */
export const RECORD_LISTEN_SQL =
  "UPDATE episodes SET position_seconds = ?, played = ?, last_played_at = ?, history_at = ? WHERE id = ?"

/** Episodes listened to, the most recent first. */
export const HISTORY_SQL =
  "SELECT * FROM episodes WHERE history_at IS NOT NULL ORDER BY history_at DESC"

/** Empties the history. Where each episode was left, and whether it was played, stay. */
export const CLEAR_HISTORY_SQL = "UPDATE episodes SET history_at = NULL"
