// LOFI-FORK: the podcasts section's Library rooms (see FORK.md).
//
// The SQL behind Library's "Latest Episodes" and "Recently Updated", kept apart from the
// database file (which needs the native SQLite module) so tests can run it against a real
// database. "Your files" (the show of added audio files) is not a followed show, so neither
// list counts it. Saved is `STAR_ORDER_SQL` in episodeSql.ts.

/** How many episodes "Latest Episodes" shows. */
export const LATEST_LIMIT = 100

/** The newest dated episodes of the followed shows that are not archived, newest first. */
export const LATEST_SQL = `SELECT e.* FROM episodes e
  WHERE e.show_id != 'local-files' AND e.archived = 0 AND e.published_at IS NOT NULL
  ORDER BY e.published_at DESC, e.id
  LIMIT ${LATEST_LIMIT}`

/**
 * The followed shows that have a dated episode, the one with the newest episode first: each
 * show's id, when its newest episode came out, and how many unplayed, unarchived episodes
 * came out since the show was followed (the grid's dot).
 */
export const RECENT_SHOWS_SQL = `SELECT s.id AS show_id,
    MAX(e.published_at) AS newest_at,
    COUNT(CASE WHEN e.played = 0 AND e.archived = 0 AND e.published_at >= s.added_at
      THEN 1 END) AS unplayed
  FROM shows s JOIN episodes e ON e.show_id = s.id AND e.published_at IS NOT NULL
  WHERE s.id != 'local-files'
  GROUP BY s.id
  ORDER BY newest_at DESC, s.title COLLATE NOCASE, s.id`
