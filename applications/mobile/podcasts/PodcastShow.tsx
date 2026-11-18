// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import { useHeaderHeight } from "expo-router/react-navigation"
import { StatusBar } from "expo-status-bar"
import { useMemo, useRef, useState } from "react"
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
import {
  type EpisodeFilter,
  filterEpisodes,
} from "@/modules/podcasts/episodeRowLook"
import { isLocalFeedUrl } from "@/modules/podcasts/localFiles"
import { readableError } from "@/modules/podcasts/nativeError"
import { settingsHref, tabBase } from "@/modules/podcasts/routes"

import { EpisodeRow } from "./EpisodeRow"
import { BelowBar, ScreenBar } from "./ScreenBar"
import { SectionHeader } from "./SectionHeader"
import { SelectionBar } from "./SelectionBar"
import { showBarItems } from "./ShowBarButtons"
import { ShowHeader } from "./ShowHeader"
import { useEpisodes, useShow } from "./hooks"
import { useDownloadMap } from "./useDownloads"
import { useSelection } from "./useSelection"

export function PodcastShow({ id }: { id: string }) {
  const router = useRouter()
  const segments = useSegments()
  const show = useShow(id)
  const episodes = useEpisodes(id)
  const [refreshing, setRefreshing] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  const [filter, setFilter] = useState<EpisodeFilter>("all")
  const downloads = useDownloadMap()
  const selection = useSelection()
  // The bar's title appears once the header's own title has scrolled under the bar.
  const headerHeight = useHeaderHeight()
  const titleBottom = useRef<number | null>(null)
  const [titleInBar, setTitleInBar] = useState(false)
  const items = useMemo(() => {
    if (!show.data) return []
    const downloaded = new Set(
      Object.values(downloads)
        .filter((info) => info.state === "downloaded")
        .map((info) => info.episodeId),
    )
    // The Archived filter has to see the archived episodes the view hides.
    const view =
      filter === "archived"
        ? { ...show.data.settings, showArchived: true }
        : show.data.settings
    return arrangeEpisodes(
      filterEpisodes(episodes.data ?? [], filter, downloaded),
      view,
    )
  }, [episodes.data, show.data, filter, downloads])
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
    <>
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
        <FlatList<EpisodeListItem>
          className="bg-background flex-1"
          data={items}
          keyExtractor={(item) => item.key}
          contentInsetAdjustmentBehavior="automatic"
          scrollEventThrottle={32}
          onScroll={(event) => {
            // The list starts under the bar (its automatic inset is the header's height), so
            // the page's top edge below the bar is at the offset plus that height.
            if (titleBottom.current === null) return
            setTitleInBar(
              event.nativeEvent.contentOffset.y + headerHeight >=
                titleBottom.current,
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
                episodes={episodes.data}
                onTitleBottom={(bottom) => (titleBottom.current = bottom)}
              />
              <SectionHeader title="Episodes" />
            </>
          }
          ListEmptyComponent={
            episodes.loading ? (
              <ActivityIndicator
                className="mt-8"
                accessibilityLabel="Loading episodes"
              />
            ) : (
              <Text className="text-muted-foreground px-safe-or-4 py-6 text-center text-sm">
                {episodes.error ??
                  (filter === "all"
                    ? "This feed has no episodes yet."
                    : "No episodes match this filter.")}
              </Text>
            )
          }
          renderItem={({ item }) =>
            item.kind === "header" ? (
              <Text variant="h4" className="px-safe-or-4 pt-4 pb-1">
                {item.title}
              </Text>
            ) : (
              <View className="px-safe-or-4">
                <EpisodeRow
                  episode={item.episode}
                  show={current}
                  selection={selection}
                  here={{ show: true }}
                />
              </View>
            )
          }
          extraData={selection.selected}
        />
      )}
      {/* White clock and battery while the coloured header is under the bar. */}
      {current && !titleInBar ? (
        <StatusBar style="light" verticalBarBehaviorIOS="disabled" />
      ) : null}
      <ScreenBar
        title={current ? current.title : "Podcast"}
        titleHidden={Boolean(current) && !titleInBar}
        right={
          current
            ? showBarItems({
                show: current,
                archivedCount: archivedCount(episodes.data ?? []),
                filter,
                onFilter: setFilter,
                onSelect: () => selection.begin(),
                onSettings: () =>
                  router.push(settingsHref(segments, current.id)),
                onUnfollow: () => confirmUnsubscribe(current.title),
              })
            : undefined
        }
      />
      {selection.on ? (
        <SelectionBar
          selection={selection}
          episodes={episodesInView(items)}
          shows={shows}
        />
      ) : null}
    </>
  )
}
