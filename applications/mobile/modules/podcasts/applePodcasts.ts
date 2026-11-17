// LOFI-FORK: the podcasts section's follow list from Apple Podcasts (see FORK.md).
//
// The Mac writes `Podcasts/apple-podcasts.json` into the sounds folder: the shows followed in
// Apple Podcasts and the episodes finished there. These are the rules for what the phone does
// with it. Nothing here touches the database or the folder (appleSync.ts does).

export type AppleShow = { feed: string; title: string | null }
export type AppleFinished = { feed: string; guid: string }
export type AppleExport = {
  shows: AppleShow[]
  finished: AppleFinished[]
}

/**
 * One key per feed, so two spellings of an address match: no scheme, no `www.`, the host in
 * lower case, no fragment and no closing slash. The path and query keep their case.
 */
export function feedKey(feed: string): string {
  const text = feed.trim().replace(/#.*$/, "")
  const match = /^(?:[a-z][a-z0-9+.-]*:)?\/\/([^/?]*)(.*)$/i.exec(text)
  const host = (match ? match[1] : text.split(/[/?]/)[0]) ?? ""
  const rest = match ? (match[2] ?? "") : text.slice(host.length)
  return (
    host.toLowerCase().replace(/^www\./, "") + rest.replace(/\/+(?=\?|$)/, "")
  )
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

/**
 * Reads the file's text. Null when it is not the version 1 file (not JSON, another version,
 * missing lists), so a file from a newer Mac tool is skipped instead of misread. Entries
 * with an empty feed or guid are left out.
 */
export function parseAppleExport(text: string | null): AppleExport | null {
  if (text === null) return null
  let data: unknown
  try {
    data = JSON.parse(text)
  } catch {
    return null
  }
  if (!isRecord(data) || data["version"] !== 1) return null
  const { shows, finished } = data
  if (!Array.isArray(shows) || !Array.isArray(finished)) return null
  const result: AppleExport = { shows: [], finished: [] }
  for (const show of shows) {
    if (!isRecord(show) || typeof show["feed"] !== "string") continue
    if (feedKey(show["feed"]) === "") continue
    result.shows.push({
      feed: show["feed"],
      title: typeof show["title"] === "string" ? show["title"] : null,
    })
  }
  for (const episode of finished) {
    if (!isRecord(episode)) continue
    const { feed, guid } = episode
    if (typeof feed !== "string" || typeof guid !== "string") continue
    if (feedKey(feed) === "" || guid === "") continue
    result.finished.push({ feed, guid })
  }
  return result
}

export type FollowPlan = {
  /** Shows to subscribe to: followed in Apple, never seen here before, not in the library. */
  subscribe: AppleShow[]
  /** The seen list with every show in the file that is in the library already. */
  seen: string[]
}

/**
 * Which followed shows to subscribe to. A show is added once: its key goes on the seen list,
 * so one the listener unsubscribes from is not added again. A show unfollowed in Apple is
 * left alone, because nothing here reads absence. Shows already in the library only go on
 * the seen list. The first run (an empty seen list) subscribes to everything followed.
 */
export function planFollows(
  file: AppleExport,
  seen: readonly string[],
  libraryFeeds: readonly string[],
): FollowPlan {
  const seenKeys = new Set(seen)
  const library = new Set(libraryFeeds.map(feedKey))
  const next = new Set(seenKeys)
  const subscribe: AppleShow[] = []
  const queued = new Set<string>()
  for (const show of file.shows) {
    const key = feedKey(show.feed)
    if (seenKeys.has(key) || queued.has(key)) continue
    if (library.has(key)) next.add(key)
    else {
      queued.add(key)
      subscribe.push(show)
    }
  }
  return { subscribe, seen: [...next] }
}

export type PlayedInShow = { showId: string; guids: string[] }

/**
 * The finished episodes to mark played, by show: only for shows in the library, by guid.
 * Shows the listener does not follow here, and guids the show does not have, are ignored
 * later (the database update matches nothing).
 */
export function planPlayed(
  file: AppleExport,
  library: readonly { id: string; feedUrl: string }[],
): PlayedInShow[] {
  const showByKey = new Map(
    library.map((show) => [feedKey(show.feedUrl), show.id]),
  )
  const byShow = new Map<string, Set<string>>()
  for (const { feed, guid } of file.finished) {
    const showId = showByKey.get(feedKey(feed))
    if (showId === undefined) continue
    const guids = byShow.get(showId) ?? new Set<string>()
    guids.add(guid)
    byShow.set(showId, guids)
  }
  return [...byShow].map(([showId, guids]) => ({ showId, guids: [...guids] }))
}

/** The seen list as kept in AsyncStorage; an unreadable one is empty. */
export function parseSeen(saved: string | null): string[] {
  if (saved === null) return []
  try {
    const data: unknown = JSON.parse(saved)
    return Array.isArray(data)
      ? data.filter((key): key is string => typeof key === "string")
      : []
  } catch {
    return []
  }
}
