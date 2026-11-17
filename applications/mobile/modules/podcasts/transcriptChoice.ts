// LOFI-FORK: the podcasts section's transcripts (see FORK.md).
//
// Which of an episode's feed transcripts to keep, where the transcript to show comes from,
// and how long a fetched one is kept. Plain rules, no native module.
import type { TranscriptInfo } from "./index"
import { kindOfType } from "./transcriptFormats"
import { transcriptStatus } from "./transcripts"

export type FeedTranscript = {
  url: string
  type: string
  language?: string
  rel?: string
}

/** JSON first, then WebVTT, then SRT, then HTML. Plain text and unknown types are skipped. */
const ORDER = ["json", "vtt", "srt", "html"] as const

/**
 * The transcript to keep for an episode: the first of the best format, in feed order. Null
 * when the feed has none we can use.
 */
export function chooseTranscript(
  transcripts: readonly FeedTranscript[] | null | undefined,
): { url: string; type: string } | null {
  for (const kind of ORDER) {
    const found = (transcripts ?? []).find(
      (transcript) =>
        transcript.url !== "" && kindOfType(transcript.type) === kind,
    )
    if (found) return { url: found.url, type: found.type }
  }
  return null
}

export type TranscriptSource =
  | { kind: "feed"; url: string; type: string }
  | { kind: "device" }
  | { kind: "none"; reason: string }

/**
 * Where the transcript comes from: the feed's when it has one (it also works while
 * streaming), else the one made on the phone, else why there is none.
 */
export function transcriptSource(input: {
  feedUrl: string | null
  feedType: string | null
  device: TranscriptInfo | undefined
}): TranscriptSource {
  if (input.feedUrl) {
    return { kind: "feed", url: input.feedUrl, type: input.feedType ?? "" }
  }
  return deviceSource(input.device)
}

/** The phone's own transcript, or the reason there is none. */
export function deviceSource(
  device: TranscriptInfo | undefined,
): TranscriptSource {
  if (device?.state === "done") return { kind: "device" }
  if (!device) {
    return {
      kind: "none",
      reason: "No transcript yet. Download the episode to make one.",
    }
  }
  return { kind: "none", reason: transcriptStatus(device) }
}

/** A fetched transcript is kept this long. */
export const TRANSCRIPT_CACHE_MS = 7 * 24 * 60 * 60 * 1000

export function transcriptCacheFresh(savedAt: number, now: number): boolean {
  return now - savedAt >= 0 && now - savedAt < TRANSCRIPT_CACHE_MS
}

export function transcriptCacheKey(url: string): string {
  return `transcript:${url}`
}
