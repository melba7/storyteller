// LOFI-FORK: the podcasts section's library view rules (see FORK.md).
//
// Pure functions for the Podcasts tab: how shows are ordered, what the unplayed badge
// says, and how the chosen layout and order are saved. Nothing here touches the database
// (db.ts does) or the screen.
import { type Show } from "./library"

export type LibraryLayout = "large" | "small" | "list"
export type LibraryOrder = "name" | "added" | "newest" | "own"
export type LibraryView = { layout: LibraryLayout; order: LibraryOrder }

export const DEFAULT_VIEW: LibraryView = { layout: "large", order: "name" }

const LAYOUTS: LibraryLayout[] = ["large", "small", "list"]
const ORDERS: LibraryOrder[] = ["name", "added", "newest", "own"]

/** What the database knows about a show's episodes, for ordering and for the badge. */
export type ShowActivity = {
  /** When the newest dated episode came out, or null when no episode has a date. */
  newestAt: number | null
  /** Whether that newest dated episode is played. */
  newestPlayed: boolean
  /** Unplayed episodes released at or after the show was followed. */
  unplayedSince: number
}

export type ActivityByShow = Record<string, ShowActivity>

// MARK: Ordering

function nameKey(show: Show): string {
  return show.title
    .trim()
    .toLowerCase()
    .replace(/^the\s+/, "")
}

function byName(a: Show, b: Show): number {
  const left = nameKey(a)
  const right = nameKey(b)
  return left < right ? -1 : left > right ? 1 : 0
}

/** Placed shows first by position, then the others oldest first (a new show goes last). */
function byOwn(a: Show, b: Show): number {
  if (a.ownPosition !== null && b.ownPosition !== null) {
    return a.ownPosition - b.ownPosition
  }
  if (a.ownPosition !== null) return -1
  if (b.ownPosition !== null) return 1
  return a.addedAt - b.addedAt
}

/**
 * A new list in the chosen order. By name ignores case and a leading "The ". By date
 * added and by newest episode put the newest first; shows with no dated episode go last.
 * "Your order" puts placed shows first, then the rest oldest first.
 * Shows that tie keep their given order, except that newest-episode ties go by name.
 */
export function sortShows(
  shows: Show[],
  order: LibraryOrder,
  activity: ActivityByShow,
): Show[] {
  const compare = (a: Show, b: Show): number => {
    if (order === "name") return byName(a, b)
    if (order === "added") return b.addedAt - a.addedAt
    if (order === "own") return byOwn(a, b)
    const left = activity[a.id]?.newestAt ?? null
    const right = activity[b.id]?.newestAt ?? null
    if (left === right) return byName(a, b)
    if (left === null) return 1
    if (right === null) return -1
    return right - left
  }
  return shows
    .map((show, index) => ({ show, index }))
    .sort((a, b) => compare(a.show, b.show) || a.index - b.index)
    .map(({ show }) => show)
}

// MARK: The badge

/**
 * The unplayed episodes released since the show was followed, plus the newest episode when
 * it is unplayed and came out before that (so a show just followed shows 1). Episodes that
 * are partly heard still count as unplayed.
 */
export function badgeCount(
  activity: ShowActivity | undefined,
  addedAt: number,
): number {
  if (!activity) return 0
  const oldNewest =
    activity.newestAt !== null &&
    activity.newestAt < addedAt &&
    !activity.newestPlayed
  return activity.unplayedSince + (oldNewest ? 1 : 0)
}

/** The badge's text: empty at 0, the number up to 99, then "99+". */
export function badgeLabel(count: number): string {
  if (count <= 0) return ""
  return count > 99 ? "99+" : String(count)
}

// MARK: Saving the choice

export function serializeLibraryView(view: LibraryView): string {
  return JSON.stringify({ layout: view.layout, order: view.order })
}

/** Reads the saved choice. Anything unknown or broken falls back to large grid and name. */
export function parseLibraryView(saved: string | null): LibraryView {
  let value: unknown = null
  try {
    value = saved === null ? null : JSON.parse(saved)
  } catch {
    value = null
  }
  const record =
    typeof value === "object" && value !== null && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : {}
  const layout = LAYOUTS.find((candidate) => candidate === record["layout"])
  const order = ORDERS.find((candidate) => candidate === record["order"])
  return {
    layout: layout ?? DEFAULT_VIEW.layout,
    order: order ?? DEFAULT_VIEW.order,
  }
}
