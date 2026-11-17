// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useEffect, useState, useSyncExternalStore } from "react"

import {
  type AdsFile,
  type AdsMap,
  adsMapFromList,
  applyAdsChange,
  parseAdsFile,
} from "@/modules/podcasts/ads"
import { getAds, listAds } from "@/modules/podcasts/adsNative"
import { type AdsInfo, Podcasts } from "@/modules/podcasts/index"

// What the screens know about ad finding: read once from Swift, then kept fresh by its
// onAdsChange event. One copy is shared by every screen.
let current: AdsMap = {}
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
  listAds().then(
    (list) => publish({ ...adsMapFromList(list), ...current }),
    (cause: unknown) => {
      started = false
      console.warn("Couldn't read the ad states", cause)
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

/** One episode's ad finding state, or undefined when it has none. */
export function useAdsInfo(episodeId: string): AdsInfo | undefined {
  return useSyncExternalStore(subscribe, () => current[episodeId])
}

/** One episode's saved ads, read again whenever its ad finding changes. */
export function useAdsFile(episodeId: string): AdsFile | null {
  const info = useAdsInfo(episodeId)
  const [file, setFile] = useState<AdsFile | null>(null)
  const found = info?.state === "found"
  const count = info?.count
  useEffect(() => {
    if (!found) {
      setFile(null)
      return
    }
    let cancelled = false
    getAds(episodeId).then(
      (json) => {
        if (!cancelled) setFile(json === null ? null : parseAdsFile(json))
      },
      (cause: unknown) => console.warn("Couldn't read the ads", cause),
    )
    return () => {
      cancelled = true
    }
  }, [episodeId, found, count])
  return file
}
