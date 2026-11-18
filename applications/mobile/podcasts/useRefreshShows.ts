// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useState } from "react"

import { followUpNew } from "@/modules/podcasts/automaticRun"
import { refreshAllShows } from "@/modules/podcasts/dbFeeds"
import { readableError } from "@/modules/podcasts/nativeError"

/**
 * Pull to refresh for the screens that list the followed shows: reads every feed again, lets
 * the new-episode rules run, and keeps a line to show when something failed.
 */
export function useRefreshShows() {
  const [refreshing, setRefreshing] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)

  async function refresh() {
    setRefreshing(true)
    setProblem(null)
    try {
      const { failed, added } = await refreshAllShows()
      await followUpNew(added)
      if (failed.length > 0)
        setProblem(`Couldn't refresh ${failed.join(", ")}.`)
    } catch (cause) {
      setProblem(readableError(cause))
    } finally {
      setRefreshing(false)
    }
  }

  return { refreshing, problem, refresh }
}
