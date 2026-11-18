// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useSyncExternalStore } from "react"
import { Alert } from "react-native"

import { Podcasts, type UpNextItem } from "@/modules/podcasts/index"
import { type Show, type StoredEpisode } from "@/modules/podcasts/library"
import { readableError } from "@/modules/podcasts/nativeError"
import { orderAfterMove, queuedLabel } from "@/modules/podcasts/upNext"
import {
  clearUpNext,
  listUpNext,
  moveInUpNext,
  queueEpisode,
  removeFromUpNext,
  requeue,
} from "@/modules/podcasts/upNextNative"

// What the screens know about Up Next: read once from Swift, then kept fresh by its
// onUpNextChange event. One copy is shared by every screen.
let current: readonly UpNextItem[] = []
let started = false
const listeners = new Set<() => void>()

function publish(next: readonly UpNextItem[]) {
  current = next
  for (const listener of [...listeners]) listener()
}

/** Reads the queue from Swift again (after something went wrong, to show the truth). */
function reread() {
  listUpNext().then(publish, (cause: unknown) => {
    console.warn("Couldn't read Up Next", cause)
  })
}

function start() {
  if (started || Podcasts === null) return
  started = true
  // Listening comes first, so a change during the first read is not lost.
  Podcasts.addListener("onUpNextChange", (change) => publish(change.items))
  listUpNext().then(publish, (cause: unknown) => {
    started = false
    console.warn("Couldn't read Up Next", cause)
  })
}

function subscribe(listener: () => void): () => void {
  start()
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

/** The queue, in play order. */
export function useUpNext(): readonly UpNextItem[] {
  return useSyncExternalStore(subscribe, () => current)
}

/**
 * One episode's place in the queue as a row says it ("Up Next, number 2"), or "" when it is
 * not queued. Draws again only when that text changes, not at every change of the queue.
 */
export function useQueued(episodeId: string): string {
  return useSyncExternalStore(subscribe, () => queuedLabel(current, episodeId))
}

function tell(title: string, cause: unknown) {
  Alert.alert(title, readableError(cause))
}

/** Puts an episode at the top or bottom of Up Next. */
export function addToUpNext(
  episode: StoredEpisode,
  show: Show | null,
  place: "next" | "last",
) {
  queueEpisode(episode, show, place).catch((cause: unknown) =>
    tell("Couldn't add to Up Next", cause),
  )
}

/** Moves a queued episode to the top or bottom. */
export function moveToEnd(item: UpNextItem, place: "next" | "last") {
  requeue(item, place).catch((cause: unknown) =>
    tell("Couldn't move the episode", cause),
  )
}

export function removeQueued(id: string) {
  removeFromUpNext(id).catch((cause: unknown) =>
    tell("Couldn't remove the episode", cause),
  )
}

/** Moves one episode and shows the new order at once; Swift confirms it with its event. */
export function moveQueued(from: number, to: number) {
  publish(orderAfterMove(current, from, to))
  moveInUpNext(from, to).catch((cause: unknown) => {
    reread()
    tell("Couldn't move the episode", cause)
  })
}

/** Asks first, then empties Up Next. */
export function confirmClear(count: number) {
  Alert.alert(
    "Clear Up Next?",
    `This takes ${count === 1 ? "the episode" : `all ${count} episodes`} out of Up Next. Downloads and your places are kept.`,
    [
      { text: "Cancel", style: "cancel" },
      {
        text: "Clear",
        style: "destructive",
        onPress: () => {
          clearUpNext().catch((cause: unknown) =>
            tell("Couldn't clear Up Next", cause),
          )
        },
      },
    ],
  )
}
