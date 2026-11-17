// LOFI-FORK: the podcasts section's downloads (see FORK.md).
//
// The episode the player is waiting to download, shown as a card with a "Stream now" button.
// One copy is shared by every screen. Not imported by any test, so it needs no native module.
import { useSyncExternalStore } from "react"

export type PlayWait = { id: number; episodeId: string; title: string }

let current: PlayWait | null = null
let streamAskedFor = 0
const listeners = new Set<() => void>()

function publish(next: PlayWait | null) {
  current = next
  for (const listener of [...listeners]) listener()
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

/** Shows the card for a new wait. A newer wait replaces an older one. */
export function beginWait(wait: PlayWait) {
  publish(wait)
}

/** Hides the card, unless a newer wait has taken its place. */
export function endWait(id: number) {
  if (current?.id === id) publish(null)
}

/** The "Stream now" button. */
export function askToStream() {
  if (current) streamAskedFor = current.id
}

export function streamAsked(id: number): boolean {
  return streamAskedFor === id
}

export function usePlayWait(): PlayWait | null {
  return useSyncExternalStore(subscribe, () => current)
}
