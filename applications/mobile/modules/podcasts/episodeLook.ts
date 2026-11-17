// LOFI-FORK: the podcasts section's episode look rules (see FORK.md).
//
// Pure functions for the show page and the episode card: what state a row is in, how much
// of the progress ring to draw, and where the links are in an episode's notes.
import { type StoredEpisode } from "./library"

type Listened = Pick<
  StoredEpisode,
  "positionSeconds" | "durationSeconds" | "played"
>

export type RowState = "unplayed" | "inProgress" | "played"

export function rowState(episode: Listened): RowState {
  if (episode.played) return "played"
  return episode.positionSeconds > 0 ? "inProgress" : "unplayed"
}

/**
 * How much of the ring around the play button is filled, from 0 to 1. It is 0 for an
 * unplayed episode or an unknown length, and null for a played episode (no ring at all).
 */
export function ringFraction(episode: Listened): number | null {
  if (episode.played) return null
  const { positionSeconds: position, durationSeconds: duration } = episode
  if (duration === null || !(duration > 0) || !(position > 0)) return 0
  return Math.min(1, position / duration)
}

export type NotesPart =
  | { type: "text"; text: string }
  | { type: "link"; text: string; url: string }

const URL_PATTERN = /https?:\/\/[^\s<>]+/g
const TRAILING = /[.,;:!?'"\]]$/

function count(text: string, char: string): number {
  return text.split(char).length - 1
}

/** Cuts the punctuation that follows a link in a sentence, keeping a balanced ")". */
function trimLink(url: string): string {
  let end = url
  for (;;) {
    if (TRAILING.test(end)) end = end.slice(0, -1)
    else if (end.endsWith(")") && count(end, ")") > count(end, "(")) {
      end = end.slice(0, -1)
    } else return end
  }
}

/** The notes cut into plain text and http(s) links, in order. Empty notes give no parts. */
export function splitNotes(notes: string): NotesPart[] {
  const parts: NotesPart[] = []
  let last = 0
  for (const match of notes.matchAll(URL_PATTERN)) {
    const url = trimLink(match[0])
    // A bare "https://" has no address after it, so it stays text.
    if (/^https?:\/\/$/.test(url)) continue
    if (match.index > last) {
      parts.push({ type: "text", text: notes.slice(last, match.index) })
    }
    parts.push({ type: "link", text: url, url })
    last = match.index + url.length
  }
  if (last < notes.length) parts.push({ type: "text", text: notes.slice(last) })
  return parts
}

const CLAMPED_LINES = 3
const CHARS_PER_LINE = 45

/**
 * Whether a description is probably longer than three lines, so it needs a More button.
 * A guess from the text's length and line breaks: measuring the clamped text on screen is
 * not reliable across platforms.
 */
export function needsMore(description: string): boolean {
  const lines = description
    .split("\n")
    .reduce(
      (total, line) =>
        total + Math.max(1, Math.ceil(line.length / CHARS_PER_LINE)),
      0,
    )
  return lines > CLAMPED_LINES
}
