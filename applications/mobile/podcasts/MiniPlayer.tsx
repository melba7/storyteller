// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter } from "expo-router"
import { NativeTabs } from "expo-router/native-tabs"
import { Pause, Play, RotateCw } from "lucide-react-native"
import { ActivityIndicator, Pressable, View } from "react-native"
import { useCSSVariable } from "uniwind"

import { Text } from "@/components/ui/text"
import { skipNoteText } from "@/modules/podcasts/ads"
import {
  miniPlayerLabel,
  showsMiniPlayer,
} from "@/modules/podcasts/playbackRules"
import { skipLabel } from "@/modules/podcasts/playbackSettings"
import { openPlayer } from "@/modules/podcasts/playerGate"
import {
  player,
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
 * open the full-screen player: the row dims under the finger and gives a light tap, and the
 * player gate (playerGate.ts) opens one player however often it is tapped. The compact row
 * (shown when the tab bar is minimized) keeps the two lines at a smaller size and leaves skip
 * forward out. A long title ends in "..." because the accessory is glass, so there is no known
 * colour for a fade to end in.
 *
 * The player still slides up as a modal. Link.AppleZoom zooms only from a Link's own trigger
 * into a pushed screen of the same navigator, and the accessory is drawn by the native tab bar
 * outside the stack, so there is no trigger to zoom from (and it can't be tried without a
 * device).
 */
export function MiniPlayerContent() {
  const router = useRouter()
  // The player's state is read in pieces: each is a plain value, so this row draws again only
  // when one of them changes, not at every tick of the clock. The spoken label is built in the
  // selector, so it changes only when the minutes left do.
  const title = usePlayerValue((view) => view.episode?.title ?? null)
  const label = usePlayerValue((view) =>
    view.episode
      ? miniPlayerLabel(view.episode.title, view.position, view.duration)
      : null,
  )
  const artwork = usePlayerValue(
    (view) => view.episode?.imageUrl ?? view.show?.imageUrl ?? null,
  )
  const publishedAt = usePlayerValue(
    (view) => view.episode?.publishedAt ?? null,
  )
  const error = usePlayerValue((view) => view.error)
  const isPlaying = usePlayerValue((view) => view.isPlaying)
  const isBuffering = usePlayerValue((view) => view.isBuffering)
  const compact = NativeTabs.BottomAccessory.usePlacement() === "inline"
  const note = useSkipNote()
  const { skipForward } = usePlaybackSettings()
  // The symbols take the title's colour; left out, iOS would draw them in its own label colour,
  // which is the wrong one under a fixed dark or light Appearance.
  const ink = useCSSVariable("--color-foreground") as string
  if (title === null) return null

  return (
    <View className="flex-1 justify-center">
      <View className="flex-row items-center gap-3 px-[9px]">
        <Pressable
          testID="podcasts-mini-player"
          className="flex-1 flex-row items-center gap-3 active:opacity-60"
          accessibilityRole="button"
          accessibilityLabel={label ?? undefined}
          onPress={() => {
            tap()
            openPlayer(router)
          }}
        >
          <Artwork
            uri={artwork}
            size={compact ? 30 : 40}
            className="rounded-lg border-0"
          />
          <View className="flex-1">
            <Text
              className={compact ? "text-sm font-bold" : "font-bold"}
              numberOfLines={1}
              maxFontSizeMultiplier={1.15}
            >
              {title}
            </Text>
            <Text
              className={compact ? "text-xs" : "text-sm"}
              numberOfLines={1}
              maxFontSizeMultiplier={1.15}
            >
              {error ?? (note ? skipNoteText(note) : miniSubtitle(publishedAt))}
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
            <Text
              className="text-sm font-semibold"
              maxFontSizeMultiplier={1.15}
            >
              Undo
            </Text>
          </Pressable>
        ) : null}
        <Pressable
          className="size-11 items-center justify-center"
          accessibilityRole="button"
          accessibilityLabel={isPlaying ? "Pause" : "Play"}
          onPress={() => {
            tap()
            void player.togglePlayPause()
          }}
        >
          {isBuffering ? (
            <ActivityIndicator accessibilityLabel="Buffering" />
          ) : (
            <SFIcon
              name={isPlaying ? "pause.fill" : "play.fill"}
              size={compact ? 22 : 26}
              color={ink}
              fallback={isPlaying ? Pause : Play}
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
              color={ink}
              fallback={RotateCw}
              badge={skipForward}
            />
          </Pressable>
        )}
      </View>
    </View>
  )
}
