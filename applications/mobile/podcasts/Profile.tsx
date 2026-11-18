// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack, useRouter } from "expo-router"
import { StatusBar } from "expo-status-bar"
import { useEffect, useState } from "react"
import { ScrollView } from "react-native"

import { Text } from "@/components/ui/text"
import {
  type AutomaticSettings,
  DEFAULT_SETTINGS,
} from "@/modules/podcasts/automatic"
import {
  loadSettings,
  saveSettings,
} from "@/modules/podcasts/automaticSettings"
import { getWifiOnly, setWifiOnly } from "@/modules/podcasts/downloadsNative"
import { Podcasts } from "@/modules/podcasts/index"

import { AdSkipSwitches } from "./AdSkipSwitches"
import { AddAudioFilesRow } from "./AddAudioFilesRow"
import { AppearanceSection } from "./AppearanceSection"
import { AppleSyncStatus } from "./AppleSyncStatus"
import { NotifyRow } from "./NotifyRow"
import { OpmlSection } from "./OpmlSection"
import { PlaybackSection } from "./PlaybackSection"
import { BelowBar, ScreenBar } from "./ScreenBar"
import { SettingsGroup, SwitchRow } from "./SettingsGroup"
import { SkipLogRow } from "./SkipLogRow"
import { StatsCard } from "./StatsCard"
import { useStatusBarStyle } from "./usePodcastsTheme"

/**
 * Profile, the account sheet: your stats, then the settings in titled cards. Downloads,
 * History and Bookmarks are Library's rows now.
 */
export function Profile() {
  const statusBarStyle = useStatusBarStyle()
  const router = useRouter()
  const [wifiOnly, setWifi] = useState<boolean | null>(null)
  const [automatic, setAutomatic] = useState<AutomaticSettings | null>(null)

  useEffect(() => {
    let live = true
    getWifiOnly().then(
      (value) => {
        if (live) setWifi(value)
      },
      () => {
        if (live) setWifi(false)
      },
    )
    return () => {
      live = false
    }
  }, [])

  useEffect(() => {
    let live = true
    loadSettings().then((value) => {
      if (live) setAutomatic(value)
    })
    return () => {
      live = false
    }
  }, [])

  function changeAutomatic(patch: Partial<AutomaticSettings>) {
    const before = automatic ?? DEFAULT_SETTINGS
    const next = { ...before, ...patch }
    setAutomatic(next)
    saveSettings(next).catch(() => setAutomatic(before))
  }

  function change(on: boolean) {
    const before = wifiOnly
    setWifi(on)
    setWifiOnly(on).catch(() => setWifi(before))
  }

  return (
    <>
      {Podcasts === null ? (
        <BelowBar>
          <Text className="text-muted-foreground px-8 py-12 text-center">
            Downloads need the iOS app.
          </Text>
        </BelowBar>
      ) : (
        <ScrollView
          className="bg-background flex-1"
          contentContainerClassName="px-safe-or-4 pb-8"
          contentInsetAdjustmentBehavior="automatic"
        >
          <StatsCard />
          <SettingsGroup title="Downloads">
            <SwitchRow
              title="Download only on Wi-Fi"
              body="Applies to downloads you start from now on."
              checked={wifiOnly}
              onChange={change}
            />
            <SwitchRow
              title="Download new episodes"
              body="New episodes of the shows you follow download by themselves, on Wi-Fi only."
              checked={automatic?.downloadNew ?? null}
              onChange={(on) => changeAutomatic({ downloadNew: on })}
            />
            <SwitchRow
              title="Delete played downloads after a day"
              body="A download is removed a day after you played it."
              checked={automatic?.deletePlayed ?? null}
              onChange={(on) => changeAutomatic({ deletePlayed: on })}
            />
            <NotifyRow />
          </SettingsGroup>
          <PlaybackSection />
          <AppearanceSection />
          <SettingsGroup title="Your files">
            <AddAudioFilesRow />
          </SettingsGroup>
          <SettingsGroup title="OPML">
            <OpmlSection />
          </SettingsGroup>
          <SettingsGroup title="Apple Podcasts">
            <AppleSyncStatus />
          </SettingsGroup>
          <SettingsGroup title="Ad skipping">
            <AdSkipSwitches />
            <SkipLogRow />
          </SettingsGroup>
        </ScrollView>
      )}
      <StatusBar style={statusBarStyle} verticalBarBehaviorIOS="disabled" />
      <ScreenBar
        large
        title="Profile"
        right={
          <Stack.Toolbar.Button
            accessibilityLabel="Done"
            onPress={() => router.dismiss()}
          >
            Done
          </Stack.Toolbar.Button>
        }
      />
    </>
  )
}
