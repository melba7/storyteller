// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import {
  ArrowDownToLine,
  Check,
  Circle,
  CircleAlert,
  CircleCheck,
  Star,
} from "lucide-react-native"
import { Pressable, View } from "react-native"
import { useCSSVariable } from "uniwind"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import {
  type RowMeta,
  ringFraction,
  rowMeta,
  rowState,
} from "@/modules/podcasts/episodeLook"
import {
  type Show,
  type StoredEpisode,
  formatEpisodeDate,
  formatEpisodeLength,
} from "@/modules/podcasts/library"
import { isLocalEpisodeId } from "@/modules/podcasts/localFiles"
import { isPreviewId } from "@/modules/podcasts/preview"
import { episodeHref } from "@/modules/podcasts/routes"
import { queuedLabel } from "@/modules/podcasts/upNext"

import { Artwork } from "./Artwork"
import { EpisodeMenu } from "./EpisodeMenu"
import { PlayButton, ProgressRing } from "./PlayButton"
import { useDownload } from "./useDownloads"
import { type Selection } from "./useSelection"
import { useUpNext } from "./useUpNext"

/** The small glyph at the start of the meta line: a download's state, or the played check. */
function MetaGlyph({ meta }: { meta: RowMeta }) {
  const primary = useCSSVariable("--color-primary") as string
  switch (meta.glyph) {
    case "none":
      return null
    case "played":
      return <Icon as={Check} size={14} className="text-muted-foreground" />
    case "downloaded":
      return (
        <Icon as={CircleCheck} size={14} className="text-muted-foreground" />
      )
    case "failed":
      return <Icon as={CircleAlert} size={14} className="text-destructive" />
    case "downloading":
      return meta.fraction === null ? (
        <Icon as={ArrowDownToLine} size={14} className="text-primary" />
      ) : (
        <View style={{ width: 14, height: 14 }}>
          <ProgressRing fraction={meta.fraction} size={14} color={primary} />
        </View>
      )
  }
}

/**
 * One episode on a list: date and star, title, a meta line (download glyph, length or time
 * left, "Up Next"), the "..." menu and a play button whose ring shows how much was heard. A
 * played episode is muted, has no ring and says "Played". The download button lives in the
 * menu.
 */
export function EpisodeRow({
  episode,
  show,
  openable = true,
  highlighted = false,
  selection,
  artwork = false,
}: {
  episode: StoredEpisode
  show: Show
  /** False in a preview, where the episode has no card because it isn't in the library. */
  openable?: boolean
  /** The episode a search result pointed at. */
  highlighted?: boolean
  /** The list's multi-select. While it is on, a tap picks the row instead of opening it. */
  selection?: Selection
  /** Shows the episode's picture (or its show's) at the start of the row. */
  artwork?: boolean
}) {
  const router = useRouter()
  const segments = useSegments()
  const state = rowState(episode)
  const date = formatEpisodeDate(episode.publishedAt)
  const length = formatEpisodeLength(episode)
  const queued = queuedLabel(useUpNext(), episode.id)
  // An added file's download is its only copy, and a preview episode has none.
  const downloadInfo = useDownload(episode.id)
  const download =
    isPreviewId(episode.id) || isLocalEpisodeId(episode.id)
      ? undefined
      : downloadInfo
  const meta = rowMeta({ state, length, queued, download })
  const played = state === "played"
  const picking = selection?.on === true
  const picked = picking && selection.selected.includes(episode.id)
  return (
    <View
      className={`border-foreground/10 flex-row items-center gap-3 border-b py-3 ${highlighted ? "bg-secondary rounded-md px-2" : ""}`}
    >
      {picking ? (
        <Icon
          as={picked ? Check : Circle}
          size={24}
          className={picked ? "text-primary" : "text-muted-foreground"}
        />
      ) : null}
      {artwork ? (
        <View style={{ opacity: played ? 0.6 : 1 }}>
          <Artwork
            uri={episode.imageUrl ?? show.imageUrl}
            size={56}
            className="rounded-lg"
          />
        </View>
      ) : null}
      <Pressable
        className="active:bg-secondary flex-1 gap-1 rounded-md"
        accessibilityRole={picking ? "checkbox" : "button"}
        accessibilityState={picking ? { checked: picked } : {}}
        accessibilityLabel={[
          episode.title,
          date,
          ...meta.spoken,
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
        <Text
          className={`font-semibold ${played ? "text-muted-foreground" : ""}`}
          numberOfLines={2}
        >
          {episode.title}
        </Text>
        {meta.glyph !== "none" || length || queued ? (
          <View className="flex-row items-center gap-1">
            <MetaGlyph meta={meta} />
            <Text className="text-muted-foreground flex-shrink text-sm">
              {length}
              {length && queued ? " · " : ""}
              {queued ? (
                <Text className="text-primary text-sm">Up Next</Text>
              ) : null}
            </Text>
          </View>
        ) : null}
      </Pressable>
      {picking ? null : (
        <>
          <EpisodeMenu episode={episode} show={show} />
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
