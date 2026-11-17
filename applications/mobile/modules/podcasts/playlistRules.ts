// LOFI-FORK: the podcasts section's smart playlists (see FORK.md).
//
// Pure rules: what a smart playlist asks for, how that becomes a database query, how it is
// sorted, what is filtered afterwards (what is on the phone is not in the database), and
// how it reads in words. The database calls are in dbPlaylists.ts.

export type PlayedState = "unplayed" | "inProgress" | "played"
export type Release =
  | "day"
  | "threeDays"
  | "week"
  | "twoWeeks"
  | "month"
  | "any"
export type DownloadedFilter = "any" | "downloaded" | "notDownloaded"
export type PlaylistSort = "newest" | "oldest" | "shortest" | "longest"

export type PlaylistRules = {
  /** The shows to take episodes from; null for every show. */
  showIds: string[] | null
  /** The played states to take; none chosen means any. */
  played: PlayedState[]
  release: Release
  /** Only episodes shorter than this many minutes, or null. */
  shorterThan: number | null
  /** Only episodes longer than this many minutes, or null. */
  longerThan: number | null
  downloaded: DownloadedFilter
  starredOnly: boolean
}

export const DEFAULT_RULES: PlaylistRules = {
  showIds: null,
  played: [],
  release: "any",
  shorterThan: null,
  longerThan: null,
  downloaded: "any",
  starredOnly: false,
}

export const PLAYED_CHOICES: { id: PlayedState; title: string }[] = [
  { id: "unplayed", title: "Unplayed" },
  { id: "inProgress", title: "In progress" },
  { id: "played", title: "Played" },
]

export const RELEASE_CHOICES: { id: Release; title: string }[] = [
  { id: "day", title: "Last 24 hours" },
  { id: "threeDays", title: "Last 3 days" },
  { id: "week", title: "Last week" },
  { id: "twoWeeks", title: "Last 2 weeks" },
  { id: "month", title: "Last month" },
  { id: "any", title: "Any time" },
]

export const DOWNLOADED_CHOICES: { id: DownloadedFilter; title: string }[] = [
  { id: "any", title: "Either" },
  { id: "downloaded", title: "Downloaded" },
  { id: "notDownloaded", title: "Not downloaded" },
]

export const SORT_CHOICES: { id: PlaylistSort; title: string }[] = [
  { id: "newest", title: "Newest first" },
  { id: "oldest", title: "Oldest first" },
  { id: "shortest", title: "Shortest first" },
  { id: "longest", title: "Longest first" },
]

const DAY_MS = 24 * 60 * 60 * 1000
const RELEASE_MS: Record<Exclude<Release, "any">, number> = {
  day: DAY_MS,
  threeDays: 3 * DAY_MS,
  week: 7 * DAY_MS,
  twoWeeks: 14 * DAY_MS,
  month: 30 * DAY_MS,
}

// MARK: Reading and saving

function oneOf<T extends string>(
  value: unknown,
  choices: readonly { id: T }[],
  fallback: T,
): T {
  return choices.find((choice) => choice.id === value)?.id ?? fallback
}

function minutes(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? value
    : null
}

/** The saved rules; a missing, broken or partial value falls back to the defaults. */
export function parseRules(saved: unknown): PlaylistRules {
  let value: unknown = saved
  if (typeof saved === "string") {
    try {
      value = JSON.parse(saved)
    } catch {
      return DEFAULT_RULES
    }
  }
  if (typeof value !== "object" || value === null) return DEFAULT_RULES
  const record = value as Record<string, unknown>
  const showIds = record["showIds"]
  const played = record["played"]
  return {
    showIds: Array.isArray(showIds)
      ? showIds.filter((id): id is string => typeof id === "string")
      : null,
    played: Array.isArray(played)
      ? PLAYED_CHOICES.map((choice) => choice.id).filter((id) =>
          played.includes(id),
        )
      : [],
    release: oneOf(record["release"], RELEASE_CHOICES, "any"),
    shorterThan: minutes(record["shorterThan"]),
    longerThan: minutes(record["longerThan"]),
    downloaded: oneOf(record["downloaded"], DOWNLOADED_CHOICES, "any"),
    starredOnly: record["starredOnly"] === true,
  }
}

export function serializeRules(rules: PlaylistRules): string {
  return JSON.stringify(rules)
}

export function parseSort(value: unknown): PlaylistSort {
  return oneOf(value, SORT_CHOICES, "newest")
}

// MARK: The query

const PLAYED_SQL: Record<PlayedState, string> = {
  unplayed: "(played = 0 AND position_seconds = 0)",
  inProgress: "(played = 0 AND position_seconds > 0)",
  played: "played = 1",
}

/**
 * The conditions of the rules on the episodes table. Archived episodes never match. An
 * episode with no date never matches a release window, and one with no length never matches
 * a length limit. "Downloaded" is not here (see filterDownloaded).
 */
export function rulesWhere(
  rules: PlaylistRules,
  now: number,
): { where: string; params: (string | number)[] } {
  const conditions = ["archived = 0"]
  const params: (string | number)[] = []
  if (rules.showIds !== null) {
    if (rules.showIds.length === 0) conditions.push("0 = 1")
    else {
      conditions.push(`show_id IN (${rules.showIds.map(() => "?").join(", ")})`)
      params.push(...rules.showIds)
    }
  }
  if (rules.played.length > 0 && rules.played.length < PLAYED_CHOICES.length) {
    conditions.push(
      `(${rules.played.map((state) => PLAYED_SQL[state]).join(" OR ")})`,
    )
  }
  if (rules.release !== "any") {
    conditions.push("published_at >= ?")
    params.push(now - RELEASE_MS[rules.release])
  }
  if (rules.shorterThan !== null) {
    conditions.push("duration_seconds < ?")
    params.push(rules.shorterThan * 60)
  }
  if (rules.longerThan !== null) {
    conditions.push("duration_seconds > ?")
    params.push(rules.longerThan * 60)
  }
  if (rules.starredOnly) conditions.push("starred_at IS NOT NULL")
  return { where: conditions.join(" AND "), params }
}

const ORDER_SQL: Record<PlaylistSort, string> = {
  newest: "published_at IS NULL, published_at DESC",
  oldest: "published_at IS NULL, published_at ASC",
  shortest: "duration_seconds IS NULL, duration_seconds ASC",
  longest: "duration_seconds IS NULL, duration_seconds DESC",
}

/** The whole query: the episodes the rules take, in the playlist's order. */
export function playlistQuery(
  rules: PlaylistRules,
  sort: PlaylistSort,
  now: number,
): { sql: string; params: (string | number)[] } {
  const { where, params } = rulesWhere(rules, now)
  return {
    sql: `SELECT * FROM episodes WHERE ${where} ORDER BY ${ORDER_SQL[sort]}, published_at DESC, id`,
    params,
  }
}

/** Keeps the episodes the "downloaded" rule allows, in order. `onPhone` holds finished downloads. */
export function filterDownloaded<T extends { id: string }>(
  episodes: readonly T[],
  rules: Pick<PlaylistRules, "downloaded">,
  onPhone: ReadonlySet<string>,
): T[] {
  if (rules.downloaded === "any") return [...episodes]
  const wanted = rules.downloaded === "downloaded"
  return episodes.filter((episode) => onPhone.has(episode.id) === wanted)
}

// MARK: Words

/** What the rules ask for in a few words ("Unplayed · Last 2 weeks · Starred"). */
export function describeRules(
  rules: PlaylistRules,
  showCount?: number,
): string {
  const parts: string[] = []
  if (rules.showIds !== null) {
    const count = showCount ?? rules.showIds.length
    parts.push(count === 1 ? "1 show" : `${count} shows`)
  }
  if (rules.played.length > 0 && rules.played.length < PLAYED_CHOICES.length) {
    parts.push(
      PLAYED_CHOICES.filter((c) => rules.played.includes(c.id))
        .map((c) => c.title)
        .join(" or "),
    )
  }
  if (rules.release !== "any") {
    parts.push(RELEASE_CHOICES.find((c) => c.id === rules.release)?.title ?? "")
  }
  if (rules.shorterThan !== null) parts.push(`Under ${rules.shorterThan} min`)
  if (rules.longerThan !== null) parts.push(`Over ${rules.longerThan} min`)
  if (rules.downloaded !== "any") {
    parts.push(
      rules.downloaded === "downloaded" ? "Downloaded" : "Not downloaded",
    )
  }
  if (rules.starredOnly) parts.push("Starred")
  return parts.length === 0 ? "Every episode" : parts.join(" · ")
}

// MARK: Auto-download

/** How many of a playlist's first episodes are kept downloaded. */
export const AUTO_DOWNLOAD_LIMIT = 5

type Downloadable = {
  id: string
  showId: string
  audioUrl: string
  audioType: string
  played?: boolean
}

/**
 * The episodes to download for the playlists that ask for it: each playlist's first
 * `AUTO_DOWNLOAD_LIMIT` episodes, in the playlists' order, once each, leaving out what is
 * already on the phone, on its way or failed (`known`). `matches` is playlist id to its
 * episodes in order. A playlist of episodes that are "Not downloaded" is skipped (it would
 * download the whole library, five at a time). With `skipPlayed`, played episodes are left
 * out too, so deleting played downloads does not start a fight with this.
 */
export function playlistDownloads<T extends Downloadable>(
  playlists: readonly {
    id: string
    autoDownload: boolean
    rules?: Pick<PlaylistRules, "downloaded">
  }[],
  matches: ReadonlyMap<string, readonly T[]>,
  known: ReadonlySet<string>,
  skipPlayed = false,
): T[] {
  const picked = new Map<string, T>()
  for (const playlist of playlists) {
    if (!playlist.autoDownload) continue
    if (playlist.rules?.downloaded === "notDownloaded") continue
    const wanted = (matches.get(playlist.id) ?? []).filter(
      (episode) => !(skipPlayed && episode.played === true),
    )
    for (const episode of wanted.slice(0, AUTO_DOWNLOAD_LIMIT)) {
      if (!known.has(episode.id) && !picked.has(episode.id)) {
        picked.set(episode.id, episode)
      }
    }
  }
  return [...picked.values()]
}
