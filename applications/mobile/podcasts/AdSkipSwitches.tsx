// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useEffect, useState } from "react"

import {
  getAdSkipSettings,
  setAdSkipSettings,
} from "@/modules/podcasts/adsNative"
import { type AdSkipSettings } from "@/modules/podcasts/index"

import { SwitchRow } from "./SettingsGroup"
import { useAdsUnavailable } from "./useAds"

/**
 * What the Skip ads switch does. A streamed episode plays through its own download (on Wi-Fi
 * only, when "Download only on Wi-Fi" is on), and ads are skipped once they are found. Why
 * ads can't be found comes last, when there is a reason.
 */
function skipAdsBody(unavailable: string | null): string {
  const body =
    'Skips sponsor reads and other ads once they are found. It works while streaming too: the episode plays from its own download, which on mobile data needs "Download only on Wi-Fi" to be off. An ad it is not sure about is skipped too, and you can undo any skip.'
  return unavailable === null
    ? body
    : `${body} Ads can't be found right now: ${unavailable}`
}

/**
 * The two switches for skipping ads and the hosts' own plugs, both on until turned off. Swift
 * keeps them, so the player skips with no JavaScript running.
 */
export function AdSkipSwitches() {
  const [settings, setSettings] = useState<AdSkipSettings | null>(null)
  const unavailable = useAdsUnavailable()

  useEffect(() => {
    let live = true
    getAdSkipSettings().then(
      (value) => {
        if (live) setSettings(value)
      },
      () => {
        if (live) setSettings({ skipAds: true, skipOwnPlugs: true })
      },
    )
    return () => {
      live = false
    }
  }, [])

  function change(patch: Partial<AdSkipSettings>) {
    const before = settings
    if (before === null) return
    const next = { ...before, ...patch }
    setSettings(next)
    setAdSkipSettings(next).catch(() => setSettings(before))
  }

  return (
    <>
      <SwitchRow
        title="Skip ads"
        body={skipAdsBody(unavailable)}
        checked={settings?.skipAds ?? null}
        onChange={(on) => change({ skipAds: on })}
      />
      <SwitchRow
        title="Skip the hosts' own plugs"
        body="Also skips the hosts promoting their own things, such as Patreon or their other shows."
        checked={settings?.skipOwnPlugs ?? null}
        onChange={(on) => change({ skipOwnPlugs: on })}
      />
    </>
  )
}
