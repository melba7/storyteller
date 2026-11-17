// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Pause, Play, Star } from "lucide-react-native"
import { ActivityIndicator, ScrollView, View } from "react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { setPlayed, setStarred } from "@/modules/podcasts/dbEpisodes"
import {
  archiveEpisodes,
  unarchiveEpisodes,
} from "@/modules/podcasts/dbSettings"
import {
  formatEpisodeDate,
  formatEpisodeLength,
} from "@/modules/podcasts/library"
import { episodeShare } from "@/modules/podcasts/share"

import { AdsFound } from "./AdsFound"
import { Artwork } from "./Artwork"
import { DownloadButton } from "./DownloadButton"
import { EpisodeBookmarks } from "./EpisodeBookmarks"
import { LinkedNotes } from "./LinkedNotes"
import { pressEpisode, useEpisodeStatus } from "./PlayButton"
import { QueueButtons } from "./QueueButtons"
import { ShareButton } from "./ShareButton"
import { chooseAndAddToPlaylist } from "./addToPlaylist"
import { useEpisode, useShow } from "./hooks"

/** The episode card, shown as a sheet: artwork, details, a big play button and the notes. */
export function PodcastEpisode({ id }: { id: string }) {
  const episode = useEpisode(id)
  const show = useShow(episode.data?.showId ?? "")
  const current = episode.data
  const status = useEpisodeStatus(id)

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
  const label = playing
    ? "Pause"
    : current.positionSeconds > 0 && !current.played
      ? "Resume"
      : "Play"

  return (
    <ScrollView
      className="bg-background flex-1"
      contentContainerClassName="px-safe-or-4 items-center gap-3 pt-8 pb-8"
      contentInsetAdjustmentBehavior="automatic"
    >
      <Artwork
        uri={current.imageUrl ?? show.data?.imageUrl ?? null}
        size={160}
        className="rounded-xl"
      />
      <View className="items-center gap-1">
        <Text variant="h4" className="text-center">
          {current.title}
        </Text>
        {show.data ? (
          <Text className="text-muted-foreground text-center">
            {show.data.title}
          </Text>
        ) : null}
        {details ? (
          <Text className="text-muted-foreground text-sm">{details}</Text>
        ) : null}
      </View>
      <Button
        size="lg"
        className="w-full max-w-xs rounded-full"
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
          />
        )}
        <Text>{label}</Text>
      </Button>
      <QueueButtons episode={current} show={show.data ?? null} />
      <DownloadButton episode={current} size={44} showStatus />
      <View className="flex-row flex-wrap items-center justify-center gap-2">
        <Button
          variant="ghost"
          accessibilityLabel={`${current.starredAt === null ? "Star" : "Unstar"} ${current.title}`}
          onPress={() => {
            setStarred([current.id], current.starredAt === null).catch(
              (cause: unknown) =>
                console.warn("Couldn't change the episode's star", cause),
            )
          }}
        >
          <Icon
            as={Star}
            size={18}
            className="text-primary"
            fill={current.starredAt === null ? "none" : "currentColor"}
          />
          <Text>{current.starredAt === null ? "Star" : "Starred"}</Text>
        </Button>
        <Button
          variant="ghost"
          accessibilityLabel={`Add ${current.title} to a playlist`}
          onPress={() =>
            void chooseAndAddToPlaylist(current, show.data ?? null)
          }
        >
          <Text>Add to playlist</Text>
        </Button>
        <Button
          variant="ghost"
          accessibilityLabel={`${current.played ? "Mark unplayed" : "Mark played"} ${current.title}`}
          onPress={() => {
            setPlayed([current.id], !current.played).catch((cause: unknown) =>
              console.warn("Couldn't change the episode's played mark", cause),
            )
          }}
        >
          <Text>{current.played ? "Mark unplayed" : "Mark played"}</Text>
        </Button>
      </View>
      <Button
        variant="ghost"
        accessibilityLabel={`${current.archived ? "Unarchive" : "Archive"} ${current.title}`}
        onPress={() => {
          const done = current.archived
            ? unarchiveEpisodes([current.id])
            : archiveEpisodes([current.id])
          done.catch((cause: unknown) =>
            console.warn("Couldn't change the episode's archive", cause),
          )
        }}
      >
        <Text>{current.archived ? "Unarchive" : "Archive"}</Text>
      </Button>
      <ShareButton
        label={`Share ${current.title}`}
        build={() => episodeShare(current, show.data ?? null)}
      />
      <AdsFound episode={current} show={show.data ?? null} />
      <EpisodeBookmarks episode={current} show={show.data ?? null} />
      <View className="w-full pt-2">
        {current.notes === "" ? (
          <Text className="text-muted-foreground">
            No notes for this episode.
          </Text>
        ) : (
          <LinkedNotes notes={current.notes} />
        )}
      </View>
    </ScrollView>
  )
}
