// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useEffect, useState, useSyncExternalStore } from "react"

import {
  type AdsFile,
  type KeptAds,
  type AdsMap,
  adsMapFromList,
  adsFileAfterRead,
  applyAdsChange,
  parseAdsFile,
  readsAdsFile,
  unavailableReason,
} from "@/modules/podcasts/ads"
import { getAds, listAds } from "@/modules/podcasts/adsNative"
import { type AdsInfo, Podcasts } from "@/modules/podcasts/index"

// What the screens know about ad finding: read once from Swift, then kept fresh by its
// onAdsChange event. One copy is shared by every screen.
let current: AdsMap = {}
// Counts the changes the listener made to the saved ads (a skip undone, an ad trimmed), so a
// list of ads reads its file again.
let undoneCount = 0
let started = false
const listeners = new Set<() => void>()

function publish(next: AdsMap) {
  current = next
  for (const listener of [...listeners]) listener()
}

function start() {
  if (started || Podcasts === null) return
  started = true
  // Listening comes first, so a change during the first read is not lost.
  Podcasts.addListener("onAdsChange", (change) =>
    publish(applyAdsChange(current, change)),
  )
  Podcasts.addListener("onAdUndone", adsEdited)
  listAds().then(
    (list) => publish({ ...adsMapFromList(list), ...current }),
    (cause: unknown) => {
      started = false
      console.warn("Couldn't read the ad states", cause)
    },
  )
}

/** The listener changed the saved ads (a skip undone, an ad trimmed): lists read them again. */
export function adsEdited() {
  undoneCount += 1
  publish(current)
}

function subscribe(listener: () => void): () => void {
  start()
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

/** One episode's ad finding state, or undefined when it has none. */
export function useAdsInfo(episodeId: string): AdsInfo | undefined {
  return useSyncExternalStore(subscribe, () => current[episodeId])
}

/** Why ads can't be found on this phone, or null. */
export function useAdsUnavailable(): string | null {
  return useSyncExternalStore(subscribe, () => unavailableReason(current))
}

/** One episode's saved ads, read again whenever its ad finding changes. */
export function useAdsFile(episodeId: string): AdsFile | null {
  const info = useAdsInfo(episodeId)
  const undone = useSyncExternalStore(subscribe, () => undoneCount)
  const [kept, setKept] = useState<KeptAds | null>(null)
  // The full pass keeps the ads found so far on show (the partial file is read meanwhile).
  const reads = readsAdsFile(info)
  const state = info?.state
  const count = info?.count
  useEffect(() => {
    if (!reads) {
      setKept(null)
      return
    }
    let cancelled = false
    getAds(episodeId).then(
      (json) => {
        if (cancelled) return
        const read = json === null ? null : parseAdsFile(json)
        setKept((last) => ({
          episodeId,
          file: adsFileAfterRead(state, last, episodeId, read),
        }))
      },
      (cause: unknown) => console.warn("Couldn't read the ads", cause),
    )
    return () => {
      cancelled = true
    }
  }, [episodeId, reads, state, count, undone])
  // A file read for the episode shown before this one is never handed on.
  return kept !== null && kept.episodeId === episodeId ? kept.file : null
}
