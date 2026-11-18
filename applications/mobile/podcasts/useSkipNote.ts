// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useSyncExternalStore } from "react"

import {
  SKIP_NOTE_MS,
  type SkipNote,
  noteAfterUndo,
  skipNote,
} from "@/modules/podcasts/ads"
import { backAfterSkip, undoAdSkip } from "@/modules/podcasts/adsNative"
import { Podcasts } from "@/modules/podcasts/index"

import { adsEdited } from "./useAds"

// The "Skipped ad" note: set by Swift's onAdSkipped, gone after six seconds or when the skip
// is undone. One copy is shared by every screen that shows it.
let current: SkipNote | null = null
let timer: ReturnType<typeof setTimeout> | null = null
let started = false
const listeners = new Set<() => void>()

function publish(next: SkipNote | null) {
  current = next
  if (timer !== null) clearTimeout(timer)
  timer = next === null ? null : setTimeout(() => publish(null), SKIP_NOTE_MS)
  for (const listener of [...listeners]) listener()
}

function start() {
  if (started || Podcasts === null) return
  started = true
  Podcasts.addListener("onAdSkipped", (event) =>
    publish(skipNote(event, Date.now())),
  )
  Podcasts.addListener("onAdUndone", (event) =>
    publish(noteAfterUndo(current, event)),
  )
}

function subscribe(listener: () => void): () => void {
  start()
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

/** The note to show now, or null. It goes by itself after six seconds. */
export function useSkipNote(): SkipNote | null {
  return useSyncExternalStore(subscribe, () => current)
}

/** Undo: back to the ad's start, playing. The note goes when Swift says it was undone. */
export function pressUndo() {
  undoAdSkip().then(
    (done) => {
      if (!done) publish(null)
    },
    (cause: unknown) => console.warn("Couldn't undo the skip", cause),
  )
}

/** Back 10 s: the skip went too far. Swift saves the trim, the note goes, ad lists read again. */
export function pressBack() {
  backAfterSkip().then(
    () => {
      publish(null)
      adsEdited()
    },
    (cause: unknown) => console.warn("Couldn't go back after the skip", cause),
  )
}
