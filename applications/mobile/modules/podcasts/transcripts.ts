// LOFI-FORK: the podcasts section's transcripts (see FORK.md).
//
// What a row says about an episode's transcript and how a change from Swift updates what the
// screens know. The transcribing itself is Swift (PodcastTranscripts); not imported by any
// test that needs the native module.
import type { TranscriptChange, TranscriptInfo } from "./index"

/** What the screens know about transcripts, by episode id. */
export type TranscriptMap = Readonly<Record<string, TranscriptInfo>>

/** The map after a change from Swift. A removed transcript leaves the map. */
export function applyTranscriptChange(
  map: TranscriptMap,
  change: TranscriptChange,
): TranscriptMap {
  if (change.state === "none") {
    if (!(change.episodeId in map)) return map
    const { [change.episodeId]: _removed, ...rest } = map
    return rest
  }
  return { ...map, [change.episodeId]: change }
}

export function transcriptMapFromList(
  list: readonly TranscriptInfo[],
): TranscriptMap {
  return Object.fromEntries(list.map((info) => [info.episodeId, info]))
}

/** What a row says about the transcript; empty when there is nothing to say. */
export function transcriptStatus(info: TranscriptInfo | undefined): string {
  if (!info) return ""
  switch (info.state) {
    case "waiting":
      return "Waiting to transcribe"
    case "transcribing":
      return info.percent === undefined
        ? "Transcribing"
        : `Transcribing ${Math.max(0, Math.min(100, Math.floor(info.percent)))}%`
    case "done":
      return "Transcript ready"
    case "unsupported":
      return info.reason ?? "Language not supported"
    case "failed":
      return info.reason ?? "Transcribing failed"
  }
}

/** The download's line followed by the transcript's, as the episode row writes them. */
export function withTranscript(
  downloadStatus: string,
  info: TranscriptInfo | undefined,
): string {
  return [downloadStatus, transcriptStatus(info)]
    .filter((part) => part !== "")
    .join(" · ")
}
