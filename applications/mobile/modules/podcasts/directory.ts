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

/** Searches Apple's podcast directory by name. */
export async function searchDirectory(
  term: string,
  fetchFn: (url: string) => Promise<Response> = fetch,
): Promise<DirectoryShow[]> {
  const trimmed = term.trim()
  if (trimmed === "") return []

  let response: Response
  try {
    response = await fetchFn(SEARCH_URL + encodeURIComponent(trimmed))
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
  let json: unknown
  try {
    json = await response.json()
  } catch {
    throw new Error(
      "Apple's podcast directory sent an answer that couldn't be read.",
    )
  }
  return parseDirectoryResults(json)
}
