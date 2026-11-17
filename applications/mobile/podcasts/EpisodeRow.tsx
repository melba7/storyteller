// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import { Pressable, View } from "react-native"

import { Text } from "@/components/ui/text"
import { ringFraction, rowState } from "@/modules/podcasts/episodeLook"
import {
  type Show,
  type StoredEpisode,
  formatEpisodeDate,
  formatEpisodeLength,
} from "@/modules/podcasts/library"
import { episodeHref } from "@/modules/podcasts/routes"
import { queuedLabel } from "@/modules/podcasts/upNext"

import { DownloadButton } from "./DownloadButton"
import { EpisodeMenu } from "./EpisodeMenu"
import { PlayButton } from "./PlayButton"
import { useUpNext } from "./useUpNext"

/**
 * One episode on a show's page: date, title, length or time left, and a download button and a play button whose
 * ring shows how much was heard. A played episode is dimmed, has no ring and says "Played".
 */
export function EpisodeRow({
  episode,
  show,
  openable = true,
  highlighted = false,
}: {
  episode: StoredEpisode
  show: Show
  /** False in a preview, where the episode has no card because it isn't in the library. */
  openable?: boolean
  /** The episode a search result pointed at. */
  highlighted?: boolean
}) {
  const router = useRouter()
  const segments = useSegments()
  const state = rowState(episode)
  const date = formatEpisodeDate(episode.publishedAt)
  const length = formatEpisodeLength(episode)
  const queued = queuedLabel(useUpNext(), episode.id)
  return (
    <View
      className={`border-border flex-row items-center gap-3 border-b py-3 ${highlighted ? "bg-secondary rounded-md px-2" : ""}`}
      style={{ opacity: state === "played" ? 0.5 : 1 }}
    >
      <Pressable
        className="active:bg-secondary flex-1 gap-1 rounded-md"
        accessibilityRole="button"
        accessibilityLabel={[episode.title, date, length, queued]
          .filter((part) => part !== "")
          .join(", ")}
        disabled={!openable}
        onPress={() => router.push(episodeHref(segments, episode.id))}
      >
        {date ? (
          <Text className="text-muted-foreground text-xs">{date}</Text>
        ) : null}
        <Text className="font-semibold" numberOfLines={2}>
          {episode.title}
        </Text>
        {length || queued ? (
          <Text className="text-muted-foreground text-sm">
            {length}
            {length && queued ? " · " : ""}
            {queued ? (
              <Text className="text-primary text-sm">Up Next</Text>
            ) : null}
          </Text>
        ) : null}
      </Pressable>
      <EpisodeMenu episode={episode} show={show} />
      <DownloadButton episode={episode} />
      <PlayButton episode={episode} show={show} ring={ringFraction(episode)} />
    </View>
  )
}
