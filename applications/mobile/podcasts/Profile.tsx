// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter } from "expo-router"
import { StatusBar } from "expo-status-bar"
import { ChevronRight, Download } from "lucide-react-native"
import { useEffect, useState } from "react"
import { Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Switch } from "@/components/ui/switch"
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
import { NotifyRow } from "./NotifyRow"
import { OpmlSection } from "./OpmlSection"
import { PlaybackSection } from "./PlaybackSection"
import { ScreenBar } from "./ScreenBar"
import { SectionMenuButton } from "./SectionMenu"
import { useDownloadMap } from "./useDownloads"

/** The Profile tab: Downloads (how many and how much room they take) and Wi-Fi only. */
export function Profile() {
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
    <View className="pt-safe bg-background flex-1">
      <StatusBar verticalBarBehaviorIOS="disabled" />
      <ScreenBar
        title="Profile"
        left={<SectionMenuButton current="podcasts" />}
      />
      {Podcasts === null ? (
        <Text className="text-muted-foreground px-8 py-12 text-center">
          Downloads need the iOS app.
        </Text>
      ) : (
        <View className="px-safe-or-4">
          <Pressable
            className="border-border active:bg-secondary flex-row items-center gap-3 border-b py-4"
            accessibilityRole="button"
            accessibilityLabel={`Downloads, ${summary}`}
            onPress={() => router.push("/podcasts/(tabs)/(profile)/downloads")}
          >
            <Icon as={Download} size={22} className="text-primary" />
            <View className="flex-1">
              <Text className="font-semibold">Downloads</Text>
              <Text className="text-muted-foreground text-sm">{summary}</Text>
            </View>
            <Icon
              as={ChevronRight}
              size={20}
              className="text-muted-foreground"
            />
          </Pressable>
          <View className="border-border flex-row items-center gap-3 border-b py-3">
            <View className="flex-1">
              <Text className="font-semibold">Download only on Wi-Fi</Text>
              <Text className="text-muted-foreground text-sm">
                Applies to downloads you start from now on.
              </Text>
            </View>
            {wifiOnly === null ? null : (
              <Switch
                accessibilityLabel="Download only on Wi-Fi"
                checked={wifiOnly}
                onCheckedChange={change}
              />
            )}
          </View>
          <SettingRow
            title="Download new episodes"
            body="New episodes of the shows you follow download by themselves, on Wi-Fi only."
            checked={automatic?.downloadNew ?? null}
            onChange={(on) => changeAutomatic({ downloadNew: on })}
          />
          <SettingRow
            title="Delete played downloads after a day"
            body="A download is removed a day after you played it."
            checked={automatic?.deletePlayed ?? null}
            onChange={(on) => changeAutomatic({ deletePlayed: on })}
          />
          <NotifyRow />
          <PlaybackSection />
          <AddAudioFilesRow />
          <OpmlSection />
          <AdSkipSwitches />
        </View>
      )}
    </View>
  )
}

function SettingRow({
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
