// LOFI-FORK: the podcasts section's teaching files from the Mac (see FORK.md).
//
// The Mac writes six teaching files and a list of them, `Podcasts/teaching.json`, into the
// linked folder (docs/PODCASTS-ADS-TEACHING.md). These are the rules for which files the phone
// fetches and for the table of feeds it sends to the native side. Nothing here touches the
// folder or the native modules (teachingSync.ts does).
import { type AppleExport, feedKey } from "./applePodcasts"
import { feedShows } from "./localFiles"

export const TEACHING_LIST_FILE = "Podcasts/teaching.json"

/**
 * The files the Mac may teach with, in the order they are fetched. The Mac's teach_publish.py
 * writes the same six (its test compares the two lists) and the phone's `TeachingFiles.install`
 * and `AdSoundLibrary.install` take the same six.
 */
export const TEACHING_NAMES = [
  "ad-model.json",
  "ad-library.json",
  "show-habits.json",
  "ad-sounds.json",
  "ad-meaning.json",
  "show-settings.json",
] as const

export type TeachingName = (typeof TEACHING_NAMES)[number]

/** A file bigger than this is never fetched; the Mac keeps them under 4.5 MB. */
export const MAX_TEACHING_BYTES = 5_000_000

/** The teaching files run at most this often (milliseconds). */
export const TEACHING_EVERY_MS = 10 * 60 * 1000

export type TeachingListed = { sha256: string; bytes: number }
export type TeachingList = Partial<Record<TeachingName, TeachingListed>>

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

/**
 * The Mac's list of files, or null when it is not exactly what the phone knows: version 1 and
 * `files` an object of `{sha256, bytes}`. Null means nothing to do. Names the phone does not
 * know are left out.
 */
export function parseTeachingList(text: string): TeachingList | null {
  let value: unknown
  try {
    value = JSON.parse(text)
  } catch {
    return null
  }
  if (!isRecord(value) || value["version"] !== 1) return null
  const files = value["files"]
  if (!isRecord(files)) return null
  const list: TeachingList = {}
  for (const [name, entry] of Object.entries(files)) {
    if (!isRecord(entry)) return null
    const { sha256, bytes } = entry
    if (typeof sha256 !== "string" || sha256 === "") return null
    if (typeof bytes !== "number" || !Number.isInteger(bytes) || bytes < 0)
      return null
    const known = TEACHING_NAMES.find((candidate) => candidate === name)
    if (known) list[known] = { sha256, bytes }
  }
  return list
}

/**
 * The files to fetch: the listed ones whose SHA-256 is not the installed one and whose size is
 * not over the limit. `installed` maps a name to the checksum of the file the phone has.
 * `refused` maps a name to the checksum of a file the phone refused earlier in this launch; the
 * same file is not fetched again.
 */
export function filesToFetch(
  list: TeachingList,
  installed: Readonly<Record<string, string>>,
  refused: Readonly<Record<string, string>> = {},
): TeachingName[] {
  return TEACHING_NAMES.filter((name) => {
    const listed = list[name]
    if (!listed || listed.bytes > MAX_TEACHING_BYTES) return false
    const sha = listed.sha256.toLowerCase()
    if (refused[name]?.toLowerCase() === sha) return false
    return installed[name]?.toLowerCase() !== sha
  })
}

/**
 * The table of feed key to show id for the shows with a feed. A show that moved to a new feed
 * is also known under the address the Apple export has for it (matched by title, as
 * `withLibraryFeeds` does), so the Mac's habits and ad library for the newer address still
 * reach it.
 */
export function showTable(
  shows: readonly { id: string; feedUrl: string; title?: string }[],
  apple: AppleExport | null = null,
): Record<string, string> {
  const table: Record<string, string> = {}
  const own = feedShows(shows)
  for (const show of own) {
    const key = feedKey(show.feedUrl)
    if (key !== "" && !(key in table)) table[key] = show.id
  }
  const byTitle = new Map<string, string>()
  for (const show of own) {
    const title = (show.title ?? "").trim().toLowerCase()
    if (title !== "" && !byTitle.has(title)) byTitle.set(title, show.id)
  }
  for (const item of apple?.shows ?? []) {
    const id = byTitle.get((item.title ?? "").trim().toLowerCase())
    const key = feedKey(item.feed)
    if (id !== undefined && key !== "" && !(key in table)) table[key] = id
  }
  return table
}

/** The table as JSON text, keys in order, so a table that did not change reads the same. */
export function showTableText(
  shows: readonly { id: string; feedUrl: string; title?: string }[],
  apple: AppleExport | null = null,
): string {
  const table = showTable(shows, apple)
  const sorted: Record<string, string> = {}
  for (const key of Object.keys(table).sort()) sorted[key] = table[key] ?? ""
  return JSON.stringify(sorted)
}

/** Whether a run may start: the first one, or ten minutes since the last (or the clock moved back). */
export function dueForTeaching(last: number | null, now: number): boolean {
  return last === null || now < last || now - last >= TEACHING_EVERY_MS
}

/** What the phone says about the small model it has. */
export type TeachingModel = {
  /** When the Mac trained it: as the file wrote it (text or milliseconds). */
  writtenAt: string | number | null
  episodes: number
  /** How often it was right when it said ad, on episodes it never saw (0 to 1). */
  precision: number | null
  recall: number | null
}

/** What the phone has of the Mac's teaching (`getTeachingState` in the native module). */
export type TeachingState = {
  /** The checksum of each installed file, by name. */
  installed: Record<string, string>
  model: TeachingModel | null
  /** How many known ads, shows with habits and ad sounds. */
  library: number
  habits: number
  sounds: number
}

function count(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? Math.floor(value)
    : 0
}

/** How many entries the native side reports: a number, or a list or table it sent whole. */
function entries(value: unknown): number {
  if (Array.isArray(value)) return value.length
  if (isRecord(value)) return Object.keys(value).length
  return count(value)
}

function fraction(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null
}

/** Reads the native state; whatever it cannot read counts as nothing installed. */
export function parseTeachingState(text: string | null): TeachingState {
  const empty: TeachingState = {
    installed: {},
    model: null,
    library: 0,
    habits: 0,
    sounds: 0,
  }
  let value: unknown
  try {
    value = JSON.parse(text ?? "")
  } catch {
    return empty
  }
  if (!isRecord(value)) return empty
  const installed: Record<string, string> = {}
  if (isRecord(value["files"])) {
    for (const [name, entry] of Object.entries(value["files"])) {
      if (isRecord(entry) && typeof entry["sha256"] === "string")
        installed[name] = entry["sha256"]
    }
  }
  const model = value["model"]
  const written = isRecord(model) ? model["writtenAt"] : null
  return {
    installed,
    model:
      isRecord(model) && count(model["episodes"]) > 0
        ? {
            writtenAt:
              typeof written === "string" || typeof written === "number"
                ? written
                : null,
            episodes: count(model["episodes"]),
            precision: fraction(model["precision"]),
            recall: fraction(model["recall"]),
          }
        : null,
    library: entries(value["library"]),
    habits: entries(value["habits"]),
    sounds: entries(value["sounds"]),
  }
}
