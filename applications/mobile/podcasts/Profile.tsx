// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack, useRouter } from "expo-router"
import { StatusBar } from "expo-status-bar"
import { Bookmark, Download, History } from "lucide-react-native"
import { useEffect, useState } from "react"
import { ScrollView, View } from "react-native"

import { Text } from "@/components/ui/text"
import {
  type AutomaticSettings,
  DEFAULT_SETTINGS,
} from "@/modules/podcasts/automatic"
import {
  loadSettings,
  saveSettings,
} from "@/modules/podcasts/automaticSettings"
import { downloadsSummary } from "@/modules/podcasts/downloads"
import { getWifiOnly, setWifiOnly } from "@/modules/podcasts/downloadsNative"
import { Podcasts } from "@/modules/podcasts/index"

import { AdSkipSwitches } from "./AdSkipSwitches"
import { AddAudioFilesRow } from "./AddAudioFilesRow"
import { AppearanceSection } from "./AppearanceSection"
import { NotifyRow } from "./NotifyRow"
import { OpmlSection } from "./OpmlSection"
import { PlaybackSection } from "./PlaybackSection"
import { BelowBar, ScreenBar } from "./ScreenBar"
import { SectionMenuButton } from "./SectionMenu"
import { LinkRow, SettingsGroup, SwitchRow } from "./SettingsGroup"
import { StatsCard } from "./StatsCard"
import { useDownloadMap } from "./useDownloads"
import { useStatusBarStyle } from "./usePodcastsTheme"

/** The Profile tab: your stats, then the settings in titled cards. */
export function Profile() {
  const statusBarStyle = useStatusBarStyle()
  const router = useRouter()
  const map = useDownloadMap()
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

  const summary = downloadsSummary(map)

  return (
    <View className="bg-background flex-1">
      <StatusBar style={statusBarStyle} verticalBarBehaviorIOS="disabled" />
      <ScreenBar
        large
        title="Profile"
        left={
          <Stack.Toolbar.View>
            <SectionMenuButton current="podcasts" />
          </Stack.Toolbar.View>
        }
      />
      {Podcasts === null ? (
        <BelowBar>
          <Text className="text-muted-foreground px-8 py-12 text-center">
            Downloads need the iOS app.
          </Text>
        </BelowBar>
      ) : (
        <ScrollView
          contentContainerClassName="px-safe-or-4 pb-8"
          contentInsetAdjustmentBehavior="automatic"
        >
          <StatsCard />
          <SettingsGroup title="Library">
            <LinkRow
              icon={Download}
              title="Downloads"
              body={summary}
              label={`Downloads, ${summary}`}
              onPress={() =>
                router.push("/podcasts/(tabs)/(profile)/downloads")
              }
            />
            <LinkRow
              icon={History}
              title="Listening history"
              body="What you listened to, by day."
              label="Listening history"
              onPress={() => router.push("/podcasts/(tabs)/(profile)/history")}
            />
            <LinkRow
              icon={Bookmark}
              title="Bookmarks"
              body="Places you marked, in every episode."
              label="Bookmarks"
              onPress={() =>
                router.push("/podcasts/(tabs)/(profile)/bookmarks")
              }
            />
          </SettingsGroup>
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
          <SettingsGroup title="Ad skipping">
            <AdSkipSwitches />
          </SettingsGroup>
        </ScrollView>
      )}
    </View>
  )
}
