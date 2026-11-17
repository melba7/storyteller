// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useEffect, useState } from "react"
import { View } from "react-native"

import { Switch } from "@/components/ui/switch"
import { Text } from "@/components/ui/text"
import {
  getAdSkipSettings,
  setAdSkipSettings,
} from "@/modules/podcasts/adsNative"
import { type AdSkipSettings } from "@/modules/podcasts/index"

/**
 * The two switches for skipping ads and the hosts' own plugs, both on until turned off. Swift
 * keeps them, so the player skips with no JavaScript running.
 */
export function AdSkipSwitches() {
  const [settings, setSettings] = useState<AdSkipSettings | null>(null)

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
      <Row
        title="Skip ads"
        body="Skips sponsor reads and other ads in downloaded episodes whose ads were found. It never skips when it is not sure."
        checked={settings?.skipAds ?? null}
        onChange={(on) => change({ skipAds: on })}
      />
      <Row
        title="Skip the hosts' own plugs"
        body="Also skips the hosts promoting their own things, such as Patreon or their other shows."
        checked={settings?.skipOwnPlugs ?? null}
        onChange={(on) => change({ skipOwnPlugs: on })}
      />
    </>
  )
}

function Row({
  title,
  body,
  checked,
  onChange,
}: {
  title: string
  body: string
  checked: boolean | null
  onChange: (on: boolean) => void
}) {
  return (
    <View className="border-border flex-row items-center gap-3 border-b py-3">
      <View className="flex-1">
        <Text className="font-semibold">{title}</Text>
        <Text className="text-muted-foreground text-sm">{body}</Text>
      </View>
      {checked === null ? null : (
        <Switch
          accessibilityLabel={title}
          checked={checked}
          onCheckedChange={onChange}
        />
      )}
    </View>
  )
}
