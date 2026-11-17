// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter } from "expo-router"
import { StatusBar } from "expo-status-bar"
import { ChevronRight, Download } from "lucide-react-native"
import { useEffect, useState } from "react"
import { Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Switch } from "@/components/ui/switch"
import { Text } from "@/components/ui/text"
import { downloadsSummary } from "@/modules/podcasts/downloads"
import { getWifiOnly, setWifiOnly } from "@/modules/podcasts/downloadsNative"
import { Podcasts } from "@/modules/podcasts/index"

import { ScreenBar } from "./ScreenBar"
import { SectionMenuButton } from "./SectionMenu"
import { useDownloadMap } from "./useDownloads"

/** The Profile tab: Downloads (how many and how much room they take) and Wi-Fi only. */
export function Profile() {
  const router = useRouter()
  const map = useDownloadMap()
  const [wifiOnly, setWifi] = useState<boolean | null>(null)

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
        </View>
      )}
    </View>
  )
}
