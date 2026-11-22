// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useSyncExternalStore } from "react"

import { SKIP_NOTE_MS } from "@/modules/podcasts/ads"
import { skipAdNow } from "@/modules/podcasts/adsNative"
import { Podcasts } from "@/modules/podcasts/index"
import { type MissedAdNote, missedAdNote } from "@/modules/podcasts/skipAdLook"

// The "Jumped 30 seconds" note after a tap on Skip ad where the phone knew no ad: gone after
// six seconds. One copy is shared by the button and the note.
let current: MissedAdNote | null = null
let timer: ReturnType<typeof setTimeout> | null = null
let started = false
// When the last skip was made, so a note that comes after a newer skip is not shown with it.
let lastSkipAt = 0
const listeners = new Set<() => void>()

function publish(next: MissedAdNote | null) {
  current = next
  if (timer !== null) clearTimeout(timer)
  timer = next === null ? null : setTimeout(() => publish(null), SKIP_NOTE_MS)
  for (const listener of [...listeners]) listener()
}

function start() {
  if (started || Podcasts === null) return
  started = true
  // A skip or an undo has its own note: two notes are never shown together.
  Podcasts.addListener("onAdSkipped", () => {
    lastSkipAt = Date.now()
    publish(null)
  })
  Podcasts.addListener("onAdUndone", () => publish(null))
}

function subscribe(listener: () => void): () => void {
  start()
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

/** The note to show now, or null. */
export function useMissedNote(): MissedAdNote | null {
  return useSyncExternalStore(subscribe, () => current)
}

/** The Skip ad button was tapped: the note appears only when the phone knew no ad there. */
export function pressSkipAd() {
  const pressedAt = Date.now()
  skipAdNow().then(
    (answer) => {
      if (lastSkipAt >= pressedAt) return
      publish(missedAdNote(answer, Date.now()))
    },
    (cause: unknown) => console.warn("Couldn't skip the ad", cause),
  )
}
