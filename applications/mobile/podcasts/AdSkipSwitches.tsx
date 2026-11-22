// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useEffect, useState } from "react"

import { AD_SWITCHES } from "@/modules/podcasts/adSwitches"
import {
  getAdSkipSettings,
  setAdSkipSettings,
} from "@/modules/podcasts/adsNative"
import { type AdSkipSettings } from "@/modules/podcasts/index"

import { SwitchRow } from "./SettingsGroup"
import { useAdsUnavailable } from "./useAds"

/**
 * What the sponsor ads switch says: what it skips, and that a streamed episode plays through its
 * own download (on Wi-Fi only, when "Download only on Wi-Fi" is on) because ads are skipped
 * once they are found. Why ads can't be found comes last, when there is a reason.
 */
function sponsorBody(base: string, unavailable: string | null): string {
  const body = `${base} It works while streaming too: the episode plays from its own download, which on mobile data needs "Download only on Wi-Fi" to be off. An ad it is not sure about is skipped too, and you can undo any skip.`
  return unavailable === null
    ? body
    : `${body} Ads can't be found right now: ${unavailable}`
}

/**
 * The four switches for skipping: sponsor ads, the hosts' own plugs, promos, and intros and
 * credits (the last one off until turned on). Swift keeps them, so the player skips with no
 * JavaScript running.
 */
export function AdSkipSwitches() {
  const [settings, setSettings] = useState<AdSkipSettings | null>(null)
  const unavailable = useAdsUnavailable()

  // When the read fails the switches stay hidden, so no tap can write defaults over what is
  // saved; the read is tried again after a few seconds.
  const [attempt, setAttempt] = useState(0)

  useEffect(() => {
    let live = true
    let retry: ReturnType<typeof setTimeout> | null = null
    getAdSkipSettings().then(
      (value) => {
        if (live) setSettings(value)
      },
      () => {
        if (live) retry = setTimeout(() => setAttempt((n) => n + 1), 3000)
      },
    )
    return () => {
      live = false
      if (retry !== null) clearTimeout(retry)
    }
  }, [attempt])

  function change(patch: Partial<AdSkipSettings>) {
    if (settings === null) return
    const next = { ...settings, ...patch }
    setSettings(next)
    // After a failure the switches show what is saved, not what was tapped.
    setAdSkipSettings(next).catch(() => {
      getAdSkipSettings().then(setSettings, () => setSettings(null))
    })
  }

  return (
    <>
      {AD_SWITCHES.map((row) => (
        <SwitchRow
          key={row.key}
          title={row.title}
          body={
            row.key === "skipAds"
              ? sponsorBody(row.body, unavailable)
              : row.body
          }
          checked={settings?.[row.key] ?? null}
          onChange={(on) =>
            change({ [row.key]: on } as Partial<AdSkipSettings>)
          }
        />
      ))}
    </>
  )
}
