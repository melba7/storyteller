// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import { useMemo, useState } from "react"
import {
  ActivityIndicator,
  Alert,
  FlatList,
  RefreshControl,
  View,
} from "react-native"

import { Text } from "@/components/ui/text"
import { followUpNew } from "@/modules/podcasts/automaticRun"
import { unsubscribe } from "@/modules/podcasts/db"
import { refreshShow } from "@/modules/podcasts/dbFeeds"
import {
  type EpisodeListItem,
  archivedCount,
  arrangeEpisodes,
  episodesInView,
} from "@/modules/podcasts/episodeList"
import { isLocalFeedUrl } from "@/modules/podcasts/localFiles"
import { readableError } from "@/modules/podcasts/nativeError"
import { settingsHref, tabBase } from "@/modules/podcasts/routes"
import { type EpisodeSort } from "@/modules/podcasts/showSettings"

import { EpisodeRow } from "./EpisodeRow"
import { BelowBar, ScreenBar } from "./ScreenBar"
import { SelectionBar } from "./SelectionBar"
import { showBarItems } from "./ShowBarButtons"
import { ShowHeader } from "./ShowHeader"
import { useEpisodes, useShow } from "./hooks"
import { useSelection } from "./useSelection"

const SORT_NAMES: Record<EpisodeSort, string> = {
  newest: "Newest first",
  oldest: "Oldest first",
  shortest: "Shortest first",
  longest: "Longest first",
}

/** How far the list scrolls before the header's title is under the bar (about 270 pt). */
const TITLE_UNDER_BAR = 270

export function PodcastShow({ id }: { id: string }) {
  const router = useRouter()
  const segments = useSegments()
  const show = useShow(id)
  const episodes = useEpisodes(id)
  const [refreshing, setRefreshing] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  const selection = useSelection()
  // The bar's title appears once the header's own title has scrolled under the bar.
  const [titleInBar, setTitleInBar] = useState(false)
  const items = useMemo(
    () =>
      show.data ? arrangeEpisodes(episodes.data ?? [], show.data.settings) : [],
    [episodes.data, show.data],
  )
  const shows = useMemo(
    () => new Map(show.data ? [[show.data.id, show.data]] : []),
    [show.data],
  )

  async function refresh() {
    setRefreshing(true)
    setProblem(null)
    try {
      await followUpNew(await refreshShow(id))
    } catch (cause) {
      setProblem(readableError(cause))
    } finally {
      setRefreshing(false)
    }
  }

  function confirmUnsubscribe(title: string) {
    const own = isLocalFeedUrl(show.data?.feedUrl ?? "")
    Alert.alert(
      own ? `Delete ${title}?` : `Unsubscribe from ${title}?`,
      own
        ? "Every file you added is deleted from this phone. The originals in the Files app stay."
        : "The show and its episodes are removed from your library.",
      [
        { text: "Cancel", style: "cancel" },
        {
          text: isLocalFeedUrl(show.data?.feedUrl ?? "")
            ? "Delete"
            : "Unsubscribe",
          style: "destructive",
          onPress: () => {
            unsubscribe(id).then(
              () => {
                // Back within this tab's stack, not into the other tab.
                if (router.canGoBack()) router.back()
                else router.navigate(tabBase(segments))
              },
              (cause: unknown) => setProblem(readableError(cause)),
            )
          },
        },
      ],
    )
  }

  const current = show.data
  return (
    <View className="bg-background flex-1">
      <ScreenBar
        title={current ? (titleInBar ? current.title : "") : "Podcast"}
        right={
          current
            ? showBarItems({
                show: current,
                archivedCount: archivedCount(episodes.data ?? []),
                onSelect: () => selection.begin(),
                onSettings: () =>
                  router.push(settingsHref(segments, current.id)),
                onUnfollow: () => confirmUnsubscribe(current.title),
              })
            : undefined
        }
      />
      {show.loading ? (
        <BelowBar>
          <ActivityIndicator className="mt-8" accessibilityLabel="Loading" />
        </BelowBar>
      ) : !current ? (
        <BelowBar>
          <Text className="text-muted-foreground px-8 py-12 text-center">
            {show.error ?? "This show isn't in your library."}
          </Text>
        </BelowBar>
      ) : (
        <>
          {selection.on ? (
            <SelectionBar
              selection={selection}
              episodes={episodesInView(items)}
              shows={shows}
            />
          ) : null}
          <FlatList<EpisodeListItem>
            data={items}
            keyExtractor={(item) => item.key}
            contentContainerClassName="px-safe-or-4"
            contentInsetAdjustmentBehavior="automatic"
            scrollEventThrottle={32}
            onScroll={(event) => {
              const { contentOffset, contentInset } = event.nativeEvent
              setTitleInBar(
                contentOffset.y + (contentInset?.top ?? 0) > TITLE_UNDER_BAR,
              )
            }}
            refreshControl={
              <RefreshControl refreshing={refreshing} onRefresh={refresh} />
            }
            ListHeaderComponent={
              <>
                <ShowHeader
                  show={current}
                  problem={problem}
                  onUnfollow={() => confirmUnsubscribe(current.title)}
                  episodeCount={episodes.data ? episodes.data.length : null}
                />
                <View className="flex-row items-baseline justify-between pt-2 pb-1">
                  <Text
                    className="text-xl font-bold"
                    accessibilityRole="header"
                  >
                    Episodes
                  </Text>
                  <Text className="text-muted-foreground text-sm">
                    {SORT_NAMES[current.settings.sort]}
                  </Text>
                </View>
              </>
            }
            ListEmptyComponent={
              episodes.loading ? undefined : (
                <Text className="text-muted-foreground py-6 text-center text-sm">
                  {episodes.error ?? "This feed has no episodes yet."}
                </Text>
              )
            }
            renderItem={({ item }) =>
              item.kind === "header" ? (
                <Text variant="h4" className="pt-4 pb-1">
                  {item.title}
                </Text>
              ) : (
                <EpisodeRow
                  episode={item.episode}
                  show={current}
                  selection={selection}
                />
              )
            }
            extraData={selection.selected}
          />
        </>
      )}
    </View>
  )
}
