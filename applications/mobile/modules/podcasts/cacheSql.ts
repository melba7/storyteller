// LOFI-FORK: the podcasts section's cache table clean-up (see FORK.md).
//
// The SQL is kept apart from dbFeeds.ts (which needs the native SQLite module) so a test can
// run it against a real database.

/** Cache rows older than this are deleted whenever something is put in the cache. */
export const CACHE_KEEP_MS = 7 * 24 * 60 * 60 * 1000

/** Params: the oldest saved time to keep (now minus `CACHE_KEEP_MS`). */
export const PRUNE_CACHE_SQL = "DELETE FROM cache WHERE saved_at < ?"
