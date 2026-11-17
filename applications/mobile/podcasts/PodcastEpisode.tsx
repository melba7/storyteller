// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Pause, Play } from "lucide-react-native"
import { ActivityIndicator, Pressable, ScrollView, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { playLabel } from "@/modules/podcasts/episodeLook"
import {
  formatEpisodeDate,
  formatEpisodeLength,
} from "@/modules/podcasts/library"
import { peopleForEpisode } from "@/modules/podcasts/people"

import { AdsFound } from "./AdsFound"
import { Artwork } from "./Artwork"
import { DownloadStatusLine } from "./DownloadButton"
import { EpisodeActions } from "./EpisodeActions"
import { EpisodeBookmarks } from "./EpisodeBookmarks"
import { EpisodePeople } from "./EpisodePeople"
import { LinkedNotes } from "./LinkedNotes"
import { pressEpisode, useEpisodeStatus } from "./PlayButton"
import { useEpisode, useShow } from "./hooks"
import { useArtworkColor, useWashStyle } from "./useWash"

/** Room above the card that the wash also covers, so it reaches the top of the sheet. */
const WASH_ABOVE = 300
const WASH_HEIGHT = 340

/**
 * The episode card, shown as a sheet: a wash from the show's colour, artwork and details on
 * the left, the title, one main button, a strip of five actions and the notes.
 */
export function PodcastEpisode({ id }: { id: string }) {
  const episode = useEpisode(id)
  const show = useShow(episode.data?.showId ?? "")
  const current = episode.data
  const status = useEpisodeStatus(id)
  const wash = useWashStyle(useArtworkColor(show.data ?? null))

  if (episode.loading) {
    return (
      <View className="bg-background flex-1 pt-8">
        <ActivityIndicator accessibilityLabel="Loading" />
      </View>
    )
  }
  if (!current) {
    return (
      <View className="bg-background flex-1">
        <Text className="text-muted-foreground px-8 py-12 text-center">
          {episode.error ?? "This episode isn't in your library."}
        </Text>
      </View>
    )
  }

  const details = [
    formatEpisodeDate(current.publishedAt),
    formatEpisodeLength(current),
  ]
    .filter((part) => part !== "")
    .join(" · ")
  const playing = status === "playing"
  const label = playLabel(current, playing)

  return (
    <ScrollView
      className="bg-background flex-1"
      contentContainerClassName="px-safe-or-4 gap-4 pt-6 pb-8"
      contentInsetAdjustmentBehavior="automatic"
    >
      {wash ? (
        <View
          pointerEvents="none"
          style={[
            {
              position: "absolute",
              top: -WASH_ABOVE,
              left: -64,
              right: -64,
              height: WASH_ABOVE + WASH_HEIGHT,
            },
            wash,
          ]}
        />
      ) : null}
      <View className="flex-row items-center gap-3">
        <Artwork
          uri={current.imageUrl ?? show.data?.imageUrl ?? null}
          size={72}
          className="rounded-xl"
        />
        <View className="flex-1 gap-1">
          {show.data ? (
            <Text
              className="text-primary text-sm font-semibold"
              numberOfLines={2}
            >
              {show.data.title}
            </Text>
          ) : null}
          {details ? (
            <Text className="text-muted-foreground text-sm">{details}</Text>
          ) : null}
        </View>
      </View>
      <Text className="text-2xl font-bold" accessibilityRole="header">
        {current.title}
      </Text>
      <Pressable
        className="bg-primary min-h-12 w-full flex-row items-center justify-center gap-2 rounded-full px-6 py-2 active:opacity-80"
        accessibilityRole="button"
        accessibilityLabel={label}
        onPress={() => pressEpisode(current, show.data ?? null, status)}
      >
        {status === "buffering" ? (
          <ActivityIndicator accessibilityLabel="Buffering" />
        ) : (
          <Icon
            as={playing ? Pause : Play}
            size={20}
            className="text-primary-foreground"
            fill="currentColor"
          />
        )}
        <Text className="text-primary-foreground text-base font-semibold">
          {label}
        </Text>
      </Pressable>
      <EpisodeActions episode={current} show={show.data ?? null} />
      <DownloadStatusLine episode={current} />
      <AdsFound episode={current} show={show.data ?? null} />
      <EpisodeBookmarks episode={current} show={show.data ?? null} />
      <View className="w-full gap-2">
        <Text className="text-lg font-bold" accessibilityRole="header">
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
      <EpisodePeople
        people={peopleForEpisode(current, show.data)}
        funding={show.data?.funding ?? []}
      />
    </ScrollView>
  )
}
