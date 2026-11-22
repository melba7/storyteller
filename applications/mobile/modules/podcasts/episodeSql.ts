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
 * Params: played (1 or 0), the same again, the same again, the time now, episode id. Marking
 * played keeps the place and starts the clean-up clock (`last_played_at`) if none is running,
 * so "delete played" and "archive after played" apply; it leaves the history alone. Marking
 * unplayed forgets the place.
 */
export const SET_PLAYED_SQL =
  "UPDATE episodes SET played = ?, position_seconds = CASE WHEN ? = 1 THEN position_seconds ELSE 0 END, last_played_at = CASE WHEN ? = 1 THEN COALESCE(last_played_at, ?) ELSE last_played_at END WHERE id = ?"

/**
 * Saves where the listener is and when they listened. Params: place, played (1 or 0),
 * last played time, history time, episode id.
 */
export const RECORD_LISTEN_SQL =
  "UPDATE episodes SET position_seconds = ?, played = ?, last_played_at = ?, history_at = ? WHERE id = ?"

/**
 * An episode finished in Apple Podcasts. Params: the time of the sync, show id, the feed's
 * guid. It starts the clean-up clock (`last_played_at`) if none is running, so "delete
 * played" and "archive after a day or week" apply, and leaves the history alone.
 */
export const MARK_PLAYED_FROM_APPLE_SQL =
  "UPDATE episodes SET played = 1, last_played_at = COALESCE(last_played_at, ?) WHERE show_id = ? AND guid = ? AND played = 0"

/** Episodes listened to, the most recent first. */
export const HISTORY_SQL =
  "SELECT * FROM episodes WHERE history_at IS NOT NULL ORDER BY history_at DESC"

/** Empties the history. Where each episode was left, and whether it was played, stay. */
export const CLEAR_HISTORY_SQL = "UPDATE episodes SET history_at = NULL"

/**
 * The episode listened to last, for the mini player after a restart. It reads `history_at`,
 * which only real listening writes, so an episode marked played in Apple Podcasts or by hand
 * never takes its place. Clearing the history leaves the mini player empty.
 */
export const LAST_LISTENED_SQL =
  "SELECT * FROM episodes WHERE history_at IS NOT NULL ORDER BY history_at DESC LIMIT 1"

/**
 * Per show: its newest dated episode's date, whether that episode is done with (played or
 * archived, so the Library badge does not count it), and how many unplayed, unarchived
 * episodes came out at or after the show was followed.
 */
export const SHOW_ACTIVITY_SQL = `SELECT s.id AS show_id,
       MAX(e.published_at) AS newest_at,
       (SELECT CASE WHEN n.played = 1 OR n.archived = 1 THEN 1 ELSE 0 END FROM episodes n
         WHERE n.show_id = s.id AND n.published_at IS NOT NULL
         ORDER BY n.published_at DESC LIMIT 1) AS newest_played,
       COUNT(CASE WHEN e.played = 0 AND e.archived = 0
         AND e.published_at >= s.added_at THEN 1 END)
         AS unplayed_since
     FROM shows s LEFT JOIN episodes e ON e.show_id = s.id
     GROUP BY s.id`
