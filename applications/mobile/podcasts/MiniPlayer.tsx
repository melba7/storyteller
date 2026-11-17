// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter } from "expo-router"
import { NativeTabs } from "expo-router/native-tabs"
import { Pause, Play } from "lucide-react-native"
import { ActivityIndicator, Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { skipNoteText } from "@/modules/podcasts/ads"
import { showsMiniPlayer, timeLeft } from "@/modules/podcasts/playbackRules"
import {
  player,
  usePlayer,
  usePlayerValue,
  useRestoreLastEpisode,
} from "@/modules/podcasts/playerInstance"
import { progressFraction } from "@/modules/podcasts/playerLook"

import { Artwork } from "./Artwork"
import { pressUndo, useSkipNote } from "./useSkipNote"

/**
 * Whether the tab bar should carry the mini player: an episode is loaded or one was played
 * before (the last one comes back after the app restarts). Call it in the tabs layout.
 */
export function useHasMiniPlayer(): boolean {
  useRestoreLastEpisode()
  return usePlayerValue((view) => showsMiniPlayer(view.episode, null))
}

/**
 * What sits in the tab bar's accessory: the artwork, the title and a play button. Tap it to
 * open the full-screen player. The full row also says the time left; the compact one (shown
 * when the tab bar is minimized) leaves it out.
 */
export function MiniPlayerContent() {
  const router = useRouter()
  const view = usePlayer()
  const compact = NativeTabs.BottomAccessory.usePlacement() === "inline"
  const note = useSkipNote()
  const { episode, show } = view
  if (!episode) return null

  return (
    <View className="flex-1 justify-center">
      <View className="flex-row items-center gap-3 px-4">
        <Pressable
          className="flex-1 flex-row items-center gap-3"
          accessibilityRole="button"
          accessibilityLabel={`Open the player, ${episode.title}`}
          onPress={() => router.push("/podcasts/player")}
        >
          <Artwork
            uri={episode.imageUrl ?? show?.imageUrl ?? null}
            size={compact ? 32 : 40}
          />
          <View className="flex-1">
            <Text
              className={compact ? "text-sm font-semibold" : "font-semibold"}
              numberOfLines={1}
            >
              {episode.title}
            </Text>
            {compact ? null : (
              <Text className="text-muted-foreground text-sm" numberOfLines={1}>
                {view.error ??
                  (note
                    ? skipNoteText(note)
                    : timeLeft(view.position, view.duration))}
              </Text>
            )}
          </View>
        </Pressable>
        {note ? (
          <Pressable
            className="bg-secondary rounded-full px-3 py-1.5 active:opacity-60"
            accessibilityRole="button"
            accessibilityLabel="Undo the ad skip"
            onPress={pressUndo}
          >
            <Text className="text-sm font-semibold">Undo</Text>
          </Pressable>
        ) : null}
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
              size={compact ? 22 : 26}
              fill="currentColor"
            />
          )}
        </Pressable>
      </View>
      {compact ? null : (
        <View className="bg-foreground/10 absolute right-4 bottom-0 left-4 h-0.5 rounded-full">
          <View
            className="bg-primary h-0.5 rounded-full"
            style={{
              width: `${progressFraction(view.position, view.duration) * 100}%`,
            }}
          />
        </View>
      )}
    </View>
  )
}
