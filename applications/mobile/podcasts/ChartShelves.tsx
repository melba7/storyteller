// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useRouter, useSegments } from "expo-router"
import { View } from "react-native"

import { Text } from "@/components/ui/text"
import { type ChartListPlan } from "@/modules/podcasts/chartLists"
import { categoryHref } from "@/modules/podcasts/routes"

import { useOpenPreview } from "./ChartRow"
import { EpisodeChartShelf, EpisodeShelfSkeleton } from "./EpisodeChartShelf"
import { SectionHeader } from "./SectionHeader"
import { ShelfSkeleton } from "./ShelfSkeleton"
import { ShowShelf } from "./ShowShelf"
import { type ChartListStates } from "./useChartLists"

/**
 * The chart lists of a page, one after the other: its heading (the chevron opens the ranked
 * page), then a skeleton of the shelf's exact height while it loads, or the ranked first
 * shows. "Top Episodes" has its own compact shelf and no chevron, as it has no ranked page.
 * A missing list draws nothing, heading included. When every list is missing the page
 * shows one quiet line.
 */
export function ChartShelves({
  lists,
  states,
}: {
  lists: ChartListPlan[]
  states: ChartListStates
}) {
  const router = useRouter()
  const segments = useSegments()
  const open = useOpenPreview()
  const stateOf = (id: string) => states[id]?.status ?? "loading"

  if (
    lists.length > 0 &&
    lists.every((list) => stateOf(list.id) === "missing")
  ) {
    return (
      <Text className="text-muted-foreground px-4 pt-7 text-base">
        Couldn&apos;t load the charts. Pull down to try again.
      </Text>
    )
  }
  return (
    <>
      {lists.map((list) => {
        const state = states[list.id]
        if (state?.status === "missing") return null
        if (list.kind === "episodes") {
          return (
            <View key={list.id}>
              <SectionHeader title={list.title} />
              {state?.status === "ready" && "episodes" in state ? (
                <EpisodeChartShelf
                  episodes={state.episodes.slice(0, list.shelf)}
                />
              ) : (
                <EpisodeShelfSkeleton />
              )}
            </View>
          )
        }
        return (
          <View key={list.id}>
            <SectionHeader
              title={list.title}
              onPress={() => router.push(categoryHref(list.id, segments))}
            />
            {state?.status === "ready" && "shows" in state ? (
              <ShowShelf
                shows={state.shows.slice(0, list.shelf).map((show, index) => ({
                  key: show.appleId,
                  imageUrl: show.imageUrl,
                  title: show.title,
                  caption: show.author,
                  rank: index + 1,
                  onPress: () => open(show.feedUrl),
                }))}
              />
            ) : (
              <ShelfSkeleton ranked />
            )}
          </View>
        )
      })}
    </>
  )
}
