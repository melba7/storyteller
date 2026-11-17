// LOFI-FORK: the podcasts section's follow list from Apple Podcasts (see FORK.md).
//
// The Mac writes `Podcasts/apple-podcasts.json` into the sounds folder: the shows followed in
// Apple Podcasts and the episodes finished there. These are the rules for what the phone does
// with it. Nothing here touches the database or the folder (appleSync.ts does).

import { feedShows, isLocalFeedUrl } from "./localFiles"

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
  libraryTitles: readonly string[] = [],
): FollowPlan {
  const seenKeys = new Set(seen)
  const library = new Set(libraryFeeds.map(feedKey))
  const titles = new Set(libraryTitles.map(titleKey))
  const next = new Set(seenKeys)
  const subscribe: AppleShow[] = []
  const queued = new Set<string>()
  for (const show of file.shows) {
    const key = feedKey(show.feed)
    if (isLocalFeedUrl(show.feed)) continue
    if (seenKeys.has(key) || queued.has(key)) continue
    // A show the listener unsubscribed from stays dropped under another address too.
    if (show.title !== null && seenKeys.has(titleSeenKey(show.title))) continue
    // The same show under another address (a feed that moved, or the other app's export)
    // is the show the listener already has, or chose to drop.
    const title = show.title === null ? "" : titleKey(show.title)
    if (library.has(key) || (title !== "" && titles.has(title))) next.add(key)
    else {
      queued.add(key)
      subscribe.push(show)
    }
  }
  return { subscribe, seen: [...next] }
}

function titleKey(title: string): string {
  return title.trim().toLowerCase()
}

function titleSeenKey(title: string): string {
  return `title:${titleKey(title)}`
}

/**
 * The seen list with this feed's key added (an unsubscribed show is not added again), and
 * its title's, so the same show under another address in the file is not added either.
 */
export function withSeen(
  seen: readonly string[],
  feed: string,
  title: string | null = null,
): string[] {
  const keys = [feedKey(feed)]
  if (title !== null && titleKey(title) !== "") keys.push(titleSeenKey(title))
  return [...new Set([...seen, ...keys])]
}

/**
 * The file with each finished episode of a show the library has under another address pointed
 * at the library's address (matched by the show's title in the file), so the episodes finished
 * in Apple Podcasts are marked played for it. A feed key that matches is left alone.
 */
export function withLibraryFeeds(
  file: AppleExport,
  library: readonly { feedUrl: string; title?: string }[],
): AppleExport {
  const shows = feedShows(library)
  const known = new Set(shows.map((show) => feedKey(show.feedUrl)))
  const byTitle = new Map<string, string>()
  for (const show of shows) {
    const title = titleKey(show.title ?? "")
    if (title !== "" && !byTitle.has(title)) byTitle.set(title, show.feedUrl)
  }
  const titleOf = new Map<string, string>()
  for (const show of file.shows) {
    if (show.title !== null)
      titleOf.set(feedKey(show.feed), titleKey(show.title))
  }
  return {
    ...file,
    finished: file.finished.map((item) => {
      const key = feedKey(item.feed)
      if (known.has(key)) return item
      const match = byTitle.get(titleOf.get(key) ?? "")
      return match === undefined ? item : { ...item, feed: match }
    }),
  }
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
    feedShows(library).map((show) => [feedKey(show.feedUrl), show.id]),
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

/** The key of one finished episode, for the applied list. */
export function appliedKey(feed: string, guid: string): string {
  return `${feedKey(feed)}\n${guid}`
}

/**
 * The finished episodes to mark played that were not marked before. `applied` holds the pairs
 * (show feed, guid) done on earlier runs, so an episode the listener marked unplayed since
 * stays unplayed. Pairs of shows not in the library yet are not applied, so they count when
 * the show arrives. A pair for an episode the phone does not have yet (`hasEpisode` says no)
 * is not applied either: it is `pending`, marked when the feed brings the episode (see
 * `pendingGuids`) and by a later run if it is there by then. The new applied list keeps only
 * pairs still in the file, so it stays small.
 */
export function planPlayedOnce(
  file: AppleExport,
  library: readonly { id: string; feedUrl: string }[],
  applied: readonly string[],
  hasEpisode: (feed: string, guid: string) => boolean = () => true,
): { plays: PlayedInShow[]; applied: string[]; pending: string[] } {
  const done = new Set(applied)
  const inLibrary = new Set(feedShows(library).map((s) => feedKey(s.feedUrl)))
  const fresh: AppleFinished[] = []
  const next = new Set<string>()
  const pending: string[] = []
  for (const item of file.finished) {
    const key = appliedKey(item.feed, item.guid)
    if (done.has(key)) next.add(key)
    else if (inLibrary.has(feedKey(item.feed))) {
      if (hasEpisode(item.feed, item.guid)) {
        next.add(key)
        fresh.push(item)
      } else if (!pending.includes(key)) pending.push(key)
    }
  }
  return {
    plays: planPlayed({ shows: [], finished: fresh }, library),
    applied: [...next],
    pending,
  }
}

/** The guids of this show's finished episodes the phone did not have yet. */
export function pendingGuids(
  pending: readonly string[],
  feed: string,
): Set<string> {
  const prefix = `${feedKey(feed)}\n`
  return new Set(
    pending
      .filter((key) => key.startsWith(prefix))
      .map((key) => key.slice(prefix.length)),
  )
}

/** Episodes that arrived and were marked played: no longer pending, now applied. */
export function settleArrival(
  pending: readonly string[],
  applied: readonly string[],
  feed: string,
  guids: readonly string[],
): { pending: string[]; applied: string[] } {
  const keys = new Set(guids.map((guid) => appliedKey(feed, guid)))
  return {
    pending: pending.filter((key) => !keys.has(key)),
    applied: [...new Set([...applied, ...keys])],
  }
}

/** The followed show whose feed is this one, however either address is spelled. */
export function findShowByFeed<T extends { feedUrl: string }>(
  shows: readonly T[],
  feed: string,
): T | undefined {
  const key = feedKey(feed)
  return feedShows(shows).find((show) => feedKey(show.feedUrl) === key)
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

const RETRY_FAILED_MS = 24 * 3_600_000

/** The shows to try now: one that failed to subscribe is tried again after a day, not at every open. */
export function dueShows(
  shows: readonly AppleShow[],
  failedAt: Readonly<Record<string, number>>,
  now: number,
): AppleShow[] {
  return shows.filter((show) => {
    const failed = failedAt[feedKey(show.feed)]
    return failed === undefined || now - failed >= RETRY_FAILED_MS
  })
}

/** The failure times as kept in AsyncStorage, by feed key; unreadable means none. */
export function parseFailures(saved: string | null): Record<string, number> {
  if (saved === null) return {}
  try {
    const data: unknown = JSON.parse(saved)
    if (!isRecord(data)) return {}
    return Object.fromEntries(
      Object.entries(data).filter(
        (entry): entry is [string, number] => typeof entry[1] === "number",
      ),
    )
  } catch {
    return {}
  }
}
