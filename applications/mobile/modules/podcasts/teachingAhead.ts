// LOFI-FORK: the podcasts section's teaching files from the Mac (see FORK.md).
//
// The small rules behind sending the table of episodes (teaching.ts `aheadEpisodesText`) to the
// native side without doing the work again for nothing: when a text is new, what to read from the
// database, and how one run reads the phone's list of next episodes once. Nothing here touches the
// database or the native modules (teachingSync.ts does).
import { AHEAD_PER_SHOW } from "./teaching"

/** Whether `text` is not the one last sent (`null`: nothing was sent yet). */
export function textChanged(text: string, lastSent: string | null): boolean {
  return text !== lastSent
}

/**
 * Reads the first time it is asked and gives that answer, or that failure, to every ask after,
 * so the parts of one run that need the same thing read it once.
 */
export function sharedRead<T>(read: () => Promise<T>): () => Promise<T> {
  let started: Promise<T> | null = null
  return () => (started ??= read())
}

/**
 * What the table of episodes can use of one show, as a query for the database: the show's newest
 * `AHEAD_PER_SHOW` unplayed, unarchived episodes (undated ones count last) and the ones with these
 * `guids` (the show's episodes in the phone's list for the Mac), whatever their age or state.
 * The rows are whole episodes; the order is left to `sortEpisodes`.
 */
export function aheadEpisodesQuery(
  showId: string,
  guids: readonly string[],
): { sql: string; params: string[] } {
  const listed =
    guids.length === 0
      ? ""
      : ` OR (show_id = ? AND guid IN (${guids.map(() => "?").join(", ")}))`
  return {
    sql: `SELECT * FROM episodes WHERE id IN (
      SELECT id FROM episodes WHERE show_id = ? AND played = 0 AND archived = 0
      ORDER BY published_at DESC, id LIMIT ${AHEAD_PER_SHOW})${listed}`,
    params: guids.length === 0 ? [showId] : [showId, showId, ...guids],
  }
}
