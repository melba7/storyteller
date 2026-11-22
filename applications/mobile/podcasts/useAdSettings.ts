// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useEffect, useState } from "react"

import {
  DEFAULT_AD_SKIP_SETTINGS,
  effectiveAdSettings,
} from "@/modules/podcasts/ads"
import {
  getAdSkipSettings,
  onAdSkipSettingsChanged,
} from "@/modules/podcasts/adsNative"
import type { AdSkipSettings } from "@/modules/podcasts/index"
import type { Show } from "@/modules/podcasts/library"

// The last value read, so a screen draws right away and does not change a moment later.
let lastMain: AdSkipSettings | null = null

/**
 * The listener's four switches, read again when they are saved or when `key` changes. Null
 * until the first read; the last value read is kept when a read fails.
 */
export function useMainAdSettings(key: string = ""): AdSkipSettings | null {
  const [main, setMain] = useState(lastMain)
  const [round, setRound] = useState(0)
  useEffect(() => onAdSkipSettingsChanged(() => setRound((r) => r + 1)), [])
  useEffect(() => {
    let live = true
    getAdSkipSettings().then(
      (value) => {
        lastMain = value
        if (live) setMain(value)
      },
      () => {},
    )
    return () => {
      live = false
    }
  }, [key, round])
  return main
}

/**
 * The four switches as they apply to one show: the show's own choices over the listener's.
 * The defaults stand in until the switches are read.
 */
export function useEffectiveAdSettings(
  show: Pick<Show, "settings"> | null,
): AdSkipSettings {
  const main = useMainAdSettings()
  return effectiveAdSettings(
    main ?? DEFAULT_AD_SKIP_SETTINGS,
    show?.settings,
  )
}
