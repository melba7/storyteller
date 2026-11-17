// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter } from "expo-router"
import { NativeTabs } from "expo-router/native-tabs"
import { Pause, Play, RotateCw } from "lucide-react-native"
import { ActivityIndicator, Pressable, View } from "react-native"

import { Text } from "@/components/ui/text"
import { skipNoteText } from "@/modules/podcasts/ads"
import {
  miniPlayerLabel,
  showsMiniPlayer,
} from "@/modules/podcasts/playbackRules"
import { skipLabel } from "@/modules/podcasts/playbackSettings"
import {
  player,
  usePlayer,
  usePlayerValue,
  useRestoreLastEpisode,
} from "@/modules/podcasts/playerInstance"
import { skipSymbol } from "@/modules/podcasts/playerLook"
import { miniSubtitle } from "@/modules/podcasts/playerSheet"

import { Artwork } from "./Artwork"
import { SFIcon } from "./SFIcon"
import { tap } from "./haptics"
import { usePlaybackSettings } from "./usePlaybackSettings"
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
 * What sits in the tab bar's accessory: small rounded artwork, the title in bold with the
 * episode's date under it in the plain text colour, a play button and skip forward. Tap it to
 * open the full-screen player. The compact row (shown when the tab bar is minimized) keeps the
 * two lines at a smaller size and leaves skip forward out. A long title ends in "..." because
 * the accessory is glass, so there is no known colour for a fade to end in.
 *
 * The player still slides up as a modal. Link.AppleZoom zooms only from a Link's own trigger
 * into a pushed screen of the same navigator, and the accessory is drawn by the native tab bar
 * outside the stack, so there is no trigger to zoom from (and it can't be tried without a
 * device).
 */
export function MiniPlayerContent() {
  const router = useRouter()
  const view = usePlayer()
  const compact = NativeTabs.BottomAccessory.usePlacement() === "inline"
  const note = useSkipNote()
  const { skipForward } = usePlaybackSettings()
  const { episode, show } = view
  if (!episode) return null

  return (
    <View className="flex-1 justify-center">
      <View className="flex-row items-center gap-3 px-[9px]">
        <Pressable
          className="flex-1 flex-row items-center gap-3"
          accessibilityRole="button"
          accessibilityLabel={miniPlayerLabel(
            episode.title,
            view.position,
            view.duration,
          )}
          onPress={() => router.push("/podcasts/player")}
        >
          <Artwork
            uri={episode.imageUrl ?? show?.imageUrl ?? null}
            size={compact ? 30 : 40}
            className="rounded-lg border-0"
          />
          <View className="flex-1">
            <Text
              className={compact ? "text-sm font-bold" : "font-bold"}
              numberOfLines={1}
            >
              {episode.title}
            </Text>
            <Text className={compact ? "text-xs" : "text-sm"} numberOfLines={1}>
              {view.error ??
                (note ? skipNoteText(note) : miniSubtitle(episode.publishedAt))}
            </Text>
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
          onPress={() => {
            tap()
            void player.togglePlayPause()
          }}
        >
          {view.isBuffering ? (
            <ActivityIndicator accessibilityLabel="Buffering" />
          ) : (
            <SFIcon
              name={view.isPlaying ? "pause.fill" : "play.fill"}
              size={compact ? 22 : 26}
              fallback={view.isPlaying ? Pause : Play}
              filled
            />
          )}
        </Pressable>
        {compact ? null : (
          <Pressable
            className="size-11 items-center justify-center active:opacity-60"
            accessibilityRole="button"
            accessibilityLabel={skipLabel("ahead", skipForward)}
            onPress={() => {
              tap()
              void player.skip(skipForward)
            }}
          >
            <SFIcon
              name={skipSymbol("ahead", skipForward)}
              size={28}
              fallback={RotateCw}
              badge={skipForward}
            />
          </Pressable>
        )}
      </View>
    </View>
  )
}
