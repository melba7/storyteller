// LOFI-FORK: the podcasts section's notes for the Mac (see FORK.md).
//
// The phone notes what happened to ads (skipped, undone, trimmed, missed, and the answers
// "confirmed" and "denied" to its questions) and writes the notes into
// `Podcasts/phone-notes.jsonl` of the linked folder, for the Mac to learn from. These are
// the rules for turning the native side's pending notes into those lines. Nothing here touches
// the database or the folder (phoneNotesSync.ts does).
import type { LinkedFileRead } from "@/modules/lofi-score"

export const NOTES_FILE = "Podcasts/phone-notes.jsonl"
export const DIARY_FILE = "Podcasts/phone-diary.jsonl"

/** The notes file keeps this many of the newest lines. */
export const MAX_NOTE_LINES = 2000

const WHAT = [
  "skipped",
  "undone",
  "trimmed",
  "missed",
  "confirmed",
  "denied",
] as const
type What = (typeof WHAT)[number]
const KINDS = ["ad", "ownPlug", "promo", "credits"] as const

/** A note as the native side keeps it, before the app adds what the database knows. */
export type PendingNote = {
  at: number
  what: What
  episode: string
  /** The show's id, or "" when the native side did not know it. */
  show: string
  start: number
  end: number | null
  /** A sort of ad, or "" when the note has none (a missed ad). */
  kind: string
  /** The name of the finder that made the ad ("own-sound", "meaning"), or "" when not known. */
  by: string
}

/** What the database knows about the episode a note is for. */
export type NoteEpisode = {
  feed: string
  guid: string
  title: string
  address: string
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function isNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value)
}

function readNote(line: string): PendingNote | null {
  let value: unknown
  try {
    value = JSON.parse(line)
  } catch {
    return null
  }
  if (!isRecord(value)) return null
  const { at, what, episode, show, start, end } = value
  const known = WHAT.find((name) => name === what)
  if (!known || !isNumber(at) || !isNumber(start)) return null
  if (typeof episode !== "string" || episode === "") return null
  if (end !== null && !isNumber(end)) return null
  return {
    at,
    what: known,
    episode,
    show: typeof show === "string" ? show : "",
    start,
    end,
    kind: KINDS.find((name) => name === value["kind"]) ?? "",
    by: typeof value["by"] === "string" ? value["by"] : "",
  }
}

/**
 * The notes in the pending lines, and how many lines were read. A line that does not parse is
 * dropped, but it is counted, so that removing that many lines clears it too.
 */
export function parsePendingNotes(text: string): {
  notes: PendingNote[]
  count: number
} {
  const lines = text.split("\n").filter((line) => line.trim() !== "")
  const notes = lines.flatMap((line) => readNote(line) ?? [])
  return { notes, count: lines.length }
}

/**
 * One line of the notes file, keys in the order of docs/PODCASTS-ADS-TEACHING.md. An episode
 * that is gone is written with empty text; `showFeed` is the show's feed address when only the
 * show is still known. `by` comes last and only when the note has one, so a note with no finder
 * is the line older builds wrote (the Mac reads it as optional, `teach_feedback.read_note`).
 */
export function noteLine(
  note: PendingNote,
  episode: NoteEpisode | null,
  showFeed = "",
): string {
  return JSON.stringify({
    v: 1,
    at: note.at,
    what: note.what,
    feed: episode?.feed ?? showFeed,
    guid: episode?.guid ?? "",
    title: episode?.title ?? "",
    address: episode?.address ?? "",
    start: note.start,
    end: note.end,
    kind: note.kind,
    ...(note.by === "" ? {} : { by: note.by }),
  })
}

/**
 * The notes file with `added` lines after the old ones, keeping the newest 2,000. A line that is
 * already in the old text is not added again (a write that was not followed by the removal).
 */
export function mergeNoteLines(old: string, added: readonly string[]): string {
  const kept = old.split("\n").filter((line) => line.trim() !== "")
  const known = new Set(kept)
  const lines = [...kept, ...added.filter((line) => !known.has(line))].slice(
    -MAX_NOTE_LINES,
  )
  return lines.length === 0 ? "" : `${lines.join("\n")}\n`
}

/**
 * The time of the newest note, in milliseconds: what the native side is told when the written
 * notes are removed, so a note added since the read stays. `fallback` is for lines that did not
 * parse (the time the notes were read).
 */
export function newestNoteAt(
  notes: readonly PendingNote[],
  fallback: number,
): number {
  return notes.reduce(
    (newest, note) => Math.max(newest, note.at),
    notes.length === 0 ? fallback : 0,
  )
}

/** A short mark of a text (its length and a checksum), to tell whether it changed since a write. */
export function diaryStamp(text: string): string {
  let hash = 0x811c9dc5
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i)
    hash = Math.imul(hash, 0x01000193)
  }
  return `${text.length}:${(hash >>> 0).toString(16)}`
}

/**
 * The notes file as it is now, to add to: its text, or empty when there is no file yet. Null
 * when nothing may be written (no folder, or the file may be there but is not downloaded or
 * not readable), so a file is never overwritten with only the new lines.
 */
export function oldNotesText(read: LinkedFileRead): string | null {
  if (read.status === "found") return read.text
  return read.status === "missing" ? "" : null
}
