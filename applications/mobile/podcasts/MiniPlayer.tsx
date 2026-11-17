// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter } from "expo-router"
import { Pause, Play } from "lucide-react-native"
import { ActivityIndicator, Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { showsMiniPlayer, timeLeft } from "@/modules/podcasts/playback"
import {
  player,
  usePlayer,
  useRestoreLastEpisode,
} from "@/modules/podcasts/playerInstance"
import { progressFraction } from "@/modules/podcasts/playerLook"

import { Artwork } from "./Artwork"

/**
 * The bar at the bottom of the Podcasts screens: the artwork, the title, the time left and a
 * play button. Tap it to open the full-screen player. It shows once an episode is loaded or
 * one was played before (the last one comes back after the app restarts).
 */
export function MiniPlayer() {
  const router = useRouter()
  const view = usePlayer()
  useRestoreLastEpisode()
  const { episode, show } = view
  if (!episode || !showsMiniPlayer(episode, null)) return null

  return (
    <View className="bg-secondary border-border pb-safe border-t">
      <View className="bg-foreground/10 h-0.5">
        <View
          className="bg-primary h-0.5"
          style={{
            width: `${progressFraction(view.position, view.duration) * 100}%`,
          }}
        />
      </View>
      <View className="px-safe-or-4 flex-row items-center gap-3 py-2">
        <Pressable
          className="flex-1 flex-row items-center gap-3"
          accessibilityRole="button"
          accessibilityLabel={`Open the player, ${episode.title}`}
          onPress={() => router.push("/podcasts/player")}
        >
          <Artwork uri={episode.imageUrl ?? show?.imageUrl ?? null} size={44} />
          <View className="flex-1">
            <Text className="font-semibold" numberOfLines={1}>
              {episode.title}
            </Text>
            <Text className="text-muted-foreground text-sm" numberOfLines={1}>
              {view.error ?? timeLeft(view.position, view.duration)}
            </Text>
          </View>
        </Pressable>
        <Pressable
          className="size-11 items-center justify-center"
          accessibilityRole="button"
          accessibilityLabel={view.isPlaying ? "Pause" : "Play"}
          onPress={() => void player.togglePlayPause()}
        >
          {view.isBuffering ? (
            <ActivityIndicator accessibilityLabel="Buffering" />
          ) : (
            <Icon
              as={view.isPlaying ? Pause : Play}
              size={26}
              fill="currentColor"
            />
          )}
        </Pressable>
      </View>
    </View>
  )
}
