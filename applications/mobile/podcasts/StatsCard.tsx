// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter } from "expo-router"
import { ChevronRight } from "lucide-react-native"
import { useEffect, useState } from "react"
import { Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { ACCOUNT_STATS_HREF } from "@/modules/podcasts/routes"
import {
  type Stats,
  formatDuration,
  readStats,
  totalSaved,
} from "@/modules/podcasts/stats"
import { getStats } from "@/modules/podcasts/statsNative"

/** The card on top of Profile: time listened and time saved. Tapping it opens Stats. */
export function StatsCard() {
  const router = useRouter()
  const [stats, setStats] = useState<Stats>(() => readStats(null))
  useEffect(() => {
    let live = true
    getStats().then(
      (value) => {
        if (live) setStats(value)
      },
      () => {},
    )
    return () => {
      live = false
    }
  }, [])
  const listened = formatDuration(stats.listened)
  const saved = formatDuration(totalSaved(stats))
  return (
    <Pressable
      className="bg-secondary active:bg-foreground/10 flex-row items-center gap-3 rounded-3xl p-4"
      accessibilityRole="button"
      accessibilityLabel={`Stats. Listened ${listened}. Saved ${saved}.`}
      onPress={() => router.push(ACCOUNT_STATS_HREF)}
    >
      <Figure value={listened} label="Listened" />
      <Figure value={saved} label="Saved" />
      <Icon as={ChevronRight} size={20} className="text-muted-foreground" />
    </Pressable>
  )
}

function Figure({ value, label }: { value: string; label: string }) {
  return (
    <View className="flex-1">
      <Text
        className="text-3xl font-bold tabular-nums"
        adjustsFontSizeToFit
        numberOfLines={1}
      >
        {value}
      </Text>
      <Text className="text-muted-foreground text-sm">{label}</Text>
    </View>
  )
}
