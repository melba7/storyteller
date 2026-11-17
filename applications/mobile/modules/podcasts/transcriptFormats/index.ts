// LOFI-FORK: the podcasts section's transcript readers (see FORK.md).
//
// Turns a transcript file into lines. Podcasting 2.0 JSON, WebVTT and SRT are read; HTML is
// not (Transcriptator reads it with node-html-parser, a package this app does not have).
import { parseJson } from "./json"
import { parseSrt } from "./srt"
import { type TranscriptLine, TranscriptFormatError } from "./types"
import { parseVtt } from "./vtt"

export type { TranscriptLine } from "./types"
export { TranscriptFormatError } from "./types"

export type TranscriptKind = "json" | "vtt" | "srt" | "html"

/** Which format a `podcast:transcript` type names, or null for one that is not offered. */
export function kindOfType(
  type: string | null | undefined,
): TranscriptKind | null {
  const kind = (type ?? "").split(";")[0]?.trim().toLowerCase() ?? ""
  if (
    kind === "application/json" ||
    kind === "text/json" ||
    kind === "application/x-json"
  ) {
    return "json"
  }
  if (kind === "text/vtt" || kind === "text/webvtt") return "vtt"
  if (
    kind === "application/x-subrip" ||
    kind === "application/srt" ||
    kind === "text/srt" ||
    kind === "application/x-srt"
  ) {
    return "srt"
  }
  if (kind === "text/html" || kind === "application/xhtml+xml") return "html"
  return null
}

/**
 * Reads a transcript file of the given type. A file that does not look like its type is
 * read by what it starts with (servers often send the wrong type). Throws a
 * TranscriptFormatError with a message to show.
 */
export function parseTranscript(
  text: string,
  type: string | null | undefined,
): TranscriptLine[] {
  const trimmed = text.replace(/^﻿/, "").trimStart()
  const sniffed: TranscriptKind | null = trimmed.startsWith("WEBVTT")
    ? "vtt"
    : trimmed.startsWith("{") || trimmed.startsWith("[")
      ? "json"
      : null
  const kind = sniffed ?? kindOfType(type)
  switch (kind) {
    case "json":
      return parseJson(text)
    case "vtt":
      return parseVtt(text)
    case "srt":
      return parseSrt(text)
    case "html":
      throw new TranscriptFormatError(
        "This transcript is a web page, which the app can't read yet.",
      )
    case null:
      return parseSrt(text)
  }
}
