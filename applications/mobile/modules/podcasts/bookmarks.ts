// LOFI-FORK: the podcasts section's bookmarks (see FORK.md).
//
// Pure rules: a bookmark and its title, reading the bookmarks the headphones made while
// JavaScript wasn't running (Swift's PendingBookmarks file), and turning them into saved
// bookmarks. The database calls are in dbBookmarks.ts.
import { formatTime } from "./playbackRules"

export type Bookmark = {
  id: string
  episodeId: string
  positionSeconds: number
  title: string
  /** Milliseconds since 1970. */
  createdAt: number
}

/** A bookmark the headphones made, waiting to be saved. */
export type PendingBookmark = {
  id: string
  episodeId: string
  positionSeconds: number
  createdAt: number
}

/** "Bookmark at 12:34", "Bookmark at 1:02:03". */
export function defaultBookmarkTitle(positionSeconds: number): string {
  return `Bookmark at ${formatTime(positionSeconds)}`
}

/** The title typed by the listener, or the default when it is left empty. */
export function bookmarkTitle(
  typed: string | undefined,
  positionSeconds: number,
): string {
  const title = (typed ?? "").trim()
  return title === "" ? defaultBookmarkTitle(positionSeconds) : title
}

/** What VoiceOver reads for a bookmark: its title and where it is. */
export function bookmarkLabel(bookmark: Bookmark): string {
  return `${bookmark.title}, at ${formatTime(bookmark.positionSeconds)}`
}

/**
 * The bookmarks in the text Swift gives. Anything that isn't a list gives none, and an entry
 * missing a field or with a bad number is left out.
 */
export function parsePending(text: string): PendingBookmark[] {
  let value: unknown
  try {
    value = JSON.parse(text)
  } catch {
    return []
  }
  if (!Array.isArray(value)) return []
  return value.flatMap((entry: unknown): PendingBookmark[] => {
    if (typeof entry !== "object" || entry === null) return []
    const e = entry as Record<string, unknown>
    const position = e["positionSeconds"]
    const created = e["createdAt"]
    if (
      typeof e["id"] !== "string" ||
      e["id"] === "" ||
      typeof e["episodeId"] !== "string" ||
      e["episodeId"] === "" ||
      typeof position !== "number" ||
      !Number.isFinite(position) ||
      position < 0 ||
      typeof created !== "number" ||
      !Number.isFinite(created)
    ) {
      return []
    }
    return [
      {
        id: e["id"],
        episodeId: e["episodeId"],
        positionSeconds: position,
        createdAt: created,
      },
    ]
  })
}

/**
 * The bookmarks to save from the pending ones: the ones whose episode is in the library
 * (`known`), each with the default title. The others can't be listed anywhere, so they are
 * dropped.
 */
export function pendingToBookmarks(
  pending: readonly PendingBookmark[],
  known: ReadonlySet<string>,
): Bookmark[] {
  return pending
    .filter((mark) => known.has(mark.episodeId))
    .map((mark) => ({
      ...mark,
      title: defaultBookmarkTitle(mark.positionSeconds),
    }))
}

type Row = Record<string, unknown>

export function bookmarkFromRow(row: Row): Bookmark {
  return {
    id: String(row["id"] ?? ""),
    episodeId: String(row["episode_id"] ?? ""),
    positionSeconds: Math.max(0, Number(row["position_seconds"] ?? 0)),
    title: String(row["title"] ?? ""),
    createdAt: Number(row["created_at"] ?? 0),
  }
}
