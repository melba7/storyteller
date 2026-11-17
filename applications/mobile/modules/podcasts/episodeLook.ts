// LOFI-FORK: the podcasts section's episode look rules (see FORK.md).
//
// Pure functions for the show page and the episode card: what state a row is in, how much
// of the progress ring to draw, and where the links are in an episode's notes.
import { downloadFraction } from "./downloads"
import type { DownloadInfo } from "./index"
import { type StoredEpisode, formatEpisodeLength } from "./library"

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

export type MetaGlyph =
  | "none"
  | "played"
  | "downloaded"
  | "downloading"
  | "failed"

/** What a row's meta line shows: a small glyph, the length or time left, and "Up Next". */
export interface RowMeta {
  glyph: MetaGlyph
  /** The mini ring's fill for a download in progress; null when it isn't known. */
  fraction: number | null
  /** The length, the time left or "Played"; empty when there is none. */
  length: string
  queued: boolean
  /** The same facts as words for the row's VoiceOver label, since the glyph is hidden. */
  spoken: string[]
}

/**
 * The meta line of an episode row. `length` is `formatEpisodeLength`'s text, `queued` is
 * `queuedLabel`'s ("" when not in Up Next) and `download` is the episode's download, if any.
 * One glyph shows: a download's state wins over the played check.
 */
export function rowMeta({
  state,
  length,
  queued,
  download,
}: {
  state: RowState
  length: string
  queued: string
  download?: DownloadInfo | undefined
}): RowMeta {
  let glyph: MetaGlyph = state === "played" ? "played" : "none"
  let fraction: number | null = null
  let downloadWords = ""
  if (download) {
    switch (download.state) {
      case "downloaded":
        glyph = "downloaded"
        downloadWords = "Downloaded"
        break
      case "downloading": {
        glyph = "downloading"
        fraction = downloadFraction(download)
        downloadWords =
          fraction === null
            ? "Downloading"
            : `Downloading, ${Math.floor(fraction * 100)}%`
        break
      }
      case "queued":
        glyph = "downloading"
        downloadWords = "Waiting to download"
        break
      case "failed":
        glyph = "failed"
        downloadWords = "Download failed"
        break
    }
  }
  return {
    glyph,
    fraction,
    length,
    queued: queued !== "",
    spoken: [downloadWords, length, queued].filter((part) => part !== ""),
  }
}

/** A show page's meta line: its first top-level category and its episode count. */
export function showMeta(
  categories: readonly string[],
  count: number | null,
): string {
  const category =
    categories.find((name) => !name.includes("›")) ?? categories[0] ?? ""
  const episodes =
    count === null ? "" : count === 1 ? "1 episode" : `${count} episodes`
  return [category, episodes].filter((part) => part !== "").join(" · ")
}

/** The episode card's main button: "Play", "Resume · 32 min left" or "Pause". */
export function playLabel(episode: Listened, playing: boolean): string {
  if (playing) return "Pause"
  if (episode.played || !(episode.positionSeconds > 0)) return "Play"
  const left = formatEpisodeLength(episode)
  return left.endsWith(" left") ? `Resume · ${left}` : "Resume"
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
