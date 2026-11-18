// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useCallback, useEffect, useState } from "react"

import {
  type ChartListUpdate,
  type ListState,
  applyListEvent,
  loadChartGroups,
} from "@/modules/podcasts/chartBatch"
import { cacheGet, cachePut } from "@/modules/podcasts/dbFeeds"

const store = { cacheGet, cachePut }
const LOADING: ListState = { status: "loading" }

export type ChartListStates = Record<string, ListState>

/**
 * Loads the chart lists with these ids and holds each one's state. Nothing starts until
 * `enabled` (Home and New wait for the followed shows, because they decide the order). Two
 * pages asking for the same list together fetch it once: `loadChartGroups` shares one
 * in-flight promise per list. `retry()` asks again; lists that are fresh cost no request.
 */
export function useChartLists(ids: string[], enabled: boolean) {
  const key = ids.join(",")
  const [states, setStates] = useState<ChartListStates>({})
  const [round, setRound] = useState(0)

  useEffect(() => {
    if (!enabled || key === "") return
    let current = true
    // A list that was missing gets another try, so it shows its skeleton again.
    setStates((before) => {
      const next: ChartListStates = {}
      for (const id of key.split(",")) {
        const old = before[id]
        next[id] = !old || old.status === "missing" ? LOADING : old
      }
      return next
    })
    const onList = (id: string, update: ChartListUpdate) => {
      if (!current) return
      setStates((before) => ({
        ...before,
        [id]: applyListEvent(before[id] ?? LOADING, update),
      }))
    }
    loadChartGroups(key.split(","), store, onList).catch(() => {})
    return () => {
      current = false
    }
  }, [key, enabled, round])

  const retry = useCallback(() => setRound((r) => r + 1), [])
  return { states, retry }
}
