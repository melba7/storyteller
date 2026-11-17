// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import { CircleArrowDown, Ellipsis, Pause, Play } from "lucide-react-native"
import { Pressable, View } from "react-native"

import { Text } from "@/components/ui/text"
import { downloadLook } from "@/modules/podcasts/downloads"
import { ringFraction } from "@/modules/podcasts/episodeLook"
import { type ShelfEntry } from "@/modules/podcasts/home"
import {
  cardLine,
  cardPalette,
  plainText,
  timeLeftLabel,
} from "@/modules/podcasts/homeLook"
import { type Show } from "@/modules/podcasts/library"
import { isLocalEpisodeId } from "@/modules/podcasts/localFiles"
import { isPreviewId } from "@/modules/podcasts/preview"
import { episodeHref } from "@/modules/podcasts/routes"

import { Artwork } from "./Artwork"
import { EpisodeMenu } from "./EpisodeMenu"
import { pressEpisode, useEpisodeStatus } from "./PlayButton"
import { PressableScale } from "./PressableScale"
import { useDownload, pressDownload } from "./useDownloads"
import { useArtworkColor } from "./useWash"

/** A card's width and height for a window width: two thirds across, a third taller than wide. */
export function cardSize(windowWidth: number) {
  const width = Math.round(windowWidth * 0.66)
  return { width, height: Math.round(width * 1.34) }
}

/** What a card shows when its show's colour is not known yet. */
const NEUTRAL = "#48484a"

/**
 * One card of Home's Up Next shelf: the artwork fading into its own colour, a line such as
 * "New · 17h ago", the title, a line of the notes, then the play capsule (with a short bar for
 * an episode in progress and the time left), a download button and the "..." menu. The card
 * opens the episode; the capsule plays it.
 */
export function UpNextCard({
  entry,
  show,
  width,
  height,
  now,
}: {
  entry: ShelfEntry
  show: Show
  width: number
  height: number
  now: number
}) {
  const router = useRouter()
  const segments = useSegments()
  const { episode } = entry
  const color = useArtworkColor(show)
  const palette = cardPalette(color ?? NEUTRAL)
  const status = useEpisodeStatus(episode.id)
  const download = useDownload(episode.id)
  const look = downloadLook(download, episode.title)
  // An added file is its own only copy, and a preview episode has no download.
  const canDownload =
    !isLocalEpisodeId(episode.id) &&
    !isPreviewId(episode.id) &&
    look.icon !== "done"
  const fraction = ringFraction(episode)
  const started = fraction !== null && fraction > 0
  const left = timeLeftLabel(episode.durationSeconds, episode.positionSeconds)
  const line = cardLine(entry, now)
  const playing = status === "playing"

  return (
    <PressableScale
      style={{
        width,
        height,
        borderRadius: 16,
        overflow: "hidden",
        backgroundColor: palette.background,
      }}
      accessibilityRole="button"
      accessibilityLabel={`${episode.title}, ${show.title}. ${line}`}
      onPress={() => router.push(episodeHref(segments, episode.id))}
    >
      <Artwork
        uri={episode.imageUrl ?? show.imageUrl}
        size={width}
        className="rounded-none border-0"
      />
      {/* The artwork's lower part fades into the card's colour. */}
      <View
        pointerEvents="none"
        style={{
          position: "absolute",
          top: width * 0.4,
          left: 0,
          right: 0,
          height: width * 0.6 + 1,
          backgroundImage: `linear-gradient(180deg, ${palette.background}00, ${palette.background})`,
        }}
      />
      <View
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          bottom: 0,
          padding: 14,
        }}
      >
        <Text
          className="text-sm font-semibold"
          style={{ color: palette.label }}
          numberOfLines={1}
        >
          {line}
        </Text>
        <Text
          className="mt-0.5 text-xl leading-6 font-bold"
          style={{ color: palette.text }}
          numberOfLines={3}
        >
          {episode.title}
        </Text>
        <Text
          className="mt-0.5 text-base"
          style={{ color: palette.text, opacity: 0.85 }}
          numberOfLines={1}
        >
          {plainText(episode.notes)}
        </Text>
        <View className="mt-3 flex-row items-center gap-2">
          <Pressable
            className="h-10 flex-row items-center gap-2 rounded-full px-3.5"
            style={{ backgroundColor: palette.capsule }}
            accessibilityRole="button"
            accessibilityLabel={`${playing ? "Pause" : "Play"} ${episode.title}${left ? `, ${left}` : ""}`}
            onPress={() => pressEpisode(episode, show, status)}
          >
            {playing ? (
              <Pause size={18} color={palette.text} fill={palette.text} />
            ) : (
              <Play size={18} color={palette.text} fill={palette.text} />
            )}
            {started ? (
              <View
                style={{
                  width: 32,
                  height: 4,
                  borderRadius: 2,
                  overflow: "hidden",
                  backgroundColor: palette.capsule,
                }}
              >
                <View
                  style={{
                    width: `${Math.round((fraction ?? 0) * 100)}%`,
                    height: 4,
                    backgroundColor: palette.text,
                  }}
                />
              </View>
            ) : null}
            {left ? (
              <Text
                className="text-base font-bold"
                style={{ color: palette.text }}
              >
                {left}
              </Text>
            ) : null}
          </Pressable>
          <View className="flex-1" />
          {canDownload ? (
            <Pressable
              className="size-10 items-center justify-center"
              accessibilityRole="button"
              accessibilityLabel={look.label}
              onPress={() => pressDownload(look.action, episode)}
            >
              <CircleArrowDown size={24} color={palette.text} />
            </Pressable>
          ) : null}
          <EpisodeMenu episode={episode} show={show} tint={palette.background}>
            <View
              className="size-10 items-center justify-center"
              accessibilityRole="button"
              accessibilityLabel={`More for ${episode.title}`}
            >
              <Ellipsis size={24} color={palette.text} />
            </View>
          </EpisodeMenu>
        </View>
      </View>
    </PressableScale>
  )
}
