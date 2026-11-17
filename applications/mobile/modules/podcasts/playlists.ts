// LOFI-FORK: the podcasts section's playlists (see FORK.md).
//
// What a playlist is, how a database row becomes one, and the three that every library
// starts with. Pure: the database calls are in dbPlaylists.ts, the rules in playlistRules.ts.
import {
  DEFAULT_RULES,
  type PlaylistRules,
  type PlaylistSort,
  parseRules,
  parseSort,
  serializeRules,
} from "./playlistRules"

export type Playlist = {
  id: string
  title: string
  /** Where it sits in the list, 0 for the first. */
  position: number
  /** What a smart playlist asks for. */
  rules: PlaylistRules
  sort: PlaylistSort
  /** Keep the first few episodes downloaded, on Wi-Fi. */
  autoDownload: boolean
  /** Milliseconds since 1970. */
  createdAt: number
}

/** The playlists a library starts with, made once when the playlists were added. */
export const STARTER_PLAYLISTS: {
  id: string
  title: string
  rules: PlaylistRules
}[] = [
  {
    id: "starter-new-releases",
    title: "New Releases",
    rules: { ...DEFAULT_RULES, played: ["unplayed"], release: "twoWeeks" },
  },
  {
    id: "starter-in-progress",
    title: "In Progress",
    rules: { ...DEFAULT_RULES, played: ["inProgress"] },
  },
  {
    id: "starter-starred",
    title: "Starred",
    rules: { ...DEFAULT_RULES, starredOnly: true },
  },
]

function sqlText(text: string): string {
  return `'${text.replaceAll("'", "''")}'`
}

/** The statements that make the starter playlists (the schema runs them once). */
export function starterStatements(): string[] {
  return STARTER_PLAYLISTS.map(
    (playlist, position) =>
      `INSERT INTO playlists (id, title, position, rules, sort, auto_download, created_at) VALUES (${sqlText(playlist.id)}, ${sqlText(playlist.title)}, ${position}, ${sqlText(serializeRules(playlist.rules))}, 'newest', 0, CAST(strftime('%s', 'now') AS INTEGER) * 1000)`,
  )
}

type Row = Record<string, unknown>

export function playlistFromRow(row: Row): Playlist {
  return {
    id: String(row["id"] ?? ""),
    title: String(row["title"] ?? ""),
    position: Number(row["position"] ?? 0),
    rules: parseRules(row["rules"]),
    sort: parseSort(row["sort"]),
    autoDownload: row["auto_download"] === 1 || row["auto_download"] === true,
    createdAt: Number(row["created_at"] ?? 0),
  }
}

/** A new, empty smart playlist for the editor to fill in. */
export function newPlaylist(
  id: string,
  position: number,
  now: number,
): Playlist {
  return {
    id,
    title: "",
    position,
    rules: DEFAULT_RULES,
    sort: "newest",
    autoDownload: false,
    createdAt: now,
  }
}

/** What the length boxes hold, as minutes: a whole number above 0, else null (no limit). */
export function parseMinutes(text: string): number | null {
  const value = Number.parseInt(text.trim(), 10)
  return Number.isFinite(value) && value > 0 ? value : null
}

/** Why a smart playlist can't be saved yet, in plain words, or null when it can. */
export function playlistProblem(
  title: string,
  rules: PlaylistRules,
): string | null {
  if (title.trim() === "") return "Give the playlist a name."
  if (rules.showIds !== null && rules.showIds.length === 0) {
    return "Choose at least one show, or use all shows."
  }
  if (
    rules.shorterThan !== null &&
    rules.longerThan !== null &&
    rules.longerThan >= rules.shorterThan
  ) {
    return "No episode is both longer and shorter than that."
  }
  return null
}
