// LOFI-FORK: the podcasts section's transcript readers (see FORK.md).
//
// Podcasting 2.0 JSON: {"version": "1.0.0", "segments": [{"speaker", "startTime", "endTime",
// "body"}]}, times in seconds. A plain list of {"start", "end", "text"} in milliseconds, which
// Transcriptator also reads, is accepted too.
import { type TranscriptLine, TranscriptFormatError } from "./types"

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function seconds(value: unknown): number | null {
  const number = typeof value === "string" ? Number(value) : value
  return typeof number === "number" && Number.isFinite(number) && number >= 0
    ? number
    : null
}

function line(
  item: unknown,
  keys: { start: string; end: string; text: string; scale: number },
): { start: number; end: number; speaker?: string; text: string } | null {
  if (!isRecord(item)) return null
  const start = seconds(item[keys.start])
  const end = seconds(item[keys.end])
  const text = item[keys.text]
  if (start === null || end === null || typeof text !== "string") return null
  const speaker = item["speaker"]
  const clean = text.replace(/\s+/g, " ").trim()
  if (clean === "") return null
  return {
    start: start / keys.scale,
    end: end / keys.scale,
    ...(typeof speaker === "string" && speaker.trim() !== ""
      ? { speaker: speaker.trim() }
      : {}),
    text: clean,
  }
}

export function parseJson(text: string): TranscriptLine[] {
  let data: unknown
  try {
    data = JSON.parse(text.replace(/^﻿/, ""))
  } catch {
    throw new TranscriptFormatError("This isn't a JSON transcript.")
  }
  const keys =
    isRecord(data) && Array.isArray(data["segments"])
      ? { start: "startTime", end: "endTime", text: "body", scale: 1 }
      : { start: "start", end: "end", text: "text", scale: 1000 }
  const items = isRecord(data) ? data["segments"] : data
  if (!Array.isArray(items)) {
    throw new TranscriptFormatError("This JSON isn't a transcript.")
  }
  const lines: TranscriptLine[] = []
  let last: string | undefined
  for (const item of items) {
    const found = line(item, keys)
    if (!found || found.end < found.start) continue
    last = found.speaker ?? last
    lines.push(
      last === undefined
        ? { start: found.start, end: found.end, text: found.text }
        : {
            start: found.start,
            end: found.end,
            speaker: last,
            text: found.text,
          },
    )
  }
  if (lines.length === 0) {
    throw new TranscriptFormatError(
      "This transcript has no lines that can be read.",
    )
  }
  return lines.sort((a, b) => a.start - b.start)
}
