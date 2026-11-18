// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Stack, useRouter, useSegments } from "expo-router"
import { StatusBar } from "expo-status-bar"
import { Podcast } from "lucide-react-native"
import { useMemo } from "react"
import { RefreshControl, ScrollView, View } from "react-native"

import { Text } from "@/components/ui/text"
import { planChartLists } from "@/modules/podcasts/chartLists"
import { topShowCaption, updateCadence } from "@/modules/podcasts/homeLook"
import {
  NEW_HREF,
  SEARCH_HREF,
  showHref,
  showsHref,
  upNextHref,
} from "@/modules/podcasts/routes"

import { useOpenPreview } from "./ChartRow"
import { ChartShelves } from "./ChartShelves"
import { CategoryTiles } from "./DiscoverBrowse"
import { EmptyState } from "./EmptyState"
import { ScreenBar } from "./ScreenBar"
import { SectionHeader } from "./SectionHeader"
import { SectionMenuButton } from "./SectionMenu"
import { ShowShelf } from "./ShowShelf"
import { UpNextShelf } from "./UpNextShelf"
import { useShows } from "./hooks"
import { useChartLists } from "./useChartLists"
import {
  useShowDates,
  useTopShows,
  useUpNextShelf,
  useYouMightLike,
} from "./useHome"
import { useStatusBarStyle } from "./usePodcastsTheme"
import { useRefreshShows } from "./useRefreshShows"

/**
 * The Home tab: "Up Next >" (a shelf of cards: episodes in progress, then the newest unplayed
 * one of each show), "Your Top Shows >" and "You Might Like >", then Apple's charts (Top Shows and eight
 * categories) and the category tiles. Pull down to refresh the feeds and retry the charts.
 */
export function Home() {
  const statusBarStyle = useStatusBarStyle()
  const router = useRouter()
  const segments = useSegments()
  const openPreview = useOpenPreview()
  const refresh = useRefreshShows()
  const shows = useShows()
  const showById = new Map((shows.data ?? []).map((show) => [show.id, show]))
  const shelf = useUpNextShelf().data ?? []
  const top = useTopShows()
  const dates = useShowDates()
  const mightLike = useYouMightLike()
  // The charts wait for the followed shows, because those decide which categories come first.
  const lists = useMemo(
    () => planChartLists(shows.data ?? [], "home"),
    [shows.data],
  )
  const charts = useChartLists(
    lists.map((list) => list.id),
    !shows.loading,
  )
  const empty = !shows.loading && (shows.data ?? []).length === 0

  return (
    <>
      <ScrollView
        className="bg-background flex-1"
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={{ paddingBottom: 24 }}
        refreshControl={
          <RefreshControl
            refreshing={refresh.refreshing}
            onRefresh={() => {
              charts.retry()
              void refresh.refresh()
            }}
          />
        }
      >
        {refresh.problem ? (
          <View className="bg-destructive/10 mx-4 mt-2 rounded-xl p-3">
            <Text
              className="text-destructive text-sm"
              accessibilityRole="alert"
            >
              {refresh.problem}
            </Text>
          </View>
        ) : null}
        {empty && mightLike.length === 0 ? (
          <EmptyState
            icon={Podcast}
            title="No podcasts yet"
            body="Search for a show, or paste its RSS or Apple Podcasts link."
            action={{
              label: "Find a podcast",
              onPress: () => router.navigate(SEARCH_HREF),
            }}
          />
        ) : null}
        {shelf.length > 0 ? (
          <>
            <SectionHeader
              title="Up Next"
              onPress={() => router.push(upNextHref(segments))}
            />
            <UpNextShelf entries={shelf} showById={showById} />
          </>
        ) : null}
        {top.length > 0 ? (
          <>
            <SectionHeader
              title="Your Top Shows"
              onPress={() => router.push(showsHref(segments))}
            />
            <ShowShelf
              shows={top.map((show) => ({
                key: show.id,
                imageUrl: show.imageUrl,
                title: topShowCaption(show),
                caption: updateCadence(dates?.get(show.id) ?? [], Date.now()),
                href: showHref(segments, show.id),
              }))}
            />
          </>
        ) : null}
        {mightLike.length > 0 ? (
          <>
            <SectionHeader
              title="You Might Like"
              onPress={() => router.navigate(NEW_HREF)}
            />
            <ShowShelf
              shows={mightLike.map((show) => ({
                key: show.feedUrl,
                imageUrl: show.imageUrl,
                title: show.title,
                caption: show.author,
                onPress: () => openPreview(show.feedUrl),
              }))}
            />
          </>
        ) : null}
        <ChartShelves lists={lists} states={charts.states} />
        <SectionHeader title="Browse Categories" />
        <View className="px-4">
          <CategoryTiles />
        </View>
      </ScrollView>
      <StatusBar style={statusBarStyle} verticalBarBehaviorIOS="disabled" />
      <ScreenBar
        large
        account
        title="Home"
        left={
          <Stack.Toolbar.View>
            <SectionMenuButton current="podcasts" />
          </Stack.Toolbar.View>
        }
      />
    </>
  )
}
