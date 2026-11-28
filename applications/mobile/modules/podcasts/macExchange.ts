// LOFI-FORK: the podcasts section's exchange with the Mac (see FORK.md).
//
// What the phone remembers of its last exchange with the Mac through the linked folder, and the
// plain words that say it. The run is in teachingRun.ts and the saving in macExchangeStore.ts;
// nothing here touches the folder, the database or the native modules.

/** What came in from the Mac in one run. */
export type Came = {
  /** Teaching files installed, not counting the marks file. */
  files: number
  /** Episodes in the Mac's marks (`ahead-ads.json`) when that file came. */
  marks: number
  /** Prepared copies of episodes taken. */
  copies: number
}

/** What the Mac can see from the phone in the linked folder. */
export type Went = { list: boolean; notes: boolean; diary: boolean }

/** The last exchange: when it was, what came in, and what is there for the Mac. */
export type Exchange = { at: number; came: Came; went: Went }

export const NOTHING_CAME: Came = { files: 0, marks: 0, copies: 0 }

/** What the line says before anything ever moved, and the step that makes it move. */
export const NEVER_EXCHANGED =
  "Nothing has moved between your phone and your Mac yet. Link the LofiMusic folder in Settings."

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function count(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? Math.floor(value)
    : 0
}

/** The saved exchange, or null when there is none or it cannot be read. */
export function parseExchange(text: string | null): Exchange | null {
  let value: unknown
  try {
    value = JSON.parse(text ?? "")
  } catch {
    return null
  }
  if (!isRecord(value)) return null
  const at = value["at"]
  if (typeof at !== "number" || !Number.isFinite(at) || at <= 0) return null
  const came = isRecord(value["came"]) ? value["came"] : {}
  const went = isRecord(value["went"]) ? value["went"] : {}
  return {
    at,
    came: {
      files: count(came["files"]),
      marks: count(came["marks"]),
      copies: count(came["copies"]),
    },
    went: {
      list: went["list"] === true,
      notes: went["notes"] === true,
      diary: went["diary"] === true,
    },
  }
}

export function cameAny(came: Came): boolean {
  return came.files > 0 || came.marks > 0 || came.copies > 0
}

function wentAny(went: Went): boolean {
  return went.list || went.notes || went.diary
}

/**
 * What to save after a run: the run's own record when something came, or when nothing was saved
 * yet and something is there for the Mac, or when what is there changed. A quiet run that brings
 * nothing new leaves the last exchange as it was, so "Came: marks for 7 episodes" stays until
 * something else comes. Null means nothing moved and there is nothing to save.
 */
export function exchangeToSave(
  saved: Exchange | null,
  now: number,
  came: Came,
  went: Went,
): Exchange | null {
  if (cameAny(came)) return { at: now, came, went }
  if (saved === null) return wentAny(went) ? { at: now, came, went } : null
  const same =
    saved.went.list === went.list &&
    saved.went.notes === went.notes &&
    saved.went.diary === went.diary
  return same ? null : { at: now, came: saved.came, went }
}

/**
 * The number of marks in `ahead-ads.json`: the episodes whose marks are not more than 14 days
 * old, as the phone ignores older ones. `nowSeconds` is seconds since 1970. Zero for text that is
 * not that file.
 */
export function countAheadMarks(text: string, nowSeconds: number): number {
  let value: unknown
  try {
    value = JSON.parse(text)
  } catch {
    return 0
  }
  if (!isRecord(value) || !Array.isArray(value["episodes"])) return 0
  const fourteenDays = 14 * 24 * 60 * 60
  return value["episodes"].filter((episode: unknown) => {
    if (!isRecord(episode)) return false
    const marked = episode["marked"]
    return typeof marked !== "number" || nowSeconds - marked <= fourteenDays
  }).length
}

function plural(n: number, one: string, many: string): string {
  return `${n} ${n === 1 ? one : many}`
}

function joined(parts: string[]): string {
  if (parts.length <= 1) return parts.join("")
  return `${parts.slice(0, -1).join(", ")} and ${parts[parts.length - 1] ?? ""}`
}

function clock(at: Date): string {
  const hours = at.getHours()
  const minutes = String(at.getMinutes()).padStart(2, "0")
  return `${hours % 12 === 0 ? 12 : hours % 12}:${minutes} ${hours < 12 ? "AM" : "PM"}`
}

function dayStart(at: Date): number {
  return new Date(at.getFullYear(), at.getMonth(), at.getDate()).getTime()
}

/** "today 11:10 PM", "yesterday 11:10 PM", or "3 days ago" when it was older than that. */
export function exchangeWhen(at: number, now: number): string {
  const when = new Date(at)
  const days = Math.round(
    (dayStart(new Date(now)) - dayStart(when)) / 86_400_000,
  )
  if (days <= 0) return `today ${clock(when)}`
  if (days === 1) return `yesterday ${clock(when)}`
  return `${days} days ago`
}

/**
 * The one line for the screens: "Last exchange with your Mac: today 11:10 PM. Came: marks for 7
 * episodes, 1 copy. Went: your list and notes." Before anything moved it says so and names the
 * step that makes it move.
 */
export function exchangeLine(exchange: Exchange | null, now: number): string {
  if (exchange === null) return NEVER_EXCHANGED
  const { came, went } = exchange
  const cameParts: string[] = []
  if (came.marks > 0)
    cameParts.push(`marks for ${plural(came.marks, "episode", "episodes")}`)
  if (came.files > 0)
    cameParts.push(plural(came.files, "teaching file", "teaching files"))
  if (came.copies > 0) cameParts.push(plural(came.copies, "copy", "copies"))
  const wentParts: string[] = []
  if (went.list) wentParts.push("your list")
  if (went.notes || went.diary)
    wentParts.push(
      went.notes && went.diary
        ? "notes and diary"
        : went.notes
          ? "notes"
          : "diary",
    )
  return [
    `Last exchange with your Mac: ${exchangeWhen(exchange.at, now)}.`,
    `Came: ${cameParts.length > 0 ? joined(cameParts) : "nothing"}.`,
    `Went: ${wentParts.length > 0 ? joined(wentParts) : "nothing"}.`,
  ].join(" ")
}
