// LOFI-FORK: the podcasts section's Library rooms (see FORK.md).
//
// Pure rules for Library's "Recently Updated" grid.
import { formatEpisodeDate } from "./library"

/** One followed show in the grid: when its newest episode came out and whether it has new ones. */
export type RecentShow = {
  showId: string
  newestAt: number
  unplayed: number
}

const DAY_MS = 86_400_000

function startOfDay(time: number): number {
  const date = new Date(time)
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime()
}

/**
 * The grey line under a show in "Recently Updated": "Updated today", "Updated yesterday",
 * "3 days ago", "2 weeks ago", and for anything over eight weeks the date. Days are the
 * phone's calendar days. A date in the future counts as today.
 */
export function updatedLabel(newestAt: number, now: number): string {
  const days = Math.max(
    0,
    Math.round((startOfDay(now) - startOfDay(newestAt)) / DAY_MS),
  )
  if (days === 0) return "Updated today"
  if (days === 1) return "Updated yesterday"
  if (days < 7) return `${days} days ago`
  const weeks = Math.floor(days / 7)
  if (weeks === 1) return "1 week ago"
  if (weeks < 8) return `${weeks} weeks ago`
  return formatEpisodeDate(newestAt)
}

/** Reads the rows of `RECENT_SHOWS_SQL`. A row without a usable date is left out. */
export function recentShowsFromRows(
  rows: readonly Record<string, unknown>[],
): RecentShow[] {
  return rows.flatMap((row) => {
    const newest = row["newest_at"]
    const id = row["show_id"]
    if (typeof id !== "string" || typeof newest !== "number") return []
    return [
      { showId: id, newestAt: newest, unplayed: Number(row["unplayed"] ?? 0) },
    ]
  })
}
