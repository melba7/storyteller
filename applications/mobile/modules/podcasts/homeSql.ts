// LOFI-FORK: the podcasts section's Home (see FORK.md).
//
// The SQL behind Home's "Up Next" shelf and "Your Top Shows", kept apart from the database
// file (which needs the native SQLite module) so tests can run it against a real database.
// "Your files" (the show of added audio files) is not a followed show: its episodes can be in
// progress, but are never "new".

/** How many episodes the Up Next shelf holds. */
export const UP_NEXT_LIMIT = 20

/**
 * The shelf's candidates: every episode in progress (a place saved, not played, not
 * archived), and the newest unplayed, unarchived, dated episode of each followed show. The
 * order and the cap are `orderUpNextShelf`'s.
 */
export const UP_NEXT_CANDIDATES_SQL = `SELECT * FROM episodes
  WHERE position_seconds > 0 AND played = 0 AND archived = 0
UNION
SELECT e.* FROM episodes e
  WHERE e.show_id != 'local-files' AND e.played = 0 AND e.archived = 0
    AND e.published_at IS NOT NULL
    AND e.id = (SELECT n.id FROM episodes n
      WHERE n.show_id = e.show_id AND n.played = 0 AND n.archived = 0
        AND n.published_at IS NOT NULL
      ORDER BY n.published_at DESC, n.id LIMIT 1)`

/** Per show, when it was last listened to, from the listening history. */
export const SHOW_PLAYS_SQL = `SELECT show_id, MAX(history_at) AS last_at FROM episodes
  WHERE history_at IS NOT NULL AND show_id != 'local-files'
  GROUP BY show_id`
