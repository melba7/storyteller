// LOFI-FORK: the podcasts section's episode row and show page rules (see FORK.md).
//
// Pure functions for Apple's look: the grey date line of an episode row, the short length in
// its capsule, plain text from HTML notes, how often a show publishes, the line under a show's
// description, and the show page's filter.
import { type StoredEpisode } from "./library"

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

const MINUTE = 60_000
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR

/**
 * An episode's date the way Apple writes it: "12m ago" and "5h ago" for the first day, then
 * "Oct 6", with the year ("Oct 6, 2023") when it is not this year's. Empty with no date. A date
 * in the future reads as just that date.
 */
export function dateWords(publishedAt: number | null, now: number): string {
  if (publishedAt === null) return ""
  const date = new Date(publishedAt)
  if (Number.isNaN(date.getTime())) return ""
  const age = now - publishedAt
  if (age >= 0 && age < DAY) {
    if (age < HOUR) return `${Math.max(1, Math.floor(age / MINUTE))}m ago`
    return `${Math.floor(age / HOUR)}h ago`
  }
  const text = `${MONTHS[date.getMonth()]} ${date.getDate()}`
  return date.getFullYear() === new Date(now).getFullYear()
    ? text
    : `${text}, ${date.getFullYear()}`
}

/** "S2 E5", "S2", "E5" or empty, from the feed's season and episode numbers. */
export function seasonEpisode(
  season: number | null,
  number: number | null,
): string {
  return [
    season === null ? "" : `S${season}`,
    number === null ? "" : `E${number}`,
  ]
    .filter((part) => part !== "")
    .join(" ")
}

/** The parts of a row's grey line: date, season and episode, "Played". */
export function dateLineParts(
  episode: Pick<StoredEpisode, "publishedAt" | "season" | "number" | "played">,
  now: number,
): string[] {
  return [
    dateWords(episode.publishedAt, now),
    seasonEpisode(episode.season, episode.number),
    episode.played ? "Played" : "",
  ].filter((part) => part !== "")
}

/** "24m", "1h 5m", "2h": a length in the capsule's short form. Empty when unknown. */
export function shortLength(seconds: number | null): string {
  if (seconds === null || !Number.isFinite(seconds) || seconds <= 0) return ""
  const minutes = Math.max(1, Math.round(seconds / 60))
  const hours = Math.floor(minutes / 60)
  const rest = minutes % 60
  if (hours === 0) return `${minutes}m`
  return rest === 0 ? `${hours}h` : `${hours}h ${rest}m`
}

/**
 * What the capsule on a row says: the length, the time left for an episode that was started
 * (with its progress, 0 to 1) or "Played".
 */
export function capsuleLook(
  episode: Pick<
    StoredEpisode,
    "durationSeconds" | "positionSeconds" | "played"
  >,
): { label: string; progress: number | null; spoken: string } {
  if (episode.played)
    return { label: "Played", progress: null, spoken: "Played" }
  const { durationSeconds: duration, positionSeconds: position } = episode
  if (
    duration !== null &&
    duration > 0 &&
    position > 0 &&
    position < duration
  ) {
    const label = shortLength(duration - position)
    return {
      label,
      progress: Math.min(1, position / duration),
      spoken: `${label} left`,
    }
  }
  const label = shortLength(duration)
  return { label, progress: null, spoken: label }
}

const ENTITIES: Record<string, string> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  nbsp: " ",
  rsquo: "’",
  lsquo: "‘",
  rdquo: "”",
  ldquo: "“",
  ndash: "–",
  mdash: "—",
  hellip: "…",
}

/** Plain text from HTML show notes: tags dropped, entities read, white space made single. */
export function stripHtml(html: string): string {
  return html
    .replace(/<(script|style)[\s\S]*?<\/\1>/gi, " ")
    .replace(/<\s*(br|\/p|\/div|\/li|\/h[1-6])\s*\/?>/gi, " ")
    .replace(/<[^>]*>/g, "")
    .replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (whole, name: string) => {
      if (name.startsWith("#")) {
        const code =
          name[1] === "x" || name[1] === "X"
            ? parseInt(name.slice(2), 16)
            : parseInt(name.slice(1), 10)
        return Number.isFinite(code) && code > 0 && code <= 0x10ffff
          ? String.fromCodePoint(code)
          : whole
      }
      return ENTITIES[name.toLowerCase()] ?? whole
    })
    .replace(/\s+/g, " ")
    .trim()
}

/**
 * How often a show publishes, from its episode dates: "Daily", "Every few days", "Weekly",
 * "Biweekly" or "Monthly", by the middle gap between its newest episodes. Empty with fewer than
 * three dates, a show that has gone quiet (nothing for six months) or an uneven one.
 */
export function updateFrequency(
  dates: readonly (number | null)[],
  now: number,
): string {
  const sorted = dates
    .filter((date): date is number => date !== null && Number.isFinite(date))
    .sort((a, b) => b - a)
  if (sorted.length < 3) return ""
  if (now - (sorted[0] ?? 0) > 180 * DAY) return ""
  const gaps: number[] = []
  for (let i = 0; i < Math.min(sorted.length - 1, 10); i++) {
    gaps.push(((sorted[i] ?? 0) - (sorted[i + 1] ?? 0)) / DAY)
  }
  gaps.sort((a, b) => a - b)
  const middle = gaps[Math.floor(gaps.length / 2)] ?? 0
  if (middle <= 1.5) return "Daily"
  if (middle <= 4) return "Every few days"
  if (middle <= 9) return "Weekly"
  if (middle <= 18) return "Biweekly"
  if (middle <= 45) return "Monthly"
  return ""
}

/** The tinted line under a show's description: first category, how often, author. */
export function showCaption(
  categories: readonly string[],
  frequency: string,
  author: string | null,
): string {
  const category =
    categories.find((name) => !name.includes("›")) ?? categories[0] ?? ""
  return [category, frequency, author ?? ""]
    .filter((part) => part !== "")
    .join(" · ")
}

// MARK: The show page's filter

export type EpisodeFilter =
  | "all"
  | "unplayed"
  | "downloaded"
  | "saved"
  | "archived"

export const EPISODE_FILTERS: { id: EpisodeFilter; title: string }[] = [
  { id: "unplayed", title: "Unplayed" },
  { id: "all", title: "All Episodes" },
  { id: "downloaded", title: "Downloaded" },
  { id: "saved", title: "Saved" },
  { id: "archived", title: "Archived" },
]

/** The episodes a filter lets through. `downloaded` holds the ids of finished downloads. */
export function filterEpisodes(
  episodes: readonly StoredEpisode[],
  filter: EpisodeFilter,
  downloaded: ReadonlySet<string>,
): StoredEpisode[] {
  switch (filter) {
    case "all":
      return [...episodes]
    case "unplayed":
      return episodes.filter((episode) => !episode.played)
    case "downloaded":
      return episodes.filter((episode) => downloaded.has(episode.id))
    case "saved":
      return episodes.filter((episode) => episode.starredAt !== null)
    case "archived":
      return episodes.filter((episode) => episode.archived)
  }
}

// MARK: The show page's play button

/**
 * What the show page's white capsule plays: the episode of the show that was started and not
 * finished (the one played last), as "resume"; else the newest one that isn't archived, as
 * "latest". Null for a show with no episodes.
 */
export function showPlayTarget(
  episodes: readonly StoredEpisode[],
): { episode: StoredEpisode; kind: "resume" | "latest" } | null {
  let resume: StoredEpisode | null = null
  for (const episode of episodes) {
    if (episode.played || !(episode.positionSeconds > 0)) continue
    if ((episode.lastPlayedAt ?? 0) >= (resume?.lastPlayedAt ?? 0)) {
      resume = episode
    }
  }
  if (resume) return { episode: resume, kind: "resume" }
  let latest: StoredEpisode | null = null
  for (const episode of episodes) {
    if (episode.archived) continue
    if (
      (episode.publishedAt ?? -Infinity) > (latest?.publishedAt ?? -Infinity) ||
      !latest
    ) {
      latest = episode
    }
  }
  return latest ? { episode: latest, kind: "latest" } : null
}
