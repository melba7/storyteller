// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useEffect, useMemo, useState } from "react"

import {
  type ForYouSuggestion,
  buildForYou,
  pickForYou,
} from "@/modules/podcasts/categories"
import { type ChartShow, loadChart } from "@/modules/podcasts/charts"
import { cacheGet, cachePut } from "@/modules/podcasts/db"
import { readableError } from "@/modules/podcasts/nativeError"

import { type Query, useShows } from "./hooks"

const store = { cacheGet, cachePut }

/** One chart (`TOP_CHART` or a genre id), read when the screen opens and kept for a day. */
export function useChart(chart: string): Query<ChartShow[]> {
  const [state, setState] = useState<Query<ChartShow[]>>({
    data: undefined,
    loading: true,
    error: null,
  })
  useEffect(() => {
    let current = true
    setState({ data: undefined, loading: true, error: null })
    loadChart(chart, store).then(
      (data) => {
        if (current) setState({ data, loading: false, error: null })
      },
      (cause: unknown) => {
        if (current) {
          setState({
            data: undefined,
            loading: false,
            error: readableError(cause),
          })
        }
      },
    )
    return () => {
      current = false
    }
  }, [chart])
  return state
}

/**
 * "For you": suggestions from the categories of the followed shows. Empty while loading, and
 * when nothing is followed or no chart could be read (Discover then shows only the charts).
 */
export function useForYou(): ForYouSuggestion[] {
  const shows = useShows().data
  const picks = useMemo(() => pickForYou(shows ?? []), [shows])
  const [suggestions, setSuggestions] = useState<ForYouSuggestion[]>([])

  useEffect(() => {
    let current = true
    if (!shows || picks.length === 0) {
      setSuggestions([])
      return
    }
    Promise.allSettled(picks.map((p) => loadChart(p.category.id, store))).then(
      (settled) => {
        if (!current) return
        const charts = new Map<string, ChartShow[]>()
        settled.forEach((result, index) => {
          const pick = picks[index]
          if (pick && result.status === "fulfilled") {
            charts.set(pick.category.id, result.value)
          }
        })
        setSuggestions(buildForYou(picks, charts, shows))
      },
    )
    return () => {
      current = false
    }
  }, [shows, picks])

  return suggestions
}
