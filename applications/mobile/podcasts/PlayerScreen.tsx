// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { useRouter } from "expo-router"
import {
  ChevronDown,
  Pause,
  Play,
  RotateCcw,
  RotateCw,
} from "lucide-react-native"
import { useState } from "react"
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  View,
  useWindowDimensions,
} from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import {
  SKIP_AHEAD_SECONDS,
  SKIP_BACK_SECONDS,
  speedLabel,
} from "@/modules/podcasts/playbackRules"
import { player, usePlayer } from "@/modules/podcasts/playerInstance"
import { playerBackground } from "@/modules/podcasts/playerLook"

import { Artwork } from "./Artwork"
import { PlayerButtons } from "./PlayerButtons"
import { SeekBar } from "./SeekBar"
import { SpeedPanel } from "./SpeedPanel"

/** The full-screen player, laid out like Pocket Casts': artwork, seek bar, controls, notes. */
export function PlayerScreen() {
  const router = useRouter()
  const view = usePlayer()
  const { width } = useWindowDimensions()
  const [showSpeed, setShowSpeed] = useState(false)
  const { episode, show } = view
  const artwork = Math.min(width - 64, 340)

  function close() {
    if (router.canGoBack()) router.back()
    else router.replace("/podcasts")
  }

  return (
    <View
      className="pt-safe flex-1"
      style={{ backgroundColor: playerBackground(show?.artworkColor ?? null) }}
    >
      <View className="px-safe-or-2 flex-row items-center">
        <Pressable
          className="size-11 items-center justify-center"
          accessibilityRole="button"
          accessibilityLabel="Close the player"
          onPress={close}
        >
          <Icon as={ChevronDown} size={28} className="text-white" />
        </Pressable>
      </View>

      {!episode ? (
        <Text className="px-8 py-12 text-center text-white/70">
          Nothing is playing. Pick an episode to start.
        </Text>
      ) : (
        <ScrollView
          contentContainerClassName="px-safe-or-6 pb-safe items-center gap-5 pb-8"
          showsVerticalScrollIndicator={false}
        >
          <Artwork
            uri={episode.imageUrl ?? show?.imageUrl ?? null}
            size={artwork}
            className="rounded-2xl"
          />
          <View className="w-full gap-1">
            <Text
              className="text-center text-xl font-semibold text-white"
              numberOfLines={2}
            >
              {episode.title}
            </Text>
            {show ? (
              <Text
                className="text-center text-base text-white/70"
                numberOfLines={1}
              >
                {show.title}
              </Text>
            ) : null}
          </View>

          {view.error ? (
            <Text
              className="text-center text-sm text-red-300"
              accessibilityRole="alert"
            >
              {view.error}
            </Text>
          ) : null}

          <SeekBar
            position={view.position}
            duration={view.duration}
            onSeek={(seconds) => void player.seekTo(seconds)}
          />

          <View className="w-full flex-row items-center justify-center gap-8">
            <SkipButton
              label={`Back ${SKIP_BACK_SECONDS} seconds`}
              seconds={SKIP_BACK_SECONDS}
              icon={RotateCcw}
              onPress={() => void player.skip(-SKIP_BACK_SECONDS)}
            />
            <Pressable
              className="size-20 items-center justify-center rounded-full bg-white active:opacity-80"
              accessibilityRole="button"
              accessibilityLabel={view.isPlaying ? "Pause" : "Play"}
              onPress={() => void player.togglePlayPause()}
            >
              {view.isBuffering ? (
                <ActivityIndicator
                  color="#000000"
                  accessibilityLabel="Buffering"
                />
              ) : (
                <Icon
                  as={view.isPlaying ? Pause : Play}
                  size={34}
                  className="text-black"
                  fill="#000000"
                />
              )}
            </Pressable>
            <SkipButton
              label={`Ahead ${SKIP_AHEAD_SECONDS} seconds`}
              seconds={SKIP_AHEAD_SECONDS}
              icon={RotateCw}
              onPress={() => void player.skip(SKIP_AHEAD_SECONDS)}
            />
          </View>

          <Pressable
            className="rounded-full bg-white/15 px-5 py-2 active:bg-white/25"
            accessibilityRole="button"
            accessibilityLabel={`Playback speed ${speedLabel(view.rate)}`}
            onPress={() => setShowSpeed((value) => !value)}
          >
            <Text className="font-semibold text-white">
              {speedLabel(view.rate)}
            </Text>
          </Pressable>
          {showSpeed ? (
            <View className="w-full">
              <SpeedPanel
                rate={view.rate}
                onChange={(rate) => void player.setRate(rate)}
              />
            </View>
          ) : null}

          <PlayerButtons />

          <View className="w-full gap-2 pt-4">
            <Text className="text-lg font-semibold text-white">Show notes</Text>
            <Text selectable className="text-base leading-6 text-white/85">
              {episode.notes === ""
                ? "No notes for this episode."
                : episode.notes}
            </Text>
          </View>
        </ScrollView>
      )}
    </View>
  )
}

function SkipButton({
  label,
  seconds,
  icon,
  onPress,
}: {
  label: string
  seconds: number
  icon: typeof RotateCcw
  onPress: () => void
}) {
  return (
    <Pressable
      className="size-14 items-center justify-center active:opacity-60"
      accessibilityRole="button"
      accessibilityLabel={label}
      onPress={onPress}
    >
      <Icon as={icon} size={44} className="text-white" strokeWidth={1.5} />
      <Text className="absolute text-xs font-bold text-white">{seconds}</Text>
    </Pressable>
  )
}
