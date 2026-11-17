// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { Pause, Play, RotateCcw, RotateCw } from "lucide-react-native"
import { useEffect } from "react"
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  View,
  useWindowDimensions,
} from "react-native"
import Animated, {
  useAnimatedStyle,
  useReducedMotion,
  useSharedValue,
  withSpring,
} from "react-native-reanimated"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { adMarks, adRows } from "@/modules/podcasts/ads"
import { chapterArtwork } from "@/modules/podcasts/chapters"
import type { PodcastChapter } from "@/modules/podcasts/index"
import { skipLabel } from "@/modules/podcasts/playbackSettings"
import { player, type usePlayer } from "@/modules/podcasts/playerInstance"

import { Artwork } from "./Artwork"
import { ChapterBar } from "./ChapterBar"
import { PlayerToolbar } from "./PlayerToolbar"
import { SeekBar } from "./SeekBar"
import { SkippedAdNote } from "./SkippedAdNote"
import { tap } from "./haptics"
import { useAdsFile } from "./useAds"
import { usePlaybackSettings } from "./usePlaybackSettings"

const PAUSED_SCALE = 0.88

/** The Now Playing page: artwork, title, seek bar, transport and the toolbar. */
export function PlayerNowPlaying({
  view,
  chapters,
  onOpenChapters,
}: {
  view: ReturnType<typeof usePlayer>
  chapters: readonly PodcastChapter[]
  onOpenChapters: () => void
}) {
  const { skipBack, skipForward } = usePlaybackSettings()
  const { width } = useWindowDimensions()
  const { episode, show } = view
  const adsFile = useAdsFile(episode?.id ?? "")
  const marks = adsFile ? adMarks(adRows(adsFile), view.duration) : []
  const size = Math.min(width - 48, 360)
  const reduceMotion = useReducedMotion()
  const scale = useSharedValue(view.isPlaying ? 1 : PAUSED_SCALE)
  useEffect(() => {
    const target = view.isPlaying ? 1 : PAUSED_SCALE
    scale.set(reduceMotion ? target : withSpring(target))
  }, [view.isPlaying, reduceMotion, scale])
  const artworkStyle = useAnimatedStyle(() => ({
    transform: [{ scale: scale.get() }],
  }))
  if (!episode) return null

  return (
    <>
      <ScrollView
        contentContainerClassName="px-safe-or-6 items-center gap-5 pb-6"
        showsVerticalScrollIndicator={false}
      >
        <Animated.View
          className="rounded-2xl"
          style={[
            { width: size, height: size },
            { boxShadow: "0 16px 40px rgba(0,0,0,0.35)" },
            artworkStyle,
          ]}
        >
          <Artwork
            uri={
              chapterArtwork(chapters, view.position) ??
              episode.imageUrl ??
              show?.imageUrl ??
              null
            }
            size={size}
            className="rounded-2xl"
          />
        </Animated.View>
        <View className="w-full gap-1">
          <Text
            className="text-2xl font-bold tracking-tight text-white"
            numberOfLines={2}
          >
            {episode.title}
          </Text>
          {show ? (
            <Text className="text-base text-white/70" numberOfLines={1}>
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
          marks={marks}
        />
        <ChapterBar
          chapters={chapters}
          position={view.position}
          onOpen={onOpenChapters}
        />
        <SkippedAdNote />

        <View className="w-full flex-row items-center justify-center gap-8">
          <SkipButton
            label={skipLabel("back", skipBack)}
            seconds={skipBack}
            icon={RotateCcw}
            onPress={() => {
              tap()
              void player.skip(-skipBack)
            }}
          />
          <Pressable
            className="size-20 items-center justify-center rounded-full bg-white active:opacity-80"
            accessibilityRole="button"
            accessibilityLabel={view.isPlaying ? "Pause" : "Play"}
            onPress={() => {
              tap()
              void player.togglePlayPause()
            }}
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
            label={skipLabel("ahead", skipForward)}
            seconds={skipForward}
            icon={RotateCw}
            onPress={() => {
              tap()
              void player.skip(skipForward)
            }}
          />
        </View>
      </ScrollView>
      <View className="px-safe-or-4 pb-safe-offset-3 pt-2">
        <PlayerToolbar />
      </View>
    </>
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
