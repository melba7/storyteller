// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack, useRouter, useSegments } from "expo-router"
import { useState } from "react"
import { ActivityIndicator, FlatList, Pressable, View } from "react-native"
import { useCSSVariable } from "uniwind"

import { Input } from "@/components/ui/input"
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
import { ScreenBar } from "./ScreenBar"
import { SpokenResults } from "./SpokenResults"
import { useDebouncedSearch } from "./useDebouncedSearch"

type Scope = "mine" | "all" | "spoken"

const SCOPES: { id: Scope; label: string }[] = [
  { id: "mine", label: "Your shows" },
  { id: "all", label: "All podcasts" },
  { id: "spoken", label: "Spoken" },
]

function Segments({
  scope,
  onChange,
}: {
  scope: Scope
  onChange: (scope: Scope) => void
}) {
  return (
    <View
      className="bg-secondary flex-row rounded-lg p-1"
      accessibilityRole="tablist"
    >
      {SCOPES.map(({ id, label }) => (
        <Pressable
          key={id}
          className={`flex-1 items-center rounded-md py-2 ${scope === id ? "bg-background" : ""}`}
          accessibilityRole="tab"
          accessibilityState={{ selected: scope === id }}
          onPress={() => onChange(id)}
        >
          <Text
            className={scope === id ? "font-semibold" : "text-muted-foreground"}
          >
            {label}
          </Text>
        </Pressable>
      ))}
    </View>
  )
}

function ResultRow({
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

/** Search for episodes: in the followed shows (on the phone) or in all of Apple's podcasts. */
export function SearchEpisodes() {
  const background = useCSSVariable("--color-background") as string
  const router = useRouter()
  const segments = useSegments()
  const [scope, setScope] = useState<Scope>("mine")
  const [term, setTerm] = useState("")
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
  const state = scope === "mine" ? mine : scope === "all" ? all : spoken
  const typed = term.trim() !== ""

  const rows =
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
      : all.results.map((found) => ({
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

  return (
    <View className="bg-background flex-1">
      <ScreenBar title="Search" />
      {/* The search box sits above the results, not in a scroll view, so the header is solid. */}
      <Stack.Screen
        options={{
          headerTransparent: false,
          headerStyle: { backgroundColor: background },
        }}
      />
      <View className="px-safe-or-4 gap-3 pb-2">
        <Input
          accessibilityLabel="Search episodes"
          placeholder="Search for an episode"
          value={term}
          onChangeText={setTerm}
          autoFocus
          autoCapitalize="none"
          autoCorrect={false}
          returnKeyType="search"
          clearButtonMode="while-editing"
        />
        <Segments scope={scope} onChange={setScope} />
      </View>
      {state.searching ? (
        <ActivityIndicator className="mt-4" accessibilityLabel="Searching" />
      ) : state.error ? (
        <Text className="text-destructive px-8 py-6 text-center text-sm">
          {state.error}
        </Text>
      ) : scope !== "spoken" && typed && rows.length === 0 ? (
        <Text className="text-muted-foreground px-8 py-6 text-center text-sm">
          No episodes found.
        </Text>
      ) : null}
      {scope === "spoken" ? (
        <SpokenResults
          results={spoken.results}
          typed={typed}
          waiting={spoken.searching || spoken.error !== null}
        />
      ) : (
        <FlatList
          data={rows}
          keyExtractor={(row) => row.key}
          contentContainerClassName="px-safe-or-4 gap-3 pb-6"
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="on-drag"
          renderItem={({ item }) => (
            <ResultRow
              title={item.title}
              line={item.line}
              imageUrl={item.imageUrl}
              onPress={item.open}
            />
          )}
        />
      )}
    </View>
  )
}
