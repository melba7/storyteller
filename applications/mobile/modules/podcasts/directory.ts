// LOFI-FORK: the podcasts section's directory search (see FORK.md).

/** A show found in Apple's free podcast directory. */
export type DirectoryShow = {
  id: string
  title: string
  author: string
  feedUrl: string
  imageUrl: string | null
}

const SEARCH_URL =
  "https://itunes.apple.com/search?media=podcast&entity=podcast&limit=25&term="

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : ""
}

/** The largest `artworkUrlNN` the result has (the number is the size in pixels). */
function largestArtwork(result: Record<string, unknown>): string | null {
  let best: { size: number; url: string } | null = null
  for (const [key, value] of Object.entries(result)) {
    const match = /^artworkUrl(\d+)$/.exec(key)
    const url = text(value)
    if (!match || url === "") continue
    const size = Number(match[1])
    if (!best || size > best.size) best = { size, url }
  }
  return best?.url ?? null
}

/** Reads the directory's JSON answer. Results without a feed address are dropped. */
export function parseDirectoryResults(json: unknown): DirectoryShow[] {
  if (typeof json !== "object" || json === null) return []
  const results = (json as { results?: unknown }).results
  if (!Array.isArray(results)) return []

  const shows: DirectoryShow[] = []
  for (const result of results as unknown[]) {
    if (typeof result !== "object" || result === null) continue
    const fields = result as Record<string, unknown>
    const feedUrl = text(fields["feedUrl"])
    if (feedUrl === "") continue
    const id = fields["collectionId"] ?? fields["trackId"]
    shows.push({
      id:
        typeof id === "number" || typeof id === "string" ? String(id) : feedUrl,
      title:
        text(fields["collectionName"]) || text(fields["trackName"]) || feedUrl,
      author: text(fields["artistName"]),
      feedUrl,
      imageUrl: largestArtwork(fields),
    })
  }
  return shows
}

type FetchFn = (url: string) => Promise<Response>

async function directoryJson(url: string, fetchFn: FetchFn): Promise<unknown> {
  let response: Response
  try {
    response = await fetchFn(url)
  } catch {
    throw new Error(
      "Couldn't reach Apple's podcast directory. Check your connection.",
    )
  }
  if (!response.ok) {
    throw new Error(
      `Apple's podcast directory answered with status ${response.status}.`,
    )
  }
  try {
    return await response.json()
  } catch {
    throw new Error(
      "Apple's podcast directory sent an answer that couldn't be read.",
    )
  }
}

/** Searches Apple's podcast directory by name. */
export async function searchDirectory(
  term: string,
  fetchFn: FetchFn = fetch,
): Promise<DirectoryShow[]> {
  const trimmed = term.trim()
  if (trimmed === "") return []
  return parseDirectoryResults(
    await directoryJson(SEARCH_URL + encodeURIComponent(trimmed), fetchFn),
  )
}

// MARK: Episodes

/** An episode found in Apple's directory, with the feed it belongs to. */
export type DirectoryEpisode = {
  id: string
  title: string
  showTitle: string
  /** Milliseconds since 1970, or null when Apple gives no date. */
  publishedAt: number | null
  durationSeconds: number | null
  feedUrl: string
  /** The feed's own id for the episode, when Apple gives it. */
  guid: string | null
  /** The audio address, when Apple gives it. */
  audioUrl: string | null
  imageUrl: string | null
}

const EPISODE_SEARCH_URL =
  "https://itunes.apple.com/search?media=podcast&entity=podcastEpisode&limit=50&term="

/** Reads Apple's episode answer. Results without a title or a feed address are dropped. */
export function parseEpisodeResults(json: unknown): DirectoryEpisode[] {
  if (typeof json !== "object" || json === null) return []
  const results = (json as { results?: unknown }).results
  if (!Array.isArray(results)) return []

  const episodes: DirectoryEpisode[] = []
  for (const result of results as unknown[]) {
    if (typeof result !== "object" || result === null) continue
    const fields = result as Record<string, unknown>
    const feedUrl = text(fields["feedUrl"])
    const title = text(fields["trackName"])
    if (feedUrl === "" || title === "") continue
    const id = fields["trackId"]
    const released = Date.parse(text(fields["releaseDate"]))
    const millis = fields["trackTimeMillis"]
    episodes.push({
      id:
        typeof id === "number" || typeof id === "string"
          ? String(id)
          : `${feedUrl}#${title}`,
      title,
      showTitle: text(fields["collectionName"]),
      publishedAt: Number.isNaN(released) ? null : released,
      durationSeconds:
        typeof millis === "number" && millis > 0 ? millis / 1000 : null,
      feedUrl,
      guid: text(fields["episodeGuid"]) || null,
      audioUrl: text(fields["episodeUrl"]) || null,
      imageUrl: largestArtwork(fields),
    })
  }
  return episodes
}

/** Searches the episodes of all podcasts in Apple's directory. */
export async function searchDirectoryEpisodes(
  term: string,
  fetchFn: FetchFn = fetch,
): Promise<DirectoryEpisode[]> {
  const trimmed = term.trim()
  if (trimmed === "") return []
  return parseEpisodeResults(
    await directoryJson(
      EPISODE_SEARCH_URL + encodeURIComponent(trimmed),
      fetchFn,
    ),
  )
}
