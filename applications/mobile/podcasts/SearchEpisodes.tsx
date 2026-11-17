// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import { Pressable, View } from "react-native"

import { Text } from "@/components/ui/text"
import { searchEpisodes } from "@/modules/podcasts/db"
import {
  type DirectoryEpisode,
  searchDirectoryEpisodes,
} from "@/modules/podcasts/directory"
import {
  formatDuration,
  formatEpisodeDate,
  formatEpisodeLength,
} from "@/modules/podcasts/library"
import { episodeHref, previewHref } from "@/modules/podcasts/routes"
import { type EpisodeHit } from "@/modules/podcasts/search"
import { searchSpoken } from "@/modules/podcasts/spokenSearch"

import { Artwork } from "./Artwork"
import { useDebouncedSearch } from "./useDebouncedSearch"

export type Scope = "mine" | "all" | "spoken"

const SCOPES: { id: Scope; label: string }[] = [
  { id: "mine", label: "Your shows" },
  { id: "all", label: "All podcasts" },
  { id: "spoken", label: "Spoken" },
]

/** The scope control under the search bar: Your shows, All podcasts, Spoken. */
export function ScopeControl({
  scope,
  onChange,
}: {
  scope: Scope
  onChange: (scope: Scope) => void
}) {
  return (
    <View
      className="bg-secondary flex-row rounded-full p-1"
      accessibilityRole="tablist"
    >
      {SCOPES.map(({ id, label }) => (
        <Pressable
          key={id}
          className={`min-h-10 flex-1 items-center justify-center rounded-full px-2 ${scope === id ? "bg-background" : ""}`}
          accessibilityRole="tab"
          accessibilityState={{ selected: scope === id }}
          onPress={() => onChange(id)}
        >
          <Text
            className={scope === id ? "font-semibold" : "text-muted-foreground"}
            numberOfLines={1}
          >
            {label}
          </Text>
        </Pressable>
      ))}
    </View>
  )
}

/** One episode result: its picture, title and a grey line. */
export function ResultRow({
  title,
  line,
  imageUrl,
  onPress,
}: {
  title: string
  line: string
  imageUrl: string | null
  onPress: () => void
}) {
  return (
    <Pressable
      className="active:bg-secondary flex-row items-center gap-3 rounded-md py-1"
      accessibilityRole="button"
      accessibilityLabel={`${title}, ${line}`}
      onPress={onPress}
    >
      <Artwork uri={imageUrl} size={56} />
      <View className="flex-1">
        <Text className="font-semibold" numberOfLines={2}>
          {title}
        </Text>
        <Text className="text-muted-foreground text-sm" numberOfLines={2}>
          {line}
        </Text>
      </View>
    </Pressable>
  )
}

const join = (parts: string[]) =>
  parts.filter((part) => part !== "").join(" · ")

export type EpisodeRowData = {
  key: string
  title: string
  line: string
  imageUrl: string | null
  open: () => void
}

/**
 * Episode search for the words typed: in the followed shows (on the phone), in all of Apple's
 * podcasts, or in the words spoken inside downloaded episodes. Only the chosen scope searches.
 */
export function useEpisodeSearch(scope: Scope, term: string) {
  const router = useRouter()
  const segments = useSegments()
  const mine = useDebouncedSearch<EpisodeHit>(
    scope === "mine" ? term : "",
    searchEpisodes,
    250,
  )
  const all = useDebouncedSearch<DirectoryEpisode>(
    scope === "all" ? term : "",
    searchDirectoryEpisodes,
    500,
  )
  const spoken = useDebouncedSearch(
    scope === "spoken" ? term : "",
    searchSpoken,
    400,
  )
  const rows: EpisodeRowData[] =
    scope === "mine"
      ? mine.results.map(({ episode, showTitle, showImageUrl }) => ({
          key: episode.id,
          title: episode.title,
          line: join([
            showTitle,
            formatEpisodeDate(episode.publishedAt),
            formatEpisodeLength(episode),
          ]),
          imageUrl: episode.imageUrl ?? showImageUrl,
          open: () => router.push(episodeHref(segments, episode.id)),
        }))
      : scope === "all"
        ? all.results.map((found) => ({
            key: found.id,
            title: found.title,
            line: join([
              found.showTitle,
              formatEpisodeDate(found.publishedAt),
              formatDuration(found.durationSeconds),
            ]),
            imageUrl: found.imageUrl,
            open: () =>
              router.push(
                previewHref(segments, found.feedUrl, {
                  guid: found.guid,
                  audioUrl: found.audioUrl,
                }),
              ),
          }))
        : []
  const state = scope === "mine" ? mine : scope === "all" ? all : spoken
  return { rows, spoken: spoken.results, state }
}
