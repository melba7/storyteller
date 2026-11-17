// LOFI-FORK: the podcasts section's transcript readers (see FORK.md).
//
// WebVTT and SRT share one shape: blocks separated by blank lines, each with a line
// "start --> end" and the spoken text under it. Cues stay as separate lines.
import { parseTimestamp } from "./timestamp"
import { type TranscriptLine, TranscriptFormatError } from "./types"

const ENTITIES: Record<string, string> = {
  "&amp;": "&",
  "&lt;": "<",
  "&gt;": ">",
  "&quot;": '"',
  "&#39;": "'",
  "&apos;": "'",
  "&nbsp;": " ",
  "&lrm;": "",
  "&rlm;": "",
}

function decode(text: string): string {
  return text.replace(
    /&(?:amp|lt|gt|quot|apos|nbsp|lrm|rlm|#39);/g,
    (m) => ENTITIES[m] ?? m,
  )
}

// <v Name> or <v.loud Name>, as in WebVTT voice tags.
const VOICE = /<v(?:\.[^\s>]*)*\s+([^>]*)>/i
// "Name: text" at the start of a line. Short names only (up to four words).
const NAMED = /^([A-Za-z][\w.'-]*(?: [\w.'-]+){0,3}): +(\S.*)$/

/** The speaker and the text of a cue's body (its lines joined by spaces). */
function readBody(raw: string): { speaker?: string; text: string } {
  let speaker: string | undefined
  const voice = VOICE.exec(raw)
  if (voice) speaker = decode((voice[1] ?? "").trim()) || undefined
  let text = decode(raw.replace(/<[^>]*>/g, ""))
    .replace(/\s+/g, " ")
    .trim()
  if (!speaker) {
    const named = NAMED.exec(text)
    if (named && (named[1] ?? "").length <= 30) {
      speaker = named[1]
      text = (named[2] ?? "").trim()
    }
  }
  return speaker ? { speaker, text } : { text }
}

/**
 * Reads the cues of the blocks in `blocks` (each a list of lines). A block with no usable
 * time line is skipped, so one bad cue does not lose the file. Throws when nothing is left.
 */
export function readCues(blocks: string[][]): TranscriptLine[] {
  const lines: TranscriptLine[] = []
  let last: string | undefined
  for (const block of blocks) {
    const at = block.findIndex((line) => line.includes("-->"))
    if (at < 0) continue
    const [from, rest] = (block[at] ?? "").split("-->")
    const start = parseTimestamp((from ?? "").trim())
    const end = parseTimestamp((rest ?? "").trim().split(/\s+/)[0] ?? "")
    if (start === null || end === null || end < start) continue
    const body = readBody(block.slice(at + 1).join(" "))
    if (body.text === "") continue
    last = body.speaker ?? last
    lines.push(
      last === undefined
        ? { start, end, text: body.text }
        : { start, end, speaker: last, text: body.text },
    )
  }
  if (lines.length === 0) {
    throw new TranscriptFormatError(
      "This transcript has no lines that can be read.",
    )
  }
  return lines.sort((a, b) => a.start - b.start)
}

/** The blocks of a text: lines between blank lines. Handles "\r\n" and a leading BOM. */
export function blocksOf(text: string): string[][] {
  const blocks: string[][] = []
  let current: string[] = []
  for (const line of text.replace(/^﻿/, "").split(/\r\n|\r|\n/)) {
    if (line.trim() === "") {
      if (current.length > 0) blocks.push(current)
      current = []
    } else current.push(line)
  }
  if (current.length > 0) blocks.push(current)
  return blocks
}
