// LOFI-FORK: the podcasts section's episode search in your shows (see FORK.md).
//
// Turns what the listener typed into one SQL query over the library's episodes. Every word
// must be in the title or the notes; `%` and `_` count as the characters they are. Title
// matches come first, then the newest. db.ts runs the query.
import { type StoredEpisode, episodeFromRow } from "./library"

/** How many results one search gives. */
export const SEARCH_LIMIT = 100

/** The words typed: split on spaces, none empty. */
export function searchWords(input: string): string[] {
  return input.split(/\s+/).filter((word) => word !== "")
}

/** A LIKE pattern that finds the word anywhere, with `\`, `%` and `_` taken literally. */
export function likePattern(word: string): string {
  return `%${word.replace(/[\\%_]/g, (character) => `\\${character}`)}%`
}

const LIKE = "LIKE ? ESCAPE '\\'"

/**
 * The query and its values for what was typed, or null when no word was typed. Each word
 * must be in the title or the notes. Episodes whose title has every word come first, then
 * the newest first, undated last.
 */
export function localSearchQuery(
  input: string,
  limit = SEARCH_LIMIT,
): { sql: string; params: (string | number)[] } | null {
  const patterns = searchWords(input).map(likePattern)
  if (patterns.length === 0) return null
  const anywhere = patterns.map(() => `(e.title ${LIKE} OR e.notes ${LIKE})`)
  const inTitle = patterns.map(() => `e.title ${LIKE}`)
  const sql = `SELECT e.*, s.title AS show_title, s.image_url AS show_image_url
    FROM episodes e JOIN shows s ON s.id = e.show_id
    WHERE ${anywhere.join(" AND ")}
    ORDER BY (${inTitle.join(" AND ")}) DESC,
      e.published_at IS NULL, e.published_at DESC, e.id
    LIMIT ?`
  return {
    sql,
    params: [
      ...patterns.flatMap((pattern) => [pattern, pattern]),
      ...patterns,
      limit,
    ],
  }
}

/** One episode found in the library, with the show it belongs to. */
export type EpisodeHit = {
  episode: StoredEpisode
  showTitle: string
  showImageUrl: string | null
}

export function hitFromRow(row: Record<string, unknown>): EpisodeHit {
  const image = row["show_image_url"]
  return {
    episode: episodeFromRow(row),
    showTitle: typeof row["show_title"] === "string" ? row["show_title"] : "",
    showImageUrl: typeof image === "string" ? image : null,
  }
}
