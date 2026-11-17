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
import { useMemo } from "react"
import { Pressable, View } from "react-native"
import { useCSSVariable } from "uniwind"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { type RowMeta, rowMeta, rowState } from "@/modules/podcasts/episodeLook"
import { dateLineParts, stripHtml } from "@/modules/podcasts/episodeRowLook"
import {
  type Show,
  type StoredEpisode,
  formatEpisodeLength,
} from "@/modules/podcasts/library"
import { isLocalEpisodeId } from "@/modules/podcasts/localFiles"
import { isPreviewId } from "@/modules/podcasts/preview"
import { episodeHref } from "@/modules/podcasts/routes"
import { queuedLabel } from "@/modules/podcasts/upNext"

import { Artwork } from "./Artwork"
import { EpisodeMenu } from "./EpisodeMenu"
import { PlayCapsule, ProgressRing } from "./PlayButton"
import { useDownload } from "./useDownloads"
import { type Selection } from "./useSelection"
import { useUpNext } from "./useUpNext"

/** The small glyph at the start of the meta line: a download's state, or the played check. */
function MetaGlyph({ meta }: { meta: RowMeta }) {
  const primary = useCSSVariable("--color-primary") as string
  switch (meta.glyph) {
    case "none":
      return null
    case "played": // The capsule says "Played".
      return null
    case "downloaded":
      return (
        <Icon as={CircleCheck} size={16} className="text-muted-foreground" />
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

const ARTWORK = 96

/**
 * One episode on a list, Apple's way: a grey date line (with the season and episode, "Played"
 * and "Up Next" when they apply), the title in bold, a grey description, the artwork at the
 * right, and a bottom row with the play capsule, a download symbol and the "..." menu. A
 * played episode's title is muted. Swipe actions come from the list; a long press starts
 * multi-select.
 */
export function EpisodeRow({
  episode,
  show,
  openable = true,
  highlighted = false,
  selection,
  artwork = true,
}: {
  episode: StoredEpisode
  show: Show
  /** False in a preview, where the episode has no card because it isn't in the library. */
  openable?: boolean
  /** The episode a search result pointed at. */
  highlighted?: boolean
  /** The list's multi-select. While it is on, a tap picks the row instead of opening it. */
  selection?: Selection
  /** Shows the episode's picture (or its show's) at the right; on by default. */
  artwork?: boolean
}) {
  const router = useRouter()
  const segments = useSegments()
  const state = rowState(episode)
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
  const dateParts = dateLineParts(episode, Date.now())
  const description = useMemo(() => stripHtml(episode.notes), [episode.notes])
  const spokenDate = dateParts.join(", ")
  return (
    <View
      className={`border-foreground/10 flex-row gap-3 border-b py-3 ${highlighted ? "bg-secondary rounded-md px-2" : ""}`}
    >
      {picking ? (
        <View className="pt-1">
          <Icon
            as={picked ? Check : Circle}
            size={24}
            className={picked ? "text-primary" : "text-muted-foreground"}
          />
        </View>
      ) : null}
      <View className="flex-1 gap-2">
        <Pressable
          className="active:bg-secondary flex-row gap-3 rounded-md"
          accessibilityRole={picking ? "checkbox" : "button"}
          accessibilityState={picking ? { checked: picked } : {}}
          accessibilityLabel={[
            episode.title,
            spokenDate,
            ...meta.spoken,
            episode.starredAt === null ? "" : "Saved",
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
          <View className="flex-1 gap-1">
            <View className="flex-row items-center gap-1">
              {episode.starredAt === null ? null : (
                <Icon
                  as={Star}
                  size={12}
                  className="text-primary"
                  fill="currentColor"
                />
              )}
              <Text
                className="text-muted-foreground flex-shrink text-[15px] font-semibold"
                numberOfLines={1}
              >
                {dateParts.join(" \u00b7 ")}
                {queued ? (
                  <Text className="text-primary text-[15px] font-semibold">
                    {dateParts.length > 0 ? " \u00b7 " : ""}Up Next
                  </Text>
                ) : null}
              </Text>
            </View>
            <Text
              className={`text-[17px] leading-[22px] font-bold ${played ? "text-muted-foreground" : ""}`}
              numberOfLines={4}
            >
              {episode.title}
            </Text>
            {description ? (
              <Text
                className="text-muted-foreground text-[15px] leading-5"
                numberOfLines={2}
              >
                {description}
              </Text>
            ) : null}
          </View>
          {artwork ? (
            <View style={{ opacity: played ? 0.6 : 1 }}>
              <Artwork
                uri={episode.imageUrl ?? show.imageUrl}
                size={ARTWORK}
                className="rounded-lg"
              />
            </View>
          ) : null}
        </Pressable>
        {picking ? null : (
          <View className="flex-row items-center gap-3">
            <PlayCapsule episode={episode} show={show} />
            <MetaGlyph meta={meta} />
            <View className="flex-1" />
            <EpisodeMenu episode={episode} show={show} />
          </View>
        )}
      </View>
    </View>
  )
}
