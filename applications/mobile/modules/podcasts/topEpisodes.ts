// LOFI-FORK: the podcasts section's top episodes chart (see FORK.md).
//
// Apple's episode chart names each episode by its own id and the address of its page, which
// ends in the show's id. Apple's lookup knows no episode ids, so the show ids go to the usual
// lookup in one call, and each episode gets its show's feed link. There is no guid or audio
// address, so a row opens the show's preview and the preview finds the episode by its title.
import {
  CACHE_MS,
  CHART_COUNTRY,
  type ChartDeps,
  getJson,
  lookupUrl,
} from "./charts"

/** The chart's key in the cache table and in a page's list of lists. */
export const EPISODES_CHART = "top-episodes"

/** How many episodes the shelf keeps (ten pages of three). */
export const EPISODE_COUNT = 30

/** Apple's episode chart (the address with "episode" in the singular answers 404). */
export const episodesUrl = () =>
  `https://rss.marketingtools.apple.com/api/v2/${CHART_COUNTRY}/podcasts/top/50/podcast-episodes.json`

/** A chart episode before its feed link is known. `showName` is the publisher until joined. */
export type EpisodeEntry = {
  episodeId: string
  title: string
  showId: string
  showName: string
  imageUrl: string | null
}

/** A chart episode that can open its show's preview. */
export type ChartEpisode = EpisodeEntry & { feedUrl: string }

/** What the lookup knows of a show. */
export type ShowInfo = {
  feedUrl: string
  name: string
  imageUrl: string | null
}

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null
}

function text(value: unknown): string {
  if (typeof value === "number") return String(value)
  return typeof value === "string" ? value.trim() : ""
}

/** The chart in rank order. Entries with no id, title or show id in their address are skipped. */
export function parseTopEpisodes(json: unknown): EpisodeEntry[] {
  const results = record(record(json)?.["feed"])?.["results"]
  if (!Array.isArray(results)) return []
  const seen = new Set<string>()
  const entries: EpisodeEntry[] = []
  for (const result of results as unknown[]) {
    const fields = record(result)
    if (!fields) continue
    const episodeId = text(fields["id"])
    const title = text(fields["name"])
    const showId = /\/id(\d+)(?:[?#]|$)/.exec(text(fields["url"]))?.[1] ?? ""
    if (episodeId === "" || title === "" || showId === "") continue
    if (seen.has(episodeId)) continue
    seen.add(episodeId)
    entries.push({
      episodeId,
      title,
      showId,
      showName: text(fields["artistName"]),
      imageUrl: text(fields["artworkUrl100"]) || null,
    })
  }
  return entries
}

/** The lookup as show id to what it knows. Shows without a feed link are left out. */
export function parseShowLookup(json: unknown): Map<string, ShowInfo> {
  const shows = new Map<string, ShowInfo>()
  const results = record(json)?.["results"]
  if (!Array.isArray(results)) return shows
  for (const result of results as unknown[]) {
    const fields = record(result)
    if (!fields) continue
    const id = text(fields["collectionId"] ?? fields["trackId"])
    const feedUrl = text(fields["feedUrl"])
    if (id === "" || feedUrl === "") continue
    shows.set(id, {
      feedUrl,
      name: text(fields["collectionName"]),
      imageUrl: text(fields["artworkUrl600"]) || null,
    })
  }
  return shows
}

/** The chart with each show's feed link and name; episodes of unknown shows are dropped. */
export function joinEpisodes(
  entries: EpisodeEntry[],
  shows: Map<string, ShowInfo>,
): ChartEpisode[] {
  const joined: ChartEpisode[] = []
  for (const entry of entries) {
    const show = shows.get(entry.showId)
    if (!show) continue
    joined.push({
      ...entry,
      showName: show.name || entry.showName,
      imageUrl: entry.imageUrl ?? show.imageUrl,
      feedUrl: show.feedUrl,
    })
  }
  return joined.slice(0, EPISODE_COUNT)
}

/** Reads a saved list. Anything that is not a list of whole episodes gives null. */
export function parseSavedEpisodes(value: string): ChartEpisode[] | null {
  let parsed: unknown
  try {
    parsed = JSON.parse(value)
  } catch {
    return null
  }
  if (!Array.isArray(parsed)) return null
  const episodes: ChartEpisode[] = []
  for (const item of parsed as unknown[]) {
    const f = record(item)
    const episodeId = text(f?.["episodeId"])
    const title = text(f?.["title"])
    const feedUrl = text(f?.["feedUrl"])
    if (!f || episodeId === "" || title === "" || feedUrl === "") return null
    episodes.push({
      episodeId,
      title,
      showId: text(f["showId"]),
      showName: text(f["showName"]),
      imageUrl: text(f["imageUrl"]) || null,
      feedUrl,
    })
  }
  return episodes
}

/** What `loadTopEpisodes` reports, as `loadChartGroups` does for the show lists. */
export type EpisodesUpdate =
  | { status: "kept"; episodes: ChartEpisode[]; fresh: boolean }
  | { status: "loaded"; episodes: ChartEpisode[] }
  | { status: "failed"; episodes: ChartEpisode[] | null }

type Settled = EpisodesUpdate & { status: "loaded" | "failed" }

// The fetch being made, so a second caller waits for it instead of fetching again.
let inFlight: Promise<Settled> | null = null

async function fetchEpisodes(
  old: ChartEpisode[] | null,
  deps: ChartDeps,
): Promise<Settled> {
  const fetchFn = deps.fetchFn ?? fetch
  try {
    const entries = parseTopEpisodes(await getJson(episodesUrl(), fetchFn))
    if (entries.length === 0) return { status: "loaded", episodes: [] }
    const ids = [...new Set(entries.map((e) => e.showId))]
    const shows = parseShowLookup(await getJson(lookupUrl(ids), fetchFn))
    const episodes = joinEpisodes(entries, shows)
    if (episodes.length > 0) {
      await deps
        .cachePut(`chart:${EPISODES_CHART}`, JSON.stringify(episodes))
        .catch(() => {})
    }
    return { status: "loaded", episodes }
  } catch {
    return { status: "failed", episodes: old }
  }
}

/**
 * Loads the episode chart: a kept copy is reported at once (fresh for a day), an old or
 * missing one is fetched (the chart, then one lookup of the show ids). A failed fetch keeps
 * the old copy. Resolves when done; it never throws.
 */
export async function loadTopEpisodes(
  deps: ChartDeps,
  onUpdate: (update: EpisodesUpdate) => void,
): Promise<void> {
  const now = deps.now ?? Date.now
  const key = `chart:${EPISODES_CHART}`
  const kept = await deps.cacheGet(key).catch(() => null)
  const old = kept ? parseSavedEpisodes(kept.value) : null
  const fresh = !!kept && now() - kept.savedAt < CACHE_MS
  if (old) onUpdate({ status: "kept", episodes: old, fresh })
  if (old && fresh) return

  if (!inFlight) {
    const pending = fetchEpisodes(old, deps).finally(() => {
      inFlight = null
    })
    inFlight = pending
  }
  onUpdate(await inFlight)
}

/** What a page knows about the episode list. */
export type EpisodesState =
  | { status: "loading" }
  | { status: "ready"; episodes: ChartEpisode[] }
  | { status: "missing" }

/** Folds a report into the state; episodes already drawn are never taken away. */
export function applyEpisodesEvent(
  state: EpisodesState,
  event: EpisodesUpdate,
): EpisodesState {
  if (event.episodes && event.episodes.length > 0) {
    return { status: "ready", episodes: event.episodes }
  }
  return state.status === "ready" ? state : { status: "missing" }
}
