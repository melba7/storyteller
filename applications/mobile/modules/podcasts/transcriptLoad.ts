// LOFI-FORK: the podcasts section's transcripts (see FORK.md).
//
// Gets the lines to show: the feed's transcript file (fetched when the transcript opens and
// kept in podcasts.db's cache for a week), or the one made on the phone. Not imported by any
// test, because the database and the native module are not there; the rules are in
// transcriptChoice.ts, transcriptLines.ts and transcriptFormats/.
import { cacheGet, cachePut } from "./dbFeeds"
import type { TranscriptInfo } from "./index"
import {
  deviceChoice,
  deviceSource,
  partialCovers,
  transcriptCacheFresh,
  transcriptCacheKey,
  transcriptSource,
} from "./transcriptChoice"
import {
  type TranscriptLine,
  TranscriptFormatError,
  parseTranscript,
} from "./transcriptFormats"
import { deviceLines } from "./transcriptLines"
import { getPartialTranscript, getTranscript } from "./transcriptsNative"

export type TranscriptResult =
  | {
      lines: TranscriptLine[]
      source: "feed" | "device"
      /** The phone's transcript is still being made: its percent, or null when not known. */
      partial?: { percent: number | null }
    }
  | { lines: null; reason: string }

/** A transcript file bigger than this is not read. */
const MAX_CHARS = 5_000_000

function cachedLines(value: string): TranscriptLine[] | null {
  try {
    const lines: unknown = JSON.parse(value)
    return Array.isArray(lines) && lines.length > 0
      ? (lines as TranscriptLine[])
      : null
  } catch {
    return null
  }
}

async function fromFeed(url: string, type: string): Promise<TranscriptLine[]> {
  const key = transcriptCacheKey(url)
  const kept = await cacheGet(key).catch(() => null)
  if (kept && transcriptCacheFresh(kept.savedAt, Date.now())) {
    const lines = cachedLines(kept.value)
    if (lines) return lines
  }
  let text: string
  try {
    const response = await fetch(url)
    if (!response.ok) {
      throw new TranscriptFormatError(
        `The transcript couldn't be loaded (the server said ${response.status}).`,
      )
    }
    text = await response.text()
  } catch (cause) {
    if (cause instanceof TranscriptFormatError) throw cause
    throw new TranscriptFormatError(
      "The transcript couldn't be loaded. Check the connection and try again.",
    )
  }
  if (text.length > MAX_CHARS) {
    throw new TranscriptFormatError("This transcript is too big to open.")
  }
  const lines = parseTranscript(text, type)
  await cachePut(key, JSON.stringify(lines)).catch(() => {})
  return lines
}

async function fromDevice(episodeId: string): Promise<TranscriptLine[] | null> {
  const json = await getTranscript(episodeId)
  return json === null ? null : deviceLines(json)
}

/** The lines saved so far of a transcript being made, or the reason there are none yet. */
async function fromPartial(
  episodeId: string,
  percent: number | null,
  empty: string,
): Promise<TranscriptResult> {
  const json = await getPartialTranscript(episodeId).catch(() => null)
  const lines = json === null ? null : deviceLines(json)
  return lines
    ? { lines, source: "device", partial: { percent } }
    : { lines: null, reason: empty }
}

/**
 * The transcript to show for an episode, or why there is none. The phone's own comes first
 * when it is finished or already covers `playhead` (seconds), because the feed's is timed
 * against the publisher's cut and drifts once ads are inserted. Else the feed's; when it
 * can't be loaded or read, the phone's partial one is used if there is one, else the reason
 * is the feed's.
 */
export async function loadTranscript(episode: {
  id: string
  transcriptUrl: string | null
  transcriptType: string | null
  device: TranscriptInfo | undefined
  playhead?: number
}): Promise<TranscriptResult> {
  const choice = deviceChoice(episode.device)
  const partial =
    choice.kind === "partial"
      ? await fromPartial(episode.id, choice.percent, choice.empty)
      : null
  const source = transcriptSource({
    feedUrl: episode.transcriptUrl,
    feedType: episode.transcriptType,
    device: episode.device,
    partialCovers:
      partial?.lines != null &&
      partialCovers(partial.lines, episode.playhead ?? 0),
  })
  let reason: string | null = null
  if (source.kind === "feed") {
    try {
      return { lines: await fromFeed(source.url, source.type), source: "feed" }
    } catch (cause) {
      reason =
        cause instanceof TranscriptFormatError
          ? cause.message
          : "The transcript couldn't be opened."
    }
  }
  if (partial) {
    if (partial.lines || reason === null) return partial
    return { lines: null, reason }
  }
  const device = deviceSource(episode.device)
  if (device.kind === "device") {
    const lines = await fromDevice(episode.id).catch(() => null)
    if (lines) return { lines, source: "device" }
    return {
      lines: null,
      reason: reason ?? "The transcript couldn't be opened.",
    }
  }
  return {
    lines: null,
    reason:
      reason ??
      (device.kind === "none"
        ? device.reason
        : "The transcript couldn't be opened."),
  }
}
