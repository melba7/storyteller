// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import { useMemo } from "react"
import {
  ActivityIndicator,
  RefreshControl,
  ScrollView,
  View,
} from "react-native"

import { Text } from "@/components/ui/text"
import { forYouOmit } from "@/modules/podcasts/categories"
import { planChartLists } from "@/modules/podcasts/chartLists"
import { TOP_CHART } from "@/modules/podcasts/charts"
import { featuredCards } from "@/modules/podcasts/featured"
import { categoryHref } from "@/modules/podcasts/routes"

import { CategoryTiles } from "./CategoryTiles"
import { useOpenPreview } from "./ChartRow"
import { ChartShelves } from "./ChartShelves"
import { FeaturedCards } from "./FeaturedCards"
import { SectionHeader } from "./SectionHeader"
import { ShowShelf } from "./ShowShelf"
import { useChart, useForYouState } from "./discoverHooks"
import { useShows } from "./hooks"
import { useChartLists } from "./useChartLists"

/** How many of the top chart the "Top Shows" shelf holds; the chart page has all of it. */
const TOP_SHELF = 25

/**
 * What New shows, Apple's way: the featured cards, "Top Shows >" with ranks, "For You >"
 * (one shelf per category you follow), a chart for every other category and the tiles. It is
 * the New tab's scroll view: pulling down retries the chart lists that failed or are old.
 */
export function DiscoverBrowse() {
  const router = useRouter()
  const segments = useSegments()
  const open = useOpenPreview()
  const { suggestions: forYou, picks, loaded: forYouLoaded } = useForYouState()
  const top = useChart(TOP_CHART)
  const topShows = top.data ?? []
  const cards = featuredCards(topShows, forYou)
  // The lists under "For You": New has its own "Top Shows" and shows the "For You" categories
  // above, so neither comes twice. They load in groups after the followed shows are known,
  // so the cards and "Top Shows" above never wait for them.
  const shows = useShows()
  const lists = useMemo(() => {
    const followed = shows.data ?? []
    // While For You loads every pick is left out, so the planned lists hold still. Once it
    // has loaded only the categories it drew are, so a pick whose chart failed still gets
    // its "Top in ..." list.
    const omit = [TOP_CHART, ...forYouOmit(picks, forYou, forYouLoaded)]
    return planChartLists(followed, "new", omit)
  }, [shows.data, picks, forYou, forYouLoaded])
  const charts = useChartLists(
    lists.map((list) => list.id),
    !shows.loading,
  )
  return (
    <ScrollView
      className="bg-background flex-1"
      contentContainerStyle={{ paddingBottom: 24 }}
      contentInsetAdjustmentBehavior="automatic"
      refreshControl={
        <RefreshControl refreshing={false} onRefresh={charts.retry} />
      }
    >
      <View className="pt-2">
        {top.loading ? (
          <ActivityIndicator
            className="mt-8"
            accessibilityLabel="Loading the top chart"
          />
        ) : top.error ? (
          <Text className="text-destructive px-4 pt-4 text-sm">
            {top.error}
          </Text>
        ) : null}

        {cards.length > 0 ? <FeaturedCards cards={cards} /> : null}

        {topShows.length > 0 ? (
          <>
            <SectionHeader
              title="Top Shows"
              onPress={() => router.push(categoryHref(TOP_CHART, segments))}
            />
            <ShowShelf
              shows={topShows.slice(0, TOP_SHELF).map((show, index) => ({
                key: show.appleId,
                imageUrl: show.imageUrl,
                title: show.title,
                caption: show.author,
                rank: index + 1,
                onPress: () => open(show.feedUrl),
              }))}
            />
          </>
        ) : null}

        {forYou.map((suggestion, index) => (
          <View key={suggestion.category.id}>
            <SectionHeader
              title={index === 0 ? "For You" : suggestion.category.name}
              onPress={() =>
                router.push(categoryHref(suggestion.category.id, segments))
              }
            />
            <Text className="text-muted-foreground -mt-2 mb-3 px-4 text-base">
              {index === 0 ? `${suggestion.category.name}. ` : ""}Because you
              follow {suggestion.because}
            </Text>
            <ShowShelf
              shows={suggestion.shows.map((show) => ({
                key: show.appleId,
                imageUrl: show.imageUrl,
                title: show.title,
                caption: show.author,
                onPress: () => open(show.feedUrl),
              }))}
            />
          </View>
        ))}

        <ChartShelves lists={lists} states={charts.states} />

        <SectionHeader title="Categories" />
        <View className="px-4">
          <CategoryTiles />
        </View>
      </View>
    </ScrollView>
  )
}
