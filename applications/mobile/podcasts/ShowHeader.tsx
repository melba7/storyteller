// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Link } from "expo-router"
import { useHeaderHeight } from "expo-router/react-navigation"
import { Check, Plus } from "lucide-react-native"
import { useEffect, useMemo, useState } from "react"
import {
  ActivityIndicator,
  Pressable,
  View,
  useWindowDimensions,
} from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { headerColors } from "@/modules/podcasts/artworkTint"
import { needsMore } from "@/modules/podcasts/episodeLook"
import {
  showCaption,
  showPlayTarget,
  stripHtml,
  updateFrequency,
} from "@/modules/podcasts/episodeRowLook"
import { type Show, type StoredEpisode } from "@/modules/podcasts/library"
import { showHeaderSide } from "@/modules/podcasts/pageFrame"

import { Artwork } from "./Artwork"
import { HeaderCapsule } from "./HeaderCapsule"
import { pressEpisode, useEpisodeStatus } from "./PlayButton"
import { useArtworkColor } from "./useWash"

interface Props {
  show: Show
  problem: string | null
  /** Called when the listener taps the check (following); the screen asks to confirm. */
  onUnfollow?: () => void
  /** For a show not in the library yet: the "+" follows. Also makes the capsule say "Play". */
  onFollow?: () => void
  /** The follow is being saved. */
  busy?: boolean
  /** The show's episodes, for the capsule and "Weekly". */
  episodes?: readonly StoredEpisode[] | null | undefined
  /**
   * Called with how far down the list (counted from where the bar ends) the picture ends, once
   * it is known. The screen shows the bar's title once the list has scrolled that far.
   */
  onTitleBottom?: (bottom: number) => void
}

/** A round button drawn on the colour: translucent white, the way glass looks on it. */
function GlassCircle({
  label,
  busy,
  onPress,
  children,
}: {
  label: string
  busy?: boolean
  onPress?: (() => void) | undefined
  children: React.ReactElement
}) {
  return (
    <Pressable
      className="size-12 items-center justify-center rounded-full bg-white/25 active:opacity-70"
      accessibilityRole="button"
      accessibilityLabel={label}
      disabled={busy}
      onPress={onPress}
    >
      {busy ? <ActivityIndicator color="#ffffff" /> : children}
    </Pressable>
  )
}

/** The white capsule: Latest Episode, Resume or Play. */
function PlayCapsuleWhite({
  show,
  episodes,
  preview,
  color,
}: {
  show: Show
  episodes: readonly StoredEpisode[]
  preview: boolean
  color: string
}) {
  const target = useMemo(() => showPlayTarget(episodes), [episodes])
  const status = useEpisodeStatus(target?.episode.id ?? "")
  const playing = status === "playing"
  const label = playing
    ? "Pause"
    : preview
      ? "Play"
      : target?.kind === "resume"
        ? "Resume"
        : "Latest Episode"
  return (
    <HeaderCapsule
      label={label}
      accessibilityLabel={`${label}, ${show.title}`}
      status={status}
      color={color}
      disabled={!target}
      onPress={() =>
        target ? pressEpisode(target.episode, show, status) : undefined
      }
    />
  )
}

/**
 * The top of a show's page, as in Apple's app: the artwork across the whole top edge, under
 * the status bar and the transparent bar, a white play capsule and a round "+" (a check when
 * followed) at its bottom edge, then the artwork's colour carrying on with the description
 * (two lines and a bold MORE) and a tinted line of category, how often and author.
 */
export function ShowHeader({
  show,
  problem,
  onUnfollow,
  onFollow,
  busy = false,
  episodes = null,
  onTitleBottom,
}: Props) {
  const { width, height } = useWindowDimensions()
  // The picture is a square as wide as the window on a phone in portrait; on a wide or low
  // window it is capped, so the episodes stay in reach. The colour fills the rest of the width.
  const side = showHeaderSide(width, height)
  const headerHeight = useHeaderHeight()
  const [expanded, setExpanded] = useState(false)
  const description = useMemo(
    () => stripHtml(show.description),
    [show.description],
  )
  const long = needsMore(description)
  // A preview's show isn't in the database, so its colour is measured but not saved.
  const { background, tint } = headerColors(useArtworkColor(show, !onFollow))
  const preview = Boolean(onFollow)
  const list = episodes ?? []
  const caption = showCaption(
    show.categories,
    updateFrequency(
      list.map((episode) => episode.publishedAt),
      Date.now(),
    ),
    show.author,
  )

  useEffect(() => {
    onTitleBottom?.(side - headerHeight)
  }, [onTitleBottom, side, headerHeight])

  return (
    // The list's automatic inset puts the first row below the bar: pull the picture up under it.
    <View style={{ backgroundColor: background, marginTop: -headerHeight }}>
      {/* Pulling the list down past its top shows the colour, not the page. */}
      <View
        pointerEvents="none"
        style={{
          position: "absolute",
          top: -1200,
          left: 0,
          right: 0,
          height: 1200,
          backgroundColor: background,
        }}
      />
      <View style={{ width, height: side, alignItems: "center" }}>
        <View style={{ width: side, height: side }}>
          {/* Only the picture is the header for VoiceOver: the buttons below stay reachable. */}
          <View
            accessible
            accessibilityRole="header"
            accessibilityLabel={show.title}
          >
            <Link.AppleZoomTarget>
              <Artwork
                uri={show.imageUrl}
                size={side}
                className="rounded-none border-0"
              />
            </Link.AppleZoomTarget>
          </View>
          <View
            pointerEvents="none"
            style={{
              position: "absolute",
              left: 0,
              right: 0,
              bottom: 0,
              height: side * 0.3,
              backgroundImage: `linear-gradient(180deg, transparent, ${background})`,
            }}
          />
          <View className="absolute right-0 bottom-3 left-0 flex-row items-center justify-center gap-3">
            <PlayCapsuleWhite
              show={show}
              episodes={list}
              preview={preview}
              color={background}
            />
            {onFollow ? (
              <GlassCircle
                label={`Follow ${show.title}`}
                busy={busy}
                onPress={onFollow}
              >
                <Icon as={Plus} size={26} className="text-white" />
              </GlassCircle>
            ) : (
              <GlassCircle
                label={`Following ${show.title}. Tap to unfollow`}
                onPress={onUnfollow}
              >
                <Icon as={Check} size={26} className="text-white" />
              </GlassCircle>
            )}
          </View>
        </View>
      </View>
      <View className="px-safe-or-4 gap-3 pt-4 pb-5">
        {description ? (
          <View className="gap-1">
            <View className="flex-row items-end gap-2">
              <Text
                className="flex-1 text-[19px] leading-6"
                style={{ color: "#ffffff" }}
                numberOfLines={expanded ? undefined : 2}
              >
                {description}
              </Text>
              {long && !expanded ? (
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel="Show more of the description"
                  onPress={() => setExpanded(true)}
                >
                  <Text
                    className="text-[17px] font-bold"
                    style={{ color: "#ffffff" }}
                  >
                    MORE
                  </Text>
                </Pressable>
              ) : null}
            </View>
            {long && expanded ? (
              <Pressable
                className="self-end"
                accessibilityRole="button"
                accessibilityLabel="Show less of the description"
                onPress={() => setExpanded(false)}
              >
                <Text
                  className="text-[17px] font-bold"
                  style={{ color: "#ffffff" }}
                >
                  LESS
                </Text>
              </Pressable>
            ) : null}
          </View>
        ) : null}
        {caption ? (
          <Text
            className="text-[19px] font-semibold"
            style={{ color: tint }}
            numberOfLines={2}
          >
            {caption}
          </Text>
        ) : null}
        {problem ? (
          <Text
            className="text-[15px] font-semibold"
            style={{ color: "#ffd0cc" }}
            accessibilityRole="alert"
          >
            {problem}
          </Text>
        ) : null}
      </View>
    </View>
  )
}
