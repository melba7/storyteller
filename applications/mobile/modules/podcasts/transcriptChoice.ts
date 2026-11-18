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
 * Where the transcript comes from: the phone's own when it is finished, or still being made
 * and already covering the playhead (`partialCovers`), else the feed's, else why there is
 * none. The feed's is timed against the publisher's cut, but the audio that plays has ads
 * inserted, so its lines drift: it is only the fallback when the phone has nothing to show.
 */
export function transcriptSource(input: {
  feedUrl: string | null
  feedType: string | null
  device: TranscriptInfo | undefined
  partialCovers?: boolean
}): TranscriptSource {
  if (input.device?.state === "done") return { kind: "device" }
  if (input.partialCovers === true) return { kind: "device" }
  if (input.feedUrl) {
    return { kind: "feed", url: input.feedUrl, type: input.feedType ?? "" }
  }
  return deviceSource(input.device)
}

/**
 * Whether the lines saved so far of a transcript being made reach `playhead` seconds. The
 * playhead is null for an episode that is not playing: it has none, so a half-made transcript
 * never covers it and does not replace a whole feed transcript.
 */
export function partialCovers(
  lines: readonly { end: number }[] | null | undefined,
  playhead: number | null,
): boolean {
  const last = lines?.[lines.length - 1]
  return playhead !== null && last !== undefined && last.end >= playhead
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

export type DeviceChoice =
  | { kind: "finished" }
  /** Still being made: the lines saved so far may be shown. `empty` is for when there are none. */
  | { kind: "partial"; percent: number | null; empty: string }
  | { kind: "none"; reason: string }

/** The phone's own transcript: finished, being made (with its percent) or not there. */
export function deviceChoice(device: TranscriptInfo | undefined): DeviceChoice {
  if (device?.state === "done") return { kind: "finished" }
  if (device?.state === "waiting" || device?.state === "transcribing") {
    const percent =
      device.state === "transcribing" && device.percent !== undefined
        ? Math.max(0, Math.min(100, Math.floor(device.percent)))
        : null
    return {
      kind: "partial",
      percent,
      empty:
        device.state === "waiting"
          ? transcriptStatus(device)
          : `${percent === null ? "Transcribing" : `Transcribing, ${percent}%`}. The first lines appear in a minute or so.`,
    }
  }
  const none = deviceSource(device)
  return {
    kind: "none",
    reason: none.kind === "none" ? none.reason : "",
  }
}

/** The quiet line under the lines of a transcript that is still being made. */
export function partialFooter(percent: number | null): string {
  return `${percent === null ? "Transcribing" : `Transcribing, ${percent}%`}. More lines appear as it goes.`
}

/** A fetched transcript is kept this long. */
export const TRANSCRIPT_CACHE_MS = 7 * 24 * 60 * 60 * 1000

export function transcriptCacheFresh(savedAt: number, now: number): boolean {
  return now - savedAt >= 0 && now - savedAt < TRANSCRIPT_CACHE_MS
}

export function transcriptCacheKey(url: string): string {
  return `transcript:${url}`
}
