// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { listHistory, listStarred } from "@/modules/podcasts/dbEpisodes"
import { type StoredEpisode } from "@/modules/podcasts/library"

import { type Query, useLibraryQuery } from "./hooks"

/** The episodes listened to, the most recent first. */
export function useHistory(): Query<StoredEpisode[]> {
  return useLibraryQuery(listHistory, "history")
}

/** The starred episodes, the one starred last first. */
export function useStarred(): Query<StoredEpisode[]> {
  return useLibraryQuery(listStarred, "starred")
}
