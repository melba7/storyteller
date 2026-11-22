// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useSyncExternalStore } from "react"
import { Alert } from "react-native"

import { readChapters } from "@/modules/podcasts/chapters"
import {
  type ChaptersInfo,
  type PodcastChapter,
  Podcasts,
} from "@/modules/podcasts/index"
import { readableError } from "@/modules/podcasts/nativeError"

// What the screens know about the loaded episode's chapters: read once from Swift, then kept
// fresh by its onChaptersChange event. One copy is shared by every screen.
let current: { episodeId: string; chapters: PodcastChapter[] } | null = null
let started = false
let listening = false
const listeners = new Set<() => void>()

function publish(info: ChaptersInfo) {
  current = { episodeId: info.episodeId, chapters: readChapters(info.chapters) }
  for (const listener of [...listeners]) listener()
}

function start() {
  if (started || Podcasts === null) return
  started = true
  // Listening comes first, so a change during the first read is not lost. It is added once,
  // even when a failed first read lets this run again.
  if (!listening) {
    listening = true
    Podcasts.addListener("onChaptersChange", publish)
  }
  Podcasts.getChapters().then(publish, () => {
    started = false
  })
}

function subscribe(listener: () => void): () => void {
  start()
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

const NONE: PodcastChapter[] = []

/** The chapters of this episode, when it is the one loaded in the player (else none). */
export function useChapters(episodeId: string): readonly PodcastChapter[] {
  return useSyncExternalStore(subscribe, () =>
    current !== null && current.episodeId === episodeId
      ? current.chapters
      : NONE,
  )
}

function run(action: Promise<void> | undefined) {
  action?.catch((cause: unknown) =>
    Alert.alert("Chapters", readableError(cause)),
  )
}

export const chapterActions = {
  previous: () => run(Podcasts?.previousChapter()),
  next: () => run(Podcasts?.nextChapter()),
  setSkipped: (episodeId: string, start: number, skipped: boolean) =>
    run(Podcasts?.setChapterSkipped(episodeId, start, skipped)),
}
