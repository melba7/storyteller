// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Pause, Play } from "lucide-react-native"
import { ActivityIndicator, ScrollView, View } from "react-native"

import { Button } from "@/components/ui/button"
import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import {
  formatEpisodeDate,
  formatEpisodeLength,
} from "@/modules/podcasts/library"

import { AdsFound } from "./AdsFound"
import { Artwork } from "./Artwork"
import { DownloadButton } from "./DownloadButton"
import { LinkedNotes } from "./LinkedNotes"
import { pressEpisode, useEpisodeStatus } from "./PlayButton"
import { QueueButtons } from "./QueueButtons"
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
      <AdsFound episode={current} show={show.data ?? null} />
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
