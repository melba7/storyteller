// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useEffect, useState, useSyncExternalStore } from "react"

import { libraryVersion, onLibraryChanged } from "@/modules/podcasts/changes"
import {
  getEpisode,
  getShow,
  listEpisodes,
  listEpisodesByIds,
  listShowActivity,
  listShows,
} from "@/modules/podcasts/db"
import { type Show, type StoredEpisode } from "@/modules/podcasts/library"
import { type ActivityByShow } from "@/modules/podcasts/libraryView"
import { readableError } from "@/modules/podcasts/nativeError"

export type Query<T> = {
  data: T | undefined
  loading: boolean
  error: string | null
}

/**
 * Reads from the library and reads again whenever the library changes (a show added,
 * refreshed or removed) or `key` changes.
 */
function useLibraryQuery<T>(load: () => Promise<T>, key: string): Query<T> {
  const version = useSyncExternalStore(onLibraryChanged, libraryVersion)
  const [state, setState] = useState<Query<T>>({
    data: undefined,
    loading: true,
    error: null,
  })

  useEffect(() => {
    let current = true
    load().then(
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
    // `load` is a new function each render; `key` and the version say when to read again.
    // oxlint-disable-next-line react-hooks/exhaustive-deps
  }, [key, version])

  return state
}

export function useShows(): Query<Show[]> {
  return useLibraryQuery(listShows, "shows")
}

/** Each show's newest episode and unplayed count, for the library's order and badges. */
export function useShowActivity(): Query<ActivityByShow> {
  return useLibraryQuery(listShowActivity, "show-activity")
}

/** The show, or null when the library has no show with this id. */
export function useShow(id: string): Query<Show | null> {
  return useLibraryQuery(() => getShow(id), `show:${id}`)
}

/** The show's episodes, newest first. */
export function useEpisodes(showId: string): Query<StoredEpisode[]> {
  return useLibraryQuery(() => listEpisodes(showId), `episodes:${showId}`)
}

export function useEpisode(id: string): Query<StoredEpisode | null> {
  return useLibraryQuery(() => getEpisode(id), `episode:${id}`)
}

/** The library's episodes with these ids (the Downloads list reads its titles from here). */
export function useEpisodesByIds(
  ids: readonly string[],
): Query<StoredEpisode[]> {
  return useLibraryQuery(
    () => listEpisodesByIds(ids),
    `episodes-by-ids:${ids.join(",")}`,
  )
}
