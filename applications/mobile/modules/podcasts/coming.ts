// LOFI-FORK: the podcasts section's wait for the Mac's copy (see FORK.md).
//
// While the Mac prepares an episode, `Podcasts/ahead-ads.json` lists it in a top-level `coming`
// list: `{"feed": "...", "guid": "...", "since": 1700000000}` (since: unix seconds when the Mac
// picked it). The phone does not start its own automatic download of such an episode for 2 hours,
// so it takes the Mac's copy instead (preparedSync.ts). After 2 hours, or when the entry is gone
// without a copy, it downloads as before. Pressing Play and a download the listener starts by
// hand never wait: only the automatic paths of automaticRun.ts filter with `withoutHeld`.

/** How long the phone waits for the Mac's copy of an episode it has picked (milliseconds). */
export const COMING_HOLD_MS = 2 * 60 * 60 * 1000

/** A `since` this far ahead of the phone's clock is not believed, so a wrong clock holds nothing. */
const CLOCK_SLACK_MS = 10 * 60 * 1000

export type ComingEntry = { feed: string; guid: string; since: number }

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

/** The `coming` list of the file's text. Anything unreadable, or of the wrong shape, is left out. */
export function parseComing(text: string): ComingEntry[] {
  let value: unknown
  try {
    value = JSON.parse(text)
  } catch {
    return []
  }
  if (!isRecord(value) || !Array.isArray(value["coming"])) return []
  return (value["coming"] as unknown[]).flatMap((one) => {
    if (!isRecord(one)) return []
    const { feed, guid, since } = one
    if (typeof feed !== "string" || feed === "") return []
    if (typeof guid !== "string" || guid === "") return []
    if (typeof since !== "number" || !Number.isFinite(since)) return []
    return [{ feed, guid, since }]
  })
}

/** The key an episode has in `heldKeys`. */
export function comingKey(feed: string, guid: string): string {
  return `${feed}\n${guid}`
}

/** The episodes (by `comingKey`) the phone waits for: in `coming` and less than 2 hours old. */
export function heldKeys(
  coming: readonly ComingEntry[],
  nowMs: number,
): Set<string> {
  const held = new Set<string>()
  for (const one of coming) {
    const sinceMs = one.since * 1000
    if (sinceMs > nowMs + CLOCK_SLACK_MS) continue
    if (nowMs - sinceMs < COMING_HOLD_MS)
      held.add(comingKey(one.feed, one.guid))
  }
  return held
}

/** What an automatic download may start: the episodes whose id is not held. */
export function withoutHeld<T extends { id: string }>(
  episodes: readonly T[],
  heldIds: ReadonlySet<string>,
): T[] {
  return episodes.filter((episode) => !heldIds.has(episode.id))
}
