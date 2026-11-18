// LOFI-FORK: the podcasts section's charts, loaded in groups (see FORK.md).
//
// Apple's lookup service allows about 20 calls a minute, so many lists are loaded three at
// a time: the three chart feeds together, then one lookup call for all their ids. A kept
// list is reported first, even an old one, so a page can draw yesterday's chart at once.
import {
  CACHE_MS,
  type ChartDeps,
  type ChartEntry,
  type ChartShow,
  TOP_CHART,
  genreUrl,
  getJson,
  joinFeeds,
  lookupUrl,
  parseCategoryChart,
  parseLookup,
  parseSavedChart,
  parseTopChart,
  topUrl,
} from "./charts"

/** How many lists are fetched together. 3 lists of 50 make 150 ids, under Apple's 200. */
export const GROUP_SIZE = 3

/** What `onList` hears about one list. */
export type ChartListUpdate =
  | { status: "kept"; shows: ChartShow[]; fresh: boolean }
  | { status: "loaded"; shows: ChartShow[] }
  /** The fetch failed; `shows` is the old kept copy, or null when nothing is kept. */
  | { status: "failed"; shows: ChartShow[] | null }

export type OnList = (id: string, update: ChartListUpdate) => void

/** The kept copy of one list and whether it is under a day old, or null when none is kept. */
export async function keptChart(
  id: string,
  deps: ChartDeps,
): Promise<{ shows: ChartShow[]; fresh: boolean } | null> {
  const now = deps.now ?? Date.now
  const kept = await deps.cacheGet(`chart:${id}`).catch(() => null)
  if (!kept) return null
  const shows = parseSavedChart(kept.value)
  if (!shows) return null
  return { shows, fresh: now() - kept.savedAt < CACHE_MS }
}

type Settled = ChartListUpdate & { status: "loaded" | "failed" }

type Pending = {
  id: string
  old: ChartShow[] | null
  entries?: ChartEntry[]
}

// One promise per list being fetched, so a second caller waits instead of fetching again.
const inFlight = new Map<string, Promise<Settled>>()

async function fetchEntries(
  id: string,
  deps: ChartDeps,
): Promise<ChartEntry[]> {
  const fetchFn = deps.fetchFn ?? fetch
  if (id === TOP_CHART) return parseTopChart(await getJson(topUrl(), fetchFn))
  return parseCategoryChart(await getJson(genreUrl(id), fetchFn))
}

/** Fetches one group: the feeds together, then a single lookup, then saves each list. */
async function loadGroup(
  group: Pending[],
  deps: ChartDeps,
): Promise<Map<string, Settled>> {
  const results = new Map<string, Settled>()
  const failed = (p: Pending): Settled => ({ status: "failed", shows: p.old })

  await Promise.all(
    group.map(async (p) => {
      try {
        p.entries = await fetchEntries(p.id, deps)
      } catch {
        results.set(p.id, failed(p))
      }
    }),
  )

  const live = group.filter(
    (p) => p.entries !== undefined && !results.has(p.id),
  )
  // Links already known from the kept copy don't need the lookup.
  const known = new Map<string, string>()
  const unknown = new Set<string>()
  for (const p of live) {
    const own = new Map((p.old ?? []).map((s) => [s.appleId, s.feedUrl]))
    for (const entry of p.entries ?? []) {
      const feed = own.get(entry.appleId)
      if (feed) known.set(entry.appleId, feed)
      else unknown.add(entry.appleId)
    }
  }

  let feeds = known
  if (unknown.size > 0) {
    try {
      const fetchFn = deps.fetchFn ?? fetch
      const found = parseLookup(await getJson(lookupUrl([...unknown]), fetchFn))
      feeds = new Map([...known, ...found])
    } catch {
      for (const p of live) results.set(p.id, failed(p))
      return results
    }
  }

  for (const p of live) {
    const shows = joinFeeds(p.entries ?? [], feeds)
    if (shows.length > 0) {
      await deps
        .cachePut(`chart:${p.id}`, JSON.stringify(shows))
        .catch(() => {})
    }
    results.set(p.id, { status: "loaded", shows })
  }
  return results
}

/**
 * Loads many lists. First every kept list is reported at once (fresh or not). Then the
 * missing and old ones are fetched in groups of three; each reports "loaded" or "failed"
 * as its group ends. One failing list never stops the others. Resolves when all are done.
 */
export async function loadChartGroups(
  ids: string[],
  deps: ChartDeps,
  onList: OnList,
): Promise<void> {
  const unique = [...new Set(ids)]
  const kept = await Promise.all(unique.map((id) => keptChart(id, deps)))

  const stale: Pending[] = []
  unique.forEach((id, i) => {
    const copy = kept[i] ?? null
    if (copy) onList(id, { status: "kept", ...copy })
    if (!copy?.fresh) stale.push({ id, old: copy?.shows ?? null })
  })

  // Claim the lists nobody is fetching, all at once, so a second caller sees them.
  const resolvers = new Map<string, (settled: Settled) => void>()
  const waiting: Promise<void>[] = []
  const own: Pending[] = []
  for (const p of stale) {
    const existing = inFlight.get(p.id)
    if (existing) {
      waiting.push(existing.then((settled) => onList(p.id, settled)))
      continue
    }
    inFlight.set(
      p.id,
      new Promise<Settled>((resolve) => resolvers.set(p.id, resolve)),
    )
    own.push(p)
  }

  for (let i = 0; i < own.length; i += GROUP_SIZE) {
    const group = own.slice(i, i + GROUP_SIZE)
    let results: Map<string, Settled>
    try {
      results = await loadGroup(group, deps)
    } catch {
      results = new Map()
    }
    for (const p of group) {
      const settled = results.get(p.id) ?? { status: "failed", shows: p.old }
      inFlight.delete(p.id)
      resolvers.get(p.id)?.(settled)
      onList(p.id, settled)
    }
  }
  await Promise.all(waiting)
}

/** What a page knows about one list: loading, ready to draw, or missing (draw nothing). */
export type ListState =
  | { status: "loading" }
  | { status: "ready"; shows: ChartShow[] }
  | { status: "missing" }

/**
 * Folds one report from `loadChartGroups` into a list's state. Shows already on screen are
 * never taken away: a failure keeps them, and so does an empty answer. A list with nothing
 * to draw after a failure or an empty answer is missing.
 */
export function applyListEvent(
  state: ListState,
  event: ChartListUpdate,
): ListState {
  const shows = event.shows
  if (shows && shows.length > 0) return { status: "ready", shows }
  return state.status === "ready" ? state : { status: "missing" }
}
