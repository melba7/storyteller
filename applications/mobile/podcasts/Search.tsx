// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack } from "expo-router"
import { StatusBar } from "expo-status-bar"
import { useState } from "react"
import { ActivityIndicator, FlatList, View } from "react-native"

import { Text } from "@/components/ui/text"
import { type DirectoryShow } from "@/modules/podcasts/directory"
import { isFollowLink } from "@/modules/podcasts/followLinkText"
import { type SpokenResult } from "@/modules/podcasts/spokenSearch"

import { CategoryTiles } from "./DiscoverBrowse"
import { ScreenBar } from "./ScreenBar"
import {
  type EpisodeRowData,
  ResultRow,
  type Scope,
  ScopeControl,
  useEpisodeSearch,
} from "./SearchEpisodes"
import { FollowLinkRow, ShowResult, useShowSearch } from "./SearchShows"
import { SectionMenuButton } from "./SectionMenu"
import { SpokenGroup, SpokenNotes } from "./SpokenResults"
import { useStatusBarStyle } from "./usePodcastsTheme"

type Item =
  | { kind: "show"; key: string; show: DirectoryShow }
  | { kind: "episode"; key: string; row: EpisodeRowData }
  | { kind: "spoken"; key: string; group: SpokenResult }

/**
 * The Search tab (the system search tab, with the native search bar): the categories while
 * nothing is typed, then, under a scope control, shows and episodes from Apple's directory
 * ("All podcasts"), episodes of the shows you follow ("Your shows") or the words said in
 * downloaded episodes ("Spoken"). A pasted feed or Apple Podcasts link is followed.
 */
export function Search() {
  const statusBarStyle = useStatusBarStyle()
  const [scope, setScope] = useState<Scope>("all")
  const [term, setTerm] = useState("")
  const link = isFollowLink(term)
  const typed = term.trim() !== ""
  // A link is followed, not searched for.
  const searched = link ? "" : term
  const shows = useShowSearch(searched, scope === "all")
  const episodes = useEpisodeSearch(scope, searched)
  const state = episodes.state

  const items: Item[] = [
    ...(scope === "all"
      ? shows.results.map((show) => ({
          kind: "show" as const,
          key: `show:${show.id}`,
          show,
        }))
      : []),
    ...episodes.rows.map((row) => ({
      kind: "episode" as const,
      key: `episode:${row.key}`,
      row,
    })),
    ...(scope === "spoken"
      ? episodes.spoken.map((group) => ({
          kind: "spoken" as const,
          key: `spoken:${group.episode.id}`,
          group,
        }))
      : []),
  ]
  const searching = state.searching || (scope === "all" && shows.searching)
  const failed = scope === "all" ? (shows.error ?? state.error) : state.error

  return (
    <>
      <FlatList<Item>
        className="bg-background flex-1"
        data={typed ? items : []}
        keyExtractor={(item) => item.key}
        contentInsetAdjustmentBehavior="automatic"
        contentContainerClassName="px-safe-or-4 gap-3 pb-6"
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="on-drag"
        ListHeaderComponent={
          typed ? (
            <View className="gap-3 pt-2">
              <ScopeControl scope={scope} onChange={setScope} />
              {link ? <FollowLinkRow term={term} /> : null}
              {searching ? (
                <ActivityIndicator accessibilityLabel="Searching" />
              ) : failed ? (
                <Text className="text-destructive text-sm">{failed}</Text>
              ) : null}
              {scope === "spoken" ? (
                <SpokenNotes
                  results={episodes.spoken}
                  typed={typed}
                  waiting={state.searching || state.error !== null}
                />
              ) : null}
            </View>
          ) : (
            <View className="pt-4">
              <CategoryTiles />
            </View>
          )
        }
        ListEmptyComponent={
          typed && !link && !searching && !failed && scope !== "spoken" ? (
            <Text className="text-muted-foreground px-8 py-6 text-center text-sm">
              {scope === "all" ? "No podcasts found." : "No episodes found."}
            </Text>
          ) : undefined
        }
        renderItem={({ item }) =>
          item.kind === "show" ? (
            <ShowResult show={item.show} />
          ) : item.kind === "episode" ? (
            <ResultRow
              title={item.row.title}
              line={item.row.line}
              imageUrl={item.row.imageUrl}
              onPress={item.row.open}
            />
          ) : (
            <SpokenGroup item={item.group} />
          )
        }
      />
      <StatusBar style={statusBarStyle} verticalBarBehaviorIOS="disabled" />
      <ScreenBar
        large
        account
        title="Search"
        left={
          <Stack.Toolbar.View>
            <SectionMenuButton current="podcasts" />
          </Stack.Toolbar.View>
        }
      />
      <Stack.SearchBar
        placeholder="Shows, episodes and words said"
        autoCapitalize="none"
        hideWhenScrolling={false}
        onChangeText={(event) => setTerm(event.nativeEvent.text)}
        onCancelButtonPress={() => setTerm("")}
      />
    </>
  )
}
