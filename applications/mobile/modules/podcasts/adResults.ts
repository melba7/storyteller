// LOFI-FORK: the podcasts section's ad skipping results (see FORK.md).
//
// The "Ad skipping results" page: what the phone skipped (totals, then a row for each show) and
// what the Mac taught it. These are the rules for the words; Swift counts (`getAdTally`) and
// keeps what is installed (`getTeachingState`). Nothing here needs the native module.
import { isPreviewId } from "./preview"
import { formatDuration } from "./stats"
import type { TeachingState } from "./teaching"

/** What the phone counted for one show. */
export type ShowTally = {
  skipped: number
  undone: number
  trimmed: number
  missed: number
  /** Seconds of audio the skips saved. */
  seconds: number
}

export const NO_LONGER_FOLLOWED = "A show you no longer follow"
const PREVIEWED = "A show you previewed"
const YOUR_FILES = "Your files"

/** What a tally's id stands for when it is not a followed show. */
function unfollowedName(id: string): string {
  if (id === "") return YOUR_FILES
  if (isPreviewId(id)) return PREVIEWED
  return NO_LONGER_FOLLOWED
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function count(value: unknown): number {
  return typeof value === "number" && Number.isInteger(value) && value > 0
    ? value
    : 0
}

function seconds(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? value
    : 0
}

/** The tally by show id, from the native JSON text. Anything it cannot read is left out. */
export function parseTally(text: string | null): Record<string, ShowTally> {
  let value: unknown
  try {
    value = JSON.parse(text ?? "")
  } catch {
    return {}
  }
  if (!isRecord(value) || !isRecord(value["shows"])) return {}
  const tally: Record<string, ShowTally> = {}
  for (const [id, entry] of Object.entries(value["shows"])) {
    if (!isRecord(entry)) continue
    tally[id] = {
      skipped: count(entry["skipped"]),
      undone: count(entry["undone"]),
      trimmed: count(entry["trimmed"]),
      missed: count(entry["missed"]),
      seconds: seconds(entry["seconds"]),
    }
  }
  return tally
}

export type ResultTotal = {
  key: "skipped" | "saved" | "undone" | "missed"
  label: string
  value: string
}

export type ResultRow = { key: string; title: string; text: string }

export type AdResults = {
  totals: ResultTotal[]
  rows: ResultRow[]
  /** The phone has skipped nothing yet, and nothing was marked as missed. */
  empty: boolean
}

/**
 * The totals and the rows. A show with nothing skipped, taken back or missed is left out.
 * The shows with the most missed and taken back come first, then the most skipped, then by
 * title. A show that is not in `shows` any more is "A show you no longer follow"; a previewed show and
 * the added files have their own names.
 */
export function resultsFor(
  tally: Readonly<Record<string, ShowTally>>,
  shows: readonly { id: string; title: string }[],
): AdResults {
  const titles = new Map(shows.map((show) => [show.id, show.title]))
  const listed = Object.entries(tally)
    .filter(([, t]) => t.skipped + t.undone + t.missed > 0)
    .map(([id, t]) => ({ id, t, title: titles.get(id) ?? unfollowedName(id) }))
    .sort(
      (a, b) =>
        b.t.missed + b.t.undone - (a.t.missed + a.t.undone) ||
        b.t.skipped - a.t.skipped ||
        a.title.localeCompare(b.title),
    )
  const sum = (pick: (t: ShowTally) => number) =>
    Object.values(tally).reduce((total, t) => total + pick(t), 0)
  return {
    totals: [
      {
        key: "skipped",
        label: "Ads skipped",
        value: String(sum((t) => t.skipped)),
      },
      {
        key: "saved",
        label: "Time saved",
        value: formatDuration(sum((t) => t.seconds)),
      },
      {
        key: "undone",
        label: "Skips you took back",
        value: String(sum((t) => t.undone)),
      },
      {
        key: "missed",
        label: "Ads you marked as missed",
        value: String(sum((t) => t.missed)),
      },
    ],
    rows: listed.map(({ id, t, title }) => ({
      key: id,
      title,
      text: `${title}: ${[
        `${t.skipped} skipped`,
        ...(t.undone > 0 ? [`${t.undone} taken back`] : []),
        ...(t.missed > 0 ? [`${t.missed} missed`] : []),
      ].join(", ")}`,
    })),
    empty: listed.length === 0,
  }
}

// MARK: What the Mac taught

const DAY_MS = 24 * 60 * 60 * 1000

/** "today", "yesterday" or "12 days ago" for a time (text or milliseconds); null when unreadable. */
export function agoText(
  when: string | number | null,
  now: number,
): string | null {
  const at = typeof when === "string" ? Date.parse(when) : when
  if (at === null || !Number.isFinite(at)) return null
  const days = Math.floor((now - at) / DAY_MS)
  if (days <= 0) return "today"
  return days === 1 ? "yesterday" : `${days} days ago`
}

export type MacLine = { key: string; label: string; text: string }

export type MacSection = {
  lines: MacLine[]
  /** What to say when the Mac has taught nothing, else null. */
  empty: { title: string; text: string } | null
}

function plural(n: number, one: string, many: string): string {
  return `${n} ${n === 1 ? one : many}`
}

/** One line for each thing the Mac taught, or the sentence that says it has taught nothing. */
export function macSection(state: TeachingState, now: number): MacSection {
  const lines: MacLine[] = []
  const { model } = state
  if (model !== null) {
    const ago = agoText(model.writtenAt, now)
    const from = `From ${plural(model.episodes, "episode", "episodes")}${ago ? `, ${ago}` : ""}.`
    const right =
      model.precision === null
        ? ""
        : ` Right ${Math.round(model.precision * 100)} times in 100 on episodes it never saw.`
    lines.push({ key: "model", label: "Small model", text: from + right })
  }
  if (state.library > 0) {
    lines.push({
      key: "library",
      label: "Known ads",
      text: `${state.library} ads it has heard before`,
    })
  }
  if (state.habits > 0) {
    lines.push({
      key: "habits",
      label: "How shows start",
      text: `Knows how ${state.habits} shows usually start`,
    })
  }
  if (state.sounds > 0) {
    lines.push({
      key: "sounds",
      label: "Ad sounds",
      text: `${plural(state.sounds, "sound", "sounds")} it listens for`,
    })
  }
  return {
    lines,
    empty:
      lines.length > 0
        ? null
        : {
            title: "Nothing from your Mac yet",
            text: "Your phone still skips ads by itself.",
          },
  }
}
