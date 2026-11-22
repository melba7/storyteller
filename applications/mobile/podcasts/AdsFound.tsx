// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Play } from "lucide-react-native"
import { Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { adRows } from "@/modules/podcasts/ads"
import { type Show, type StoredEpisode } from "@/modules/podcasts/library"
import { player } from "@/modules/podcasts/playerInstance"

import { useEffectiveAdSettings } from "./useAdSettings"
import { useAdsFile } from "./useAds"

/**
 * The "Ads found" list on the episode card: when each ad is, how long, what kind, who and its
 * first words, with a button that plays from the ad's start so the listener can check it.
 * Nothing when no ads were found.
 */
export function AdsFound({
  episode,
  show,
}: {
  episode: StoredEpisode
  show: Show | null
}) {
  const file = useAdsFile(episode.id)
  const settings = useEffectiveAdSettings(show)
  const rows = file ? adRows(file, settings) : []
  if (rows.length === 0) return null
  return (
    <View className="w-full gap-1 pt-2">
      <Text className="text-lg font-bold" accessibilityRole="header">
        Ads found
      </Text>
      {rows.map((row) => (
        <View
          key={row.key}
          className="border-foreground/10 flex-row items-center gap-3 border-b py-2"
        >
          <View className="flex-1 gap-0.5">
            <Text className="text-sm font-medium">
              {[`${row.time} · ${row.length}`, row.kind, row.advertiser]
                .filter((part) => part !== "")
                .join(" · ")}
            </Text>
            {row.firstWords ? (
              <Text className="text-muted-foreground text-sm" numberOfLines={2}>
                {row.firstWords}
              </Text>
            ) : null}
            {row.undone || row.unsure ? (
              <Text className="text-muted-foreground text-xs">
                {row.undone ? "Skip undone" : "Not sure"}
              </Text>
            ) : null}
          </View>
          <Pressable
            className="bg-secondary h-10 w-10 items-center justify-center rounded-full active:opacity-60"
            accessibilityRole="button"
            accessibilityLabel={`Play from ${row.time}. ${row.label}`}
            onPress={() => void player.playFrom(episode, show, row.start)}
          >
            <Icon as={Play} size={18} className="text-foreground" />
          </Pressable>
        </View>
      ))}
    </View>
  )
}
