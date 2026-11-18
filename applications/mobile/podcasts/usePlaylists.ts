// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useMemo } from "react"

import {
  getPlaylist,
  itemCounts,
  listEntries,
  listPlaylists,
  smartEpisodes,
} from "@/modules/podcasts/dbPlaylists"
import { type StoredEpisode } from "@/modules/podcasts/library"
import { type PlaylistEntry } from "@/modules/podcasts/manualPlaylist"
import {
  filterDownloaded,
  serializeRules,
} from "@/modules/podcasts/playlistRules"
import { type Playlist } from "@/modules/podcasts/playlists"

import { type Query, useLibraryQuery } from "./hooks"
import { useDownloadedIds } from "./useDownloads"

export function usePlaylists(): Query<Playlist[]> {
  return useLibraryQuery(listPlaylists, "playlists")
}

/** The playlist, or null when there is no playlist with this id. */
export function usePlaylist(id: string): Query<Playlist | null> {
  return useLibraryQuery(() => getPlaylist(id), `playlist:${id}`)
}

/** The episodes of a smart playlist, in its order, read again when the library changes. */
export function useSmartEpisodes(
  playlist: Playlist | null | undefined,
): Query<StoredEpisode[]> {
  const onPhone = useDownloadedIds()
  const key = playlist
    ? `smart:${playlist.id}:${serializeRules(playlist.rules)}:${playlist.sort}`
    : "smart:none"
  const found = useLibraryQuery(
    () => (playlist ? smartEpisodes(playlist) : Promise.resolve([])),
    key,
  )
  const data = useMemo(() => {
    if (!playlist || !found.data) return found.data
    return filterDownloaded(found.data, playlist.rules, onPhone)
  }, [found.data, playlist, onPhone])
  return { ...found, data }
}

/** A hand-filled playlist's episodes, in order. */
export function useEntries(playlistId: string): Query<PlaylistEntry[]> {
  return useLibraryQuery(
    () => listEntries(playlistId),
    `playlist-entries:${playlistId}`,
  )
}

/** How many items each hand-filled playlist holds, by playlist id. */
export function useItemCounts(): Query<Map<string, number>> {
  return useLibraryQuery(itemCounts, "playlist-item-counts")
}
