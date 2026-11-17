// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import { Check, Circle, Star } from "lucide-react-native"
import { Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { ringFraction, rowState } from "@/modules/podcasts/episodeLook"
import {
  type Show,
  type StoredEpisode,
  formatEpisodeDate,
  formatEpisodeLength,
} from "@/modules/podcasts/library"
import { isPreviewId } from "@/modules/podcasts/preview"
import { episodeHref } from "@/modules/podcasts/routes"
import { queuedLabel } from "@/modules/podcasts/upNext"

import { DownloadButton } from "./DownloadButton"
import { EpisodeMenu } from "./EpisodeMenu"
import { PlayButton } from "./PlayButton"
import { type Selection } from "./useSelection"
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
  selection,
}: {
  episode: StoredEpisode
  show: Show
  /** False in a preview, where the episode has no card because it isn't in the library. */
  openable?: boolean
  /** The episode a search result pointed at. */
  highlighted?: boolean
  /** The list's multi-select. While it is on, a tap picks the row instead of opening it. */
  selection?: Selection
}) {
  const router = useRouter()
  const segments = useSegments()
  const state = rowState(episode)
  const date = formatEpisodeDate(episode.publishedAt)
  const length = formatEpisodeLength(episode)
  const queued = queuedLabel(useUpNext(), episode.id)
  const picking = selection?.on === true
  const picked = picking && selection.selected.includes(episode.id)
  return (
    <View
      className={`border-border flex-row items-center gap-3 border-b py-3 ${highlighted ? "bg-secondary rounded-md px-2" : ""}`}
      style={{ opacity: state === "played" ? 0.5 : 1 }}
    >
      {picking ? (
        <Icon
          as={picked ? Check : Circle}
          size={24}
          className={picked ? "text-primary" : "text-muted-foreground"}
        />
      ) : null}
      <Pressable
        className="active:bg-secondary flex-1 gap-1 rounded-md"
        accessibilityRole={picking ? "checkbox" : "button"}
        accessibilityState={picking ? { checked: picked } : {}}
        accessibilityLabel={[
          episode.title,
          date,
          length,
          queued,
          episode.starredAt === null ? "" : "Starred",
        ]
          .filter((part) => part !== "")
          .join(", ")}
        disabled={!openable && !picking}
        onPress={() =>
          picking
            ? selection.toggle(episode.id)
            : router.push(episodeHref(segments, episode.id))
        }
        onLongPress={
          selection && openable && !picking
            ? () => selection.begin(episode.id)
            : undefined
        }
      >
        {date || episode.starredAt !== null ? (
          <View className="flex-row items-center gap-1">
            {episode.starredAt === null ? null : (
              <Icon
                as={Star}
                size={12}
                className="text-primary"
                fill="currentColor"
              />
            )}
            <Text className="text-muted-foreground text-xs">{date}</Text>
          </View>
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
      {picking ? null : (
        <>
          <EpisodeMenu episode={episode} show={show} />
          {isPreviewId(episode.id) ? null : (
            <DownloadButton episode={episode} />
          )}
          <PlayButton
            episode={episode}
            show={show}
            ring={ringFraction(episode)}
          />
        </>
      )}
    </View>
  )
}
