// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Link, useRouter, useSegments } from "expo-router"
import { useHeaderHeight } from "expo-router/react-navigation"
import { StatusBar } from "expo-status-bar"
import { ActivityIndicator, Pressable, ScrollView, View } from "react-native"

import { Text } from "@/components/ui/text"
import { headerColors } from "@/modules/podcasts/artworkTint"
import { currentChapterIndex } from "@/modules/podcasts/chapters"
import {
  capsuleLook,
  dateWords,
  seasonEpisode,
} from "@/modules/podcasts/episodeRowLook"
import { peopleForEpisode } from "@/modules/podcasts/people"
import { formatTime } from "@/modules/podcasts/playbackRules"
import { player, usePlayer } from "@/modules/podcasts/playerInstance"
import { showHref } from "@/modules/podcasts/routes"

import { AdsFound } from "./AdsFound"
import { Artwork } from "./Artwork"
import { DownloadStatusLine } from "./DownloadButton"
import { EpisodeActions } from "./EpisodeActions"
import { EpisodeBookmarks } from "./EpisodeBookmarks"
import { EpisodePeople } from "./EpisodePeople"
import { HeaderCapsule } from "./HeaderCapsule"
import { LinkedNotes } from "./LinkedNotes"
import { pressEpisode, useEpisodeStatus } from "./PlayButton"
import { BelowBar, ScreenBar } from "./ScreenBar"
import { useEpisode, useShow } from "./hooks"
import { useChapters } from "./useChapters"
import { useArtworkColor } from "./useWash"

const ARTWORK = 200

/** The chapters of the episode when it is the one the player has loaded; a tap plays one. */
function EpisodeChapters({ episodeId }: { episodeId: string }) {
  const chapters = useChapters(episodeId)
  const view = usePlayer()
  if (chapters.length === 0) return null
  const playing =
    view.episode?.id === episodeId
      ? currentChapterIndex(chapters, view.position)
      : -1
  return (
    <View className="w-full gap-1">
      <Text className="text-[22px] font-bold" accessibilityRole="header">
        Chapters
      </Text>
      {chapters.map((chapter, index) => (
        <Pressable
          key={chapter.start}
          className="active:bg-secondary min-h-11 flex-row items-center justify-between gap-3 rounded-md py-2"
          accessibilityRole="button"
          accessibilityLabel={`Play chapter ${chapter.title} from ${formatTime(chapter.start)}`}
          onPress={() => {
            void player.seekTo(chapter.start)
            if (!view.isPlaying) void player.togglePlayPause()
          }}
        >
          <Text
            className={`flex-1 ${index === playing ? "text-primary font-bold" : ""}`}
            numberOfLines={2}
          >
            {chapter.title}
          </Text>
          <Text className="text-muted-foreground text-sm">
            {formatTime(chapter.start)}
          </Text>
        </Pressable>
      ))}
    </View>
  )
}

/**
 * The episode page, as in Apple's app: the show's colour across the top with the episode's
 * artwork (smaller, centred, rounded), the date line, the title in bold white, the show's name
 * in a tint (it opens the show), a white Play capsule with the length or time left and a row of
 * round buttons; then, on the page's own background, the notes (links open), the chapters, hosts
 * and guests, support links, bookmarks and the ads found.
 */
export function PodcastEpisode({ id }: { id: string }) {
  const router = useRouter()
  const segments = useSegments()
  const headerHeight = useHeaderHeight()
  const episode = useEpisode(id)
  const show = useShow(episode.data?.showId ?? "")
  const current = episode.data
  const status = useEpisodeStatus(id)
  const { background, tint } = headerColors(useArtworkColor(show.data ?? null))

  if (episode.loading) {
    return (
      <>
        <BelowBar>
          <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
        </BelowBar>
        <ScreenBar title="Episode" titleHidden />
      </>
    )
  }
  if (!current) {
    return (
      <>
        <BelowBar>
          <Text className="text-muted-foreground px-8 py-12 text-center">
            {episode.error ?? "This episode isn't in your library."}
          </Text>
        </BelowBar>
        <ScreenBar title="Episode" titleHidden />
      </>
    )
  }

  const playing = status === "playing"
  const look = capsuleLook(current)
  const started = !current.played && current.positionSeconds > 0
  const label = playing ? "Pause" : started ? "Resume" : "Play"
  const dateLine = [
    dateWords(current.publishedAt, Date.now()),
    seasonEpisode(current.season, current.number),
    current.played ? "Played" : "",
  ]
    .filter((part) => part !== "")
    .join(" · ")

  return (
    <>
      <ScrollView
        className="bg-background flex-1"
        contentInsetAdjustmentBehavior="automatic"
      >
        <View
          className="px-safe-or-4 items-center gap-3 pb-6"
          style={{
            backgroundColor: background,
            marginTop: -headerHeight,
            paddingTop: headerHeight + 24,
          }}
        >
          {/* Pulling down past the top shows the colour, not the page. */}
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
          <View
            className="rounded-2xl"
            style={{ boxShadow: "0 8px 24px rgba(0, 0, 0, 0.3)" }}
          >
            <Link.AppleZoomTarget>
              <Artwork
                uri={current.imageUrl ?? show.data?.imageUrl ?? null}
                size={ARTWORK}
                className="rounded-2xl"
              />
            </Link.AppleZoomTarget>
          </View>
          {dateLine ? (
            <Text className="text-[15px] font-semibold" style={{ color: tint }}>
              {dateLine}
            </Text>
          ) : null}
          <Text
            className="text-center text-[26px] font-bold"
            style={{ color: "#ffffff" }}
            accessibilityRole="header"
          >
            {current.title}
          </Text>
          {show.data ? (
            <Pressable
              accessibilityRole="link"
              accessibilityLabel={`Open the show ${show.data.title}`}
              onPress={() =>
                show.data
                  ? router.push(showHref(segments, show.data.id))
                  : undefined
              }
            >
              <Text
                className="text-center text-[19px] font-semibold"
                style={{ color: tint }}
                numberOfLines={2}
              >
                {show.data.title}
              </Text>
            </Pressable>
          ) : null}
          <HeaderCapsule
            label={look.label ? `${label} · ${look.spoken}` : label}
            accessibilityLabel={[label, look.spoken]
              .filter((part) => part !== "")
              .join(", ")}
            status={status}
            color={background}
            onPress={() => pressEpisode(current, show.data ?? null, status)}
          />
          <EpisodeActions episode={current} show={show.data ?? null} />
        </View>
        <View className="px-safe-or-4 gap-4 pt-5 pb-8">
          <DownloadStatusLine episode={current} />
          <View className="w-full gap-2">
            <Text className="text-[22px] font-bold" accessibilityRole="header">
              Notes
            </Text>
            {current.notes === "" ? (
              <Text className="text-muted-foreground">
                No notes for this episode.
              </Text>
            ) : (
              <LinkedNotes notes={current.notes} />
            )}
          </View>
          <EpisodeChapters episodeId={current.id} />
          <EpisodePeople
            people={peopleForEpisode(current, show.data)}
            funding={show.data?.funding ?? []}
          />
          <EpisodeBookmarks episode={current} show={show.data ?? null} />
          <AdsFound episode={current} show={show.data ?? null} />
        </View>
      </ScrollView>
      {/* The episode's colour is under the bar: white clock and battery. */}
      <StatusBar style="light" verticalBarBehaviorIOS="disabled" />
      <ScreenBar title={current.title} titleHidden />
    </>
  )
}
