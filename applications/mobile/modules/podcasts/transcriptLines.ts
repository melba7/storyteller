// LOFI-FORK: the podcasts section's transcripts (see FORK.md).
//
// Finding the line playing and searching the words. Plain rules over lines in time order.
import type { TranscriptLine } from "./transcriptFormats"

/**
 * The index of the line to show at `time` seconds: the line that contains it, or in a gap
 * between lines the one just before it. Before the first line it is the first (index 0).
 * -1 when there are no lines. Binary search, because an hour of speech is thousands of lines.
 */
export function lineAt(lines: readonly TranscriptLine[], time: number): number {
  if (lines.length === 0) return -1
  let low = 0
  let high = lines.length - 1
  let found = 0
  while (low <= high) {
    const middle = (low + high) >> 1
    if ((lines[middle] as TranscriptLine).start <= time) {
      found = middle
      low = middle + 1
    } else high = middle - 1
  }
  return found
}

/** Lower case with accents removed, so "Café" matches "cafe". */
export function foldText(text: string): string {
  return text
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
}

/**
 * The indexes of the lines that contain the query (every word of it), in order. An empty
 * query finds nothing.
 */
export function searchLines(
  lines: readonly TranscriptLine[],
  query: string,
): number[] {
  const words = foldText(query).split(/\s+/).filter(Boolean)
  if (words.length === 0) return []
  const found: number[] = []
  lines.forEach((line, index) => {
    const text = foldText(line.text)
    if (words.every((word) => text.includes(word))) found.push(index)
  })
  return found
}

/** The match after (or before) `current`, wrapping round; the first (last) when `current` is not one. */
export function stepMatch(
  matches: readonly number[],
  current: number | null,
  direction: 1 | -1,
): number | null {
  if (matches.length === 0) return null
  const at = current === null ? -1 : matches.indexOf(current)
  if (at < 0) {
    return (direction === 1 ? matches[0] : matches[matches.length - 1]) ?? null
  }
  return matches[(at + direction + matches.length) % matches.length] ?? null
}

/** The time as the screen reads it: "4:05" or "1:02:03". */
export function lineTimeLabel(seconds: number): string {
  const total = Math.max(0, Math.floor(seconds))
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  const pad = (n: number) => String(n).padStart(2, "0")
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`
}

/** Whether the line starts a new speaker's turn (the speaker's name is shown above it). */
export function speakerChanges(
  lines: readonly TranscriptLine[],
  index: number,
): boolean {
  const speaker = lines[index]?.speaker
  if (!speaker) return false
  return index === 0 || lines[index - 1]?.speaker !== speaker
}

/**
 * The lines of the phone's own transcript (the JSON `getTranscript` returns: its `lines` are
 * already {start, end, text}). Null when the text is not that.
 */
export function deviceLines(json: string): TranscriptLine[] | null {
  let data: unknown
  try {
    data = JSON.parse(json)
  } catch {
    return null
  }
  const lines = (data as { lines?: unknown } | null)?.lines
  if (!Array.isArray(lines)) return null
  const result: TranscriptLine[] = []
  for (const item of lines) {
    const { start, end, text } = (item ?? {}) as Record<string, unknown>
    if (
      typeof start === "number" &&
      typeof end === "number" &&
      typeof text === "string" &&
      text !== ""
    ) {
      result.push({ start, end, text })
    }
  }
  return result.length > 0 ? result : null
}
