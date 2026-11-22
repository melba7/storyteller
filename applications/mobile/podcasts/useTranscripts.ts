// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useSyncExternalStore } from "react"

import { type TranscriptInfo, Podcasts } from "@/modules/podcasts/index"
import {
  type TranscriptMap,
  applyTranscriptChange,
  transcriptMapFromList,
} from "@/modules/podcasts/transcripts"
import { listTranscripts } from "@/modules/podcasts/transcriptsNative"

// What the screens know about transcripts: read once from Swift, then kept fresh by its
// onTranscriptChange event. One copy is shared by every screen.
let current: TranscriptMap = {}
let started = false
let listening = false
const listeners = new Set<() => void>()

function publish(next: TranscriptMap) {
  current = next
  for (const listener of [...listeners]) listener()
}

function start() {
  if (started || Podcasts === null) return
  started = true
  // Listening comes first, so a change during the first read is not lost. It is added once,
  // even when a failed first read lets this run again.
  if (!listening) {
    listening = true
    Podcasts.addListener("onTranscriptChange", (change) =>
      publish(applyTranscriptChange(current, change)),
    )
  }
  listTranscripts().then(
    (list) => publish({ ...transcriptMapFromList(list), ...current }),
    (cause: unknown) => {
      started = false
      console.warn("Couldn't read the transcripts", cause)
    },
  )
}

function subscribe(listener: () => void): () => void {
  start()
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

/** One episode's transcript state, or undefined when it has none. */
export function useTranscript(episodeId: string): TranscriptInfo | undefined {
  return useSyncExternalStore(subscribe, () => current[episodeId])
}
