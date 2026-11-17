// LOFI-FORK: the podcasts section's spoken-word search (see FORK.md).
//
// Asks Swift for the hits, then finds each hit's episode and show in the library. Not imported
// by any test, because the database and the native module are not there; the rules are in
// spoken.ts.
import { listEpisodesByIds, listShows } from "./db"
import { type Show, type StoredEpisode } from "./library"
import { type SpokenGroup, groupSpoken } from "./spoken"
import { searchTranscripts } from "./transcriptsNative"

export type SpokenResult = SpokenGroup<StoredEpisode, Show>

export async function searchSpoken(query: string): Promise<SpokenResult[]> {
  const hits = await searchTranscripts(query)
  if (hits.length === 0) return []
  const ids = [...new Set(hits.map((hit) => hit.episodeId))]
  const [episodes, shows] = await Promise.all([
    listEpisodesByIds(ids),
    listShows(),
  ])
  const showById = new Map(shows.map((show) => [show.id, show]))
  const known = new Map(
    episodes.map((episode) => [
      episode.id,
      { episode, show: showById.get(episode.showId) ?? null },
    ]),
  )
  return groupSpoken(hits, known)
}
