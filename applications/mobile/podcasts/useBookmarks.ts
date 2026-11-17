import { type Bookmark } from "@/modules/podcasts/bookmarks"
// LOFI-FORK: the podcasts section's screens (see FORK.md).
import {
  listAllBookmarks,
  listEpisodeBookmarks,
} from "@/modules/podcasts/dbBookmarks"

import { type Query, useLibraryQuery } from "./hooks"

/** One episode's bookmarks, in the order of the episode. */
export function useEpisodeBookmarks(episodeId: string): Query<Bookmark[]> {
  return useLibraryQuery(
    () => listEpisodeBookmarks(episodeId),
    `bookmarks:${episodeId}`,
  )
}

/** Every bookmark, the newest first. */
export function useAllBookmarks(): Query<Bookmark[]> {
  return useLibraryQuery(listAllBookmarks, "bookmarks")
}
