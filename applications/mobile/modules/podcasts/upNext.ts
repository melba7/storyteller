// LOFI-FORK: the podcasts section's Up Next rules (see FORK.md).
//
// Pure functions for the Up Next screen: the list's total time left, the count on the tab,
// the order after a move, and what an episode becomes when it is queued. The queue itself
// lives in Swift (it starts the next episode with the screen locked); the screens only show
// what Swift last said.
import { moveShow } from "./arrange"
import type { UpNextItem } from "./index"
import { type Show, type StoredEpisode, formatDuration } from "./library"
import { badgeLabel } from "./libraryView"
import { resumeStart } from "./playbackRules"

/** The queue item for an episode: what the player needs to start it without JavaScript. */
export function queueItem(
  episode: StoredEpisode,
  show: Show | null,
): UpNextItem {
  return {
    id: episode.id,
    showId: episode.showId,
    url: episode.audioUrl,
    type: episode.audioType,
    chaptersUrl: episode.chaptersUrl,
    title: episode.title,
    language: show?.language ?? null,
    showTitle: show?.title ?? "",
    artworkUrl: episode.imageUrl ?? show?.imageUrl ?? null,
    duration: episode.durationSeconds,
    position: resumeStart(
      episode.positionSeconds,
      episode.durationSeconds,
      episode.played,
    ),
  }
}

/** Seconds left in one item; 0 when its length is not known. */
function timeLeft(item: UpNextItem): number {
  const { duration, position } = item
  if (duration === null || duration === undefined || !(duration > 0)) return 0
  return Math.max(0, duration - Math.max(0, position))
}

/** The time left over the whole queue, as the header reads it: "3 h 20 min left". */
export function queueTimeLeft(items: readonly UpNextItem[]): string {
  const total = items.reduce((sum, item) => sum + timeLeft(item), 0)
  const text = formatDuration(total)
  return text === "" ? "" : `${text} left`
}

/** What the tab's badge says: the number of queued episodes, "99+" past 99, nothing at 0. */
export function upNextBadge(items: readonly UpNextItem[]): string {
  return badgeLabel(items.length)
}

/** The header over the list: "3 episodes · 3 h 20 min left". */
export function upNextSummary(items: readonly UpNextItem[]): string {
  if (items.length === 0) return ""
  const noun = items.length === 1 ? "episode" : "episodes"
  return [`${items.length} ${noun}`, queueTimeLeft(items)]
    .filter((part) => part !== "")
    .join(" · ")
}

/** The queue after moving the item at `from` to `to`. A move out of range is clamped. */
export function orderAfterMove(
  items: readonly UpNextItem[],
  from: number,
  to: number,
): UpNextItem[] {
  const byId = new Map(items.map((item) => [item.id, item]))
  return moveShow(
    items.map((item) => item.id),
    from,
    to,
  ).flatMap((id) => byId.get(id) ?? [])
}

/** Whether the episode is in the queue. */
export function isQueued(items: readonly UpNextItem[], id: string): boolean {
  return items.some((item) => item.id === id)
}

/** What an episode row says about the queue: its place, or nothing. */
export function queuedLabel(items: readonly UpNextItem[], id: string): string {
  const at = items.findIndex((item) => item.id === id)
  return at < 0 ? "" : `Up Next, number ${at + 1}`
}

/** For VoiceOver on a queue row. */
export function rowLabel(
  item: UpNextItem,
  index: number,
  count: number,
): string {
  const left = formatDuration(timeLeft(item))
  return [
    item.title,
    item.showTitle,
    left === "" ? "" : `${left} left`,
    `place ${index + 1} of ${count}`,
  ]
    .filter((part) => part !== "")
    .join(", ")
}

/**
 * The move that turns the queue `before` into the queue `after`, when `after` is `before`
 * with one episode moved; null when nothing moved or the lists differ otherwise.
 */
export function moveBetween(
  before: readonly string[],
  after: readonly string[],
): { from: number; to: number } | null {
  if (before.length !== after.length) return null
  const at = before.findIndex((id, i) => id !== after[i])
  if (at < 0) return null
  const same = (a: readonly string[], b: readonly string[]) =>
    a.every((id, i) => id === b[i])
  // The episode moved down from `at`, or an episode moved up to `at`.
  const down = after.indexOf(before[at] as string)
  if (down > at && same(moveShow([...before], at, down), after)) {
    return { from: at, to: down }
  }
  const up = before.indexOf(after[at] as string)
  if (up > at && same(moveShow([...before], up, at), after)) {
    return { from: up, to: at }
  }
  return null
}

/** How much of an episode is played, 0 to 1, for the line under a row; null until it has started. */
export function progressFraction(
  position: number,
  duration: number | null | undefined,
): number | null {
  if (duration === null || duration === undefined || !(duration > 0)) {
    return null
  }
  if (!(position > 0)) return null
  return Math.min(1, position / duration)
}
