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

import { PlayButton } from "./PlayButton"

/**
 * One episode on a show's page: date, title, length or time left, and a play button whose
 * ring shows how much was heard. A played episode is dimmed, has no ring and says "Played".
 */
export function EpisodeRow({
  episode,
  show,
  openable = true,
}: {
  episode: StoredEpisode
  show: Show
  /** False in a preview, where the episode has no card because it isn't in the library. */
  openable?: boolean
}) {
  const router = useRouter()
  const segments = useSegments()
  const state = rowState(episode)
  const date = formatEpisodeDate(episode.publishedAt)
  const length = formatEpisodeLength(episode)
  return (
    <View
      className="border-border flex-row items-center gap-3 border-b py-3"
      style={{ opacity: state === "played" ? 0.5 : 1 }}
    >
      <Pressable
        className="active:bg-secondary flex-1 gap-1 rounded-md"
        accessibilityRole="button"
        accessibilityLabel={[episode.title, date, length]
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
        {length ? (
          <Text className="text-muted-foreground text-sm">{length}</Text>
        ) : null}
      </Pressable>
      <PlayButton episode={episode} show={show} ring={ringFraction(episode)} />
    </View>
  )
}
