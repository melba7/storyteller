// LOFI-FORK: the podcasts section's library rules (see FORK.md).
//
// Pure functions: what a show and an episode are, merging a
// refreshed feed into the stored episodes, sorting, and how dates and lengths read.
// Nothing here touches the database (db.ts does) or the screen.

export type Show = {
  id: string
  feedUrl: string
  title: string
  author: string | null
  description: string
  imageUrl: string | null
  link: string | null
  language: string | null
  /** Milliseconds since 1970. */
  addedAt: number
  refreshedAt: number
}

/** An episode as the feed gives it (what the Swift side returns). */
export type FetchedEpisode = {
  guid: string
  title: string
  /** Milliseconds since 1970, or null when the feed has no date. */
  publishedAt: number | null
  durationSeconds: number | null
  notes: string
  audioUrl: string
  audioType: string
  audioBytes: number | null
  imageUrl: string | null
  season: number | null
  number: number | null
}

export type StoredEpisode = FetchedEpisode & { id: string; showId: string }

// MARK: Refreshing

const FETCHED_KEYS: (keyof FetchedEpisode)[] = [
  "title",
  "publishedAt",
  "durationSeconds",
  "notes",
  "audioUrl",
  "audioType",
  "audioBytes",
  "imageUrl",
  "season",
  "number",
]

function unchanged(stored: StoredEpisode, fetched: FetchedEpisode): boolean {
  return FETCHED_KEYS.every((key) => stored[key] === fetched[key])
}

/**
 * Which fetched episodes to insert (new guids) and which stored ones to update (same
 * guid, something changed). A guid the feed repeats counts once, the first time. An
 * episode that left the feed is never deleted.
 */
export function mergeEpisodes(
  existing: StoredEpisode[],
  fetched: FetchedEpisode[],
): {
  insert: FetchedEpisode[]
  update: { id: string; episode: FetchedEpisode }[]
} {
  const byGuid = new Map(existing.map((episode) => [episode.guid, episode]))
  const seen = new Set<string>()
  const insert: FetchedEpisode[] = []
  const update: { id: string; episode: FetchedEpisode }[] = []
  for (const episode of fetched) {
    if (seen.has(episode.guid)) continue
    seen.add(episode.guid)
    const stored = byGuid.get(episode.guid)
    if (!stored) insert.push(episode)
    else if (!unchanged(stored, episode))
      update.push({ id: stored.id, episode })
  }
  return { insert, update }
}

// MARK: Sorting and reading

/** Newest first, undated last. Episodes with the same date keep their order. */
export function sortEpisodes<T extends { publishedAt: number | null }>(
  episodes: T[],
): T[] {
  return episodes
    .map((episode, index) => ({ episode, index }))
    .sort((a, b) => {
      const left = a.episode.publishedAt
      const right = b.episode.publishedAt
      if (left === right) return a.index - b.index
      if (left === null) return 1
      if (right === null) return -1
      return right - left
    })
    .map(({ episode }) => episode)
}

const MONTHS = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
]

/** "2 Jan 2023", in the phone's time zone. Empty when there is no date. */
export function formatEpisodeDate(publishedAt: number | null): string {
  if (publishedAt === null) return ""
  const date = new Date(publishedAt)
  if (Number.isNaN(date.getTime())) return ""
  return `${date.getDate()} ${MONTHS[date.getMonth()]} ${date.getFullYear()}`
}

/** "42 min", "1 h 5 min", "2 h". Empty when the length is unknown. */
export function formatDuration(seconds: number | null): string {
  if (seconds === null || !Number.isFinite(seconds) || seconds <= 0) return ""
  const minutes = Math.max(1, Math.round(seconds / 60))
  const hours = Math.floor(minutes / 60)
  const rest = minutes % 60
  if (hours === 0) return `${minutes} min`
  return rest === 0 ? `${hours} h` : `${hours} h ${rest} min`
}

// MARK: Database rows

type Row = Record<string, unknown>

function str(value: unknown): string {
  return typeof value === "string" ? value : ""
}

function strOrNull(value: unknown): string | null {
  return typeof value === "string" ? value : null
}

function numOrNull(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null
}

export function showFromRow(row: Row): Show {
  return {
    id: str(row["id"]),
    feedUrl: str(row["feed_url"]),
    title: str(row["title"]),
    author: strOrNull(row["author"]),
    description: str(row["description"]),
    imageUrl: strOrNull(row["image_url"]),
    link: strOrNull(row["link"]),
    language: strOrNull(row["language"]),
    addedAt: numOrNull(row["added_at"]) ?? 0,
    refreshedAt: numOrNull(row["refreshed_at"]) ?? 0,
  }
}

export function episodeFromRow(row: Row): StoredEpisode {
  return {
    id: str(row["id"]),
    showId: str(row["show_id"]),
    guid: str(row["guid"]),
    title: str(row["title"]),
    publishedAt: numOrNull(row["published_at"]),
    durationSeconds: numOrNull(row["duration_seconds"]),
    notes: str(row["notes"]),
    audioUrl: str(row["audio_url"]),
    audioType: str(row["audio_type"]),
    audioBytes: numOrNull(row["audio_bytes"]),
    imageUrl: strOrNull(row["image_url"]),
    season: numOrNull(row["season"]),
    number: numOrNull(row["number"]),
  }
}
