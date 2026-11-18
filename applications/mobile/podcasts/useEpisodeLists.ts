// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { listHistory, listStarred } from "@/modules/podcasts/dbEpisodes"
import { listLatest, listRecentShows } from "@/modules/podcasts/dbRooms"
import { type StoredEpisode } from "@/modules/podcasts/library"
import { type RecentShow } from "@/modules/podcasts/rooms"

import { type Query, useLibraryQuery } from "./hooks"

/** The episodes listened to, the most recent first. */
export function useHistory(): Query<StoredEpisode[]> {
  return useLibraryQuery(listHistory, "history")
}

/** The starred episodes, the one starred last first. */
export function useStarred(): Query<StoredEpisode[]> {
  return useLibraryQuery(listStarred, "starred")
}

/** The newest episodes of the followed shows, not archived, newest first. */
export function useLatest(): Query<StoredEpisode[]> {
  return useLibraryQuery(listLatest, "latest")
}

/** The followed shows by their newest episode, for Library's "Recently Updated". */
export function useRecentShows(): Query<RecentShow[]> {
  return useLibraryQuery(listRecentShows, "recent-shows")
}
