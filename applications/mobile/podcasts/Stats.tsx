// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useCallback, useEffect, useState } from "react"
import { Alert, ScrollView, View } from "react-native"

import { Button } from "@/components/ui/button"
import { Text } from "@/components/ui/text"
import { Podcasts } from "@/modules/podcasts/index"
import {
  type Stats as StatsData,
  formatDuration,
  lastDays,
  readStats,
  savedRows,
  totalSaved,
} from "@/modules/podcasts/stats"
import { getStats, resetStats } from "@/modules/podcasts/statsNative"

import { ScreenBar } from "./ScreenBar"

const BAR_AREA = 120

/** The Stats screen: time listened, time saved in five ways, and the last 30 days. */
export function Stats() {
  const [stats, setStats] = useState<StatsData>(() => readStats(null))

  const load = useCallback(() => {
    getStats().then(setStats, () => {})
  }, [])

  useEffect(() => {
    load()
  }, [load])

  function confirmReset() {
    Alert.alert(
      "Reset stats?",
      "This clears the time you listened and the time you saved. It can't be undone.",
      [
        { text: "Cancel", style: "cancel" },
        {
          text: "Reset stats",
          style: "destructive",
          onPress: () => {
            resetStats().then(load, () =>
              Alert.alert("Couldn't reset the stats", "Try again in a moment."),
            )
          },
        },
      ],
    )
  }

  const days = lastDays(stats.days, new Date())
  return (
    <View className="pt-safe bg-background flex-1">
      <ScreenBar title="Stats" />
      {Podcasts === null ? (
        <Text className="text-muted-foreground px-8 py-12 text-center">
          Stats need the iOS app.
        </Text>
      ) : (
        <ScrollView contentContainerClassName="px-safe-or-4 pb-8">
          <View className="border-border border-b py-4">
            <Text className="text-muted-foreground text-sm">Time listened</Text>
            <Text variant="h3">{formatDuration(stats.listened)}</Text>
          </View>
          <View className="border-border border-b py-4">
            <Text className="text-muted-foreground text-sm">Time saved</Text>
            <Text variant="h3">{formatDuration(totalSaved(stats))}</Text>
            {savedRows(stats).map((row) => (
              <View key={row.key} className="flex-row justify-between pt-2">
                <Text>{row.label}</Text>
                <Text className="text-muted-foreground">
                  {formatDuration(row.seconds)}
                </Text>
              </View>
            ))}
          </View>
          <View className="py-4">
            <Text className="font-semibold">Last 30 days</Text>
            <View
              className="mt-3 flex-row items-end gap-0.5"
              style={{ height: BAR_AREA }}
              accessibilityLabel="Listening by day for the last 30 days"
            >
              {days.map((day) => (
                <View
                  key={day.key}
                  className="bg-primary flex-1 rounded-t-sm"
                  style={{ height: Math.max(day.height * BAR_AREA, 1) }}
                  accessibilityLabel={`${day.label}, ${formatDuration(day.seconds)}`}
                />
              ))}
            </View>
            <View className="mt-1 flex-row gap-0.5">
              {days.map((day) => (
                <View key={day.key} className="flex-1 items-center">
                  {day.showLabel ? (
                    <Text
                      className="text-muted-foreground w-12 text-center text-xs"
                      numberOfLines={1}
                    >
                      {day.label}
                    </Text>
                  ) : null}
                </View>
              ))}
            </View>
          </View>
          <Button variant="outline" onPress={confirmReset}>
            <Text>Reset stats</Text>
          </Button>
        </ScrollView>
      )}
    </View>
  )
}
