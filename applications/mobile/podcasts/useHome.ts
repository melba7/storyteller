// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useMemo } from "react"

import { type ChartShow } from "@/modules/podcasts/charts"
import { listShowPlays, listUpNextShelf } from "@/modules/podcasts/dbHome"
import { type ShelfEntry, rankTopShows } from "@/modules/podcasts/home"
import { type Show } from "@/modules/podcasts/library"

import { useForYou } from "./discoverHooks"
import { type Query, useLibraryQuery, useShowActivity, useShows } from "./hooks"

/** Home's Up Next shelf: episodes in progress, then the newest unplayed one of each show. */
export function useUpNextShelf(): Query<ShelfEntry[]> {
  return useLibraryQuery(listUpNextShelf, "home-up-next")
}

/** "Your Top Shows": the followed shows ranked by recent listening (see `rankTopShows`). */
export function useTopShows(): Show[] {
  const shows = useShows().data
  const activity = useShowActivity().data
  const plays = useLibraryQuery(listShowPlays, "home-plays").data
  return useMemo(
    () =>
      rankTopShows(
        shows ?? [],
        plays ?? new Map(),
        new Map(
          Object.entries(activity ?? {}).map(([id, a]) => [id, a.newestAt]),
        ),
      ),
    [shows, activity, plays],
  )
}

/** "You Might Like": the shows of Discover's "For you", each once, not followed yet. */
export function useYouMightLike(limit = 12): ChartShow[] {
  const suggestions = useForYou()
  return useMemo(() => {
    const seen = new Set<string>()
    const picked: ChartShow[] = []
    for (const { shows } of suggestions) {
      for (const show of shows) {
        if (seen.has(show.feedUrl)) continue
        seen.add(show.feedUrl)
        picked.push(show)
      }
    }
    return picked.slice(0, limit)
  }, [suggestions, limit])
}
