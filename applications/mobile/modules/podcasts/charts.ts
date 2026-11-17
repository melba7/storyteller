// LOFI-FORK: the podcasts section's charts from Apple's free addresses (see FORK.md).
//
// Apple's top charts list shows by Apple id, not by feed, so one lookup call turns the ids
// into feed links. Answers are kept for a day in the library's cache table. The addresses
// live here and nowhere else, in case Apple changes them.

/** A chart show that has a feed link, ready to open as a preview. */
export type ChartShow = {
  /** Apple's id for the show. */
  appleId: string
  title: string
  author: string
  feedUrl: string
  imageUrl: string | null
}

/** A chart entry before its feed link is known. */
type ChartEntry = Omit<ChartShow, "feedUrl">

/** A category with Apple's genre number for its chart. */
export type ChartCategory = { id: string; name: string }

/** The overall chart's key for `loadChart`. */
export const TOP_CHART = "top"

/** Apple's main podcast genres, named as feeds name their `itunes:category`. */
export const CHART_CATEGORIES: readonly ChartCategory[] = [
  { id: "1301", name: "Arts" },
  { id: "1321", name: "Business" },
  { id: "1303", name: "Comedy" },
  { id: "1304", name: "Education" },
  { id: "1483", name: "Fiction" },
  { id: "1512", name: "Health & Fitness" },
  { id: "1487", name: "History" },
  { id: "1305", name: "Kids & Family" },
  { id: "1502", name: "Leisure" },
  { id: "1310", name: "Music" },
  { id: "1489", name: "News" },
  { id: "1314", name: "Religion & Spirituality" },
  { id: "1533", name: "Science" },
  { id: "1324", name: "Society & Culture" },
  { id: "1545", name: "Sports" },
  { id: "1318", name: "Technology" },
  { id: "1488", name: "True Crime" },
  { id: "1309", name: "TV & Film" },
]

const TOP_URL =
  "https://rss.marketingtools.apple.com/api/v2/us/podcasts/top/50/podcasts.json"
const GENRE_URL = (id: string) =>
  `https://itunes.apple.com/us/rss/toppodcasts/limit=50/genre=${id}/json`
const LOOKUP_URL = "https://itunes.apple.com/lookup?id="

/** A chart answer and its lookup are kept this long. */
export const CACHE_MS = 24 * 60 * 60 * 1000

// MARK: Reading Apple's answers

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : ""
}

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null
}

function idText(value: unknown): string {
  return typeof value === "number" ? String(value) : text(value)
}

function withoutRepeats(entries: ChartEntry[]): ChartEntry[] {
  const seen = new Set<string>()
  return entries.filter((entry) => {
    if (seen.has(entry.appleId)) return false
    seen.add(entry.appleId)
    return true
  })
}

/** The overall chart (`feed.results`). Entries with no id or name are dropped. */
export function parseTopChart(json: unknown): ChartEntry[] {
  const results = record(record(json)?.["feed"])?.["results"]
  if (!Array.isArray(results)) return []
  const entries: ChartEntry[] = []
  for (const result of results as unknown[]) {
    const fields = record(result)
    if (!fields) continue
    const appleId = idText(fields["id"])
    const title = text(fields["name"])
    if (appleId === "" || title === "") continue
    entries.push({
      appleId,
      title,
      author: text(fields["artistName"]),
      imageUrl: text(fields["artworkUrl100"]) || null,
    })
  }
  return withoutRepeats(entries)
}

/** The largest picture of a category chart entry (`im:image` has several sizes). */
function largestImage(images: unknown): string | null {
  if (!Array.isArray(images)) return null
  let best: { height: number; url: string } | null = null
  for (const image of images as unknown[]) {
    const fields = record(image)
    const url = text(fields?.["label"])
    const height = Number(record(fields?.["attributes"])?.["height"])
    if (url === "") continue
    const size = Number.isFinite(height) ? height : 0
    if (!best || size > best.height) best = { height: size, url }
  }
  return best?.url ?? null
}

/** A category's chart (`feed.entry`, one object instead of a list when there is one show). */
export function parseCategoryChart(json: unknown): ChartEntry[] {
  const raw = record(record(json)?.["feed"])?.["entry"]
  const list: unknown[] = Array.isArray(raw) ? raw : raw ? [raw] : []
  const entries: ChartEntry[] = []
  for (const item of list) {
    const fields = record(item)
    if (!fields) continue
    const appleId = text(
      record(record(fields["id"])?.["attributes"])?.["im:id"],
    )
    const title = text(record(fields["im:name"])?.["label"])
    if (appleId === "" || title === "") continue
    entries.push({
      appleId,
      title,
      author: text(record(fields["im:artist"])?.["label"]),
      imageUrl: largestImage(fields["im:image"]),
    })
  }
  return withoutRepeats(entries)
}

/** The lookup answer as Apple id to feed link. Results without a feed link are left out. */
export function parseLookup(json: unknown): Map<string, string> {
  const feeds = new Map<string, string>()
  const results = record(json)?.["results"]
  if (!Array.isArray(results)) return feeds
  for (const result of results as unknown[]) {
    const fields = record(result)
    if (!fields) continue
    const appleId = idText(fields["collectionId"] ?? fields["trackId"])
    const feedUrl = text(fields["feedUrl"])
    if (appleId !== "" && feedUrl !== "") feeds.set(appleId, feedUrl)
  }
  return feeds
}

/** The chart in order, each entry with its feed link. Entries without a link are dropped. */
export function joinFeeds(
  entries: ChartEntry[],
  feeds: Map<string, string>,
): ChartShow[] {
  const shows: ChartShow[] = []
  for (const entry of entries) {
    const feedUrl = feeds.get(entry.appleId)
    if (feedUrl) shows.push({ ...entry, feedUrl })
  }
  return shows
}

/** Reads a saved chart (JSON of ChartShow list). Anything else gives null. */
export function parseSavedChart(value: string): ChartShow[] | null {
  let parsed: unknown
  try {
    parsed = JSON.parse(value)
  } catch {
    return null
  }
  if (!Array.isArray(parsed)) return null
  const shows: ChartShow[] = []
  for (const item of parsed as unknown[]) {
    const fields = record(item)
    const appleId = text(fields?.["appleId"])
    const feedUrl = text(fields?.["feedUrl"])
    const title = text(fields?.["title"])
    if (!fields || appleId === "" || feedUrl === "" || title === "") return null
    shows.push({
      appleId,
      title,
      author: text(fields["author"]),
      feedUrl,
      imageUrl: text(fields["imageUrl"]) || null,
    })
  }
  return shows
}

// MARK: Fetching

type FetchFn = (url: string) => Promise<Response>

async function getJson(url: string, fetchFn: FetchFn): Promise<unknown> {
  let response: Response
  try {
    response = await fetchFn(url)
  } catch {
    throw new Error("Couldn't reach Apple's charts. Check your connection.")
  }
  if (!response.ok) {
    throw new Error(`Apple's charts answered with status ${response.status}.`)
  }
  try {
    return await response.json()
  } catch {
    throw new Error("Apple's charts sent an answer that couldn't be read.")
  }
}

export interface ChartDeps {
  fetchFn?: FetchFn
  cacheGet(key: string): Promise<{ value: string; savedAt: number } | null>
  cachePut(key: string, value: string): Promise<void>
  now?: () => number
}

/**
 * One chart with feed links: `TOP_CHART` or a category's genre id. Kept for a day; a kept
 * answer that can't be read, or that is too old, is fetched again. A cache that fails
 * does not stop the chart.
 */
export async function loadChart(
  chart: string,
  deps: ChartDeps,
): Promise<ChartShow[]> {
  const fetchFn = deps.fetchFn ?? fetch
  const now = deps.now ?? Date.now
  const key = `chart:${chart}`

  const kept = await deps.cacheGet(key).catch(() => null)
  if (kept && now() - kept.savedAt < CACHE_MS) {
    const shows = parseSavedChart(kept.value)
    if (shows) return shows
  }

  const isTop = chart === TOP_CHART
  const answer = await getJson(isTop ? TOP_URL : GENRE_URL(chart), fetchFn)
  const entries = isTop ? parseTopChart(answer) : parseCategoryChart(answer)
  if (entries.length === 0) return []
  const ids = entries.map((entry) => entry.appleId).join(",")
  const feeds = parseLookup(await getJson(LOOKUP_URL + ids, fetchFn))
  const shows = joinFeeds(entries, feeds)
  if (shows.length > 0) {
    await deps.cachePut(key, JSON.stringify(shows)).catch(() => {})
  }
  return shows
}
