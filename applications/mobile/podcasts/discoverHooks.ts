// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useFocusEffect } from "expo-router"
import { useCallback, useEffect, useMemo, useRef, useState } from "react"

import {
  type ForYouPick,
  type ForYouSuggestion,
  buildForYou,
  forYouKey,
  pickForYou,
} from "@/modules/podcasts/categories"
import { keptChart, startChartLoad } from "@/modules/podcasts/chartBatch"
import { type ChartShow, loadChart } from "@/modules/podcasts/charts"
import { cacheGet, cachePut } from "@/modules/podcasts/dbFeeds"
import { readableError } from "@/modules/podcasts/nativeError"

import { type Query, useShows } from "./hooks"

const store = { cacheGet, cachePut }

type ChartState = Query<ChartShow[]> & { chart: string }

/**
 * One chart (`TOP_CHART` or a genre id), kept for a day. The kept copy is drawn at once, even
 * an old one, while a newer one is fetched. `retry()` asks again; so does coming back to the
 * screen. A failed retry never takes away what is on screen.
 */
export function useChart(chart: string): Query<ChartShow[]> & {
  retry: () => void
} {
  const [state, setState] = useState<ChartState>({
    chart,
    data: undefined,
    loading: true,
    error: null,
  })
  // `quiet` is a round started by returning to the screen: an error stays on screen meanwhile.
  const [round, setRound] = useState({ n: 0, quiet: false })
  useEffect(() => {
    let current = true
    // Another chart starts empty; a retry of the same chart keeps its copy on screen.
    setState((before) => startChartLoad(before, chart, round.quiet))
    keptChart(chart, store).then(
      (kept) => {
        if (!current || !kept) return
        setState((before) =>
          before.data
            ? before
            : { chart, data: kept.shows, loading: false, error: null },
        )
      },
      () => {},
    )
    loadChart(chart, store).then(
      (data) => {
        if (current) setState({ chart, data, loading: false, error: null })
      },
      (cause: unknown) => {
        if (!current) return
        setState((before) => ({
          chart,
          data: before.data,
          loading: false,
          error: before.data ? null : readableError(cause),
        }))
      },
    )
    return () => {
      current = false
    }
  }, [chart, round])
  // Coming back to the screen asks again; the first focus is the screen opening.
  const opened = useRef(false)
  useFocusEffect(
    useCallback(() => {
      if (opened.current) setRound((r) => ({ n: r.n + 1, quiet: true }))
      opened.current = true
    }, []),
  )
  const retry = useCallback(
    () => setRound((r) => ({ n: r.n + 1, quiet: false })),
    [],
  )
  if (state.chart !== chart)
    return { data: undefined, loading: true, error: null, retry }
  return { data: state.data, loading: state.loading, error: state.error, retry }
}

/**
 * "For you": suggestions from the categories of the followed shows. Empty while loading, and
 * when nothing is followed or no chart could be read (Discover then shows only the charts).
 * `loaded` is true once the answer is in, so a page can tell "none yet" from "none".
 */
export function useForYouState(): {
  suggestions: ForYouSuggestion[]
  picks: ForYouPick[]
  loaded: boolean
} {
  const shows = useShows().data
  const picks = useMemo(() => pickForYou(shows ?? []), [shows])
  const [done, setDone] = useState<ForYouSuggestion[] | null>(null)
  // The library changes often (an episode saves its place every 15 s). The effect depends only
  // on what the suggestions are made from, and keeps the last answer on screen while it runs.
  const key = shows ? forYouKey(picks, shows) : null
  const latest = useRef({ shows, picks })
  latest.current = { shows, picks }

  useEffect(() => {
    const { shows: followed, picks: wanted } = latest.current
    if (!followed || wanted.length === 0) {
      setDone(null)
      return
    }
    let current = true
    Promise.allSettled(wanted.map((p) => loadChart(p.category.id, store))).then(
      (settled) => {
        if (!current) return
        const charts = new Map<string, ChartShow[]>()
        settled.forEach((result, index) => {
          const pick = wanted[index]
          if (pick && result.status === "fulfilled") {
            charts.set(pick.category.id, result.value)
          }
        })
        setDone(buildForYou(wanted, charts, followed))
      },
    )
    return () => {
      current = false
    }
  }, [key])

  const ready = shows !== undefined && (picks.length === 0 || done !== null)
  return { suggestions: done ?? [], picks, loaded: ready }
}

export function useForYou(): ForYouSuggestion[] {
  return useForYouState().suggestions
}
