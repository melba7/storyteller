import { UP_NEXT_LIMIT } from "./homeSql"
// LOFI-FORK: the podcasts section's Home (see FORK.md).
//
// Pure rules for Home: the order of the Up Next shelf and of "Your Top Shows".
import { type Show, type StoredEpisode } from "./library"
import { LOCAL_SHOW_ID } from "./localFiles"

export type ShelfEntry = {
  episode: StoredEpisode
  /** "resume" for one in progress, "new" for the newest unplayed one of its show. */
  kind: "resume" | "new"
}

const inProgress = (episode: StoredEpisode) =>
  !episode.played && episode.positionSeconds > 0

/** Larger first; a missing value last; ties by id so the order never jumps. */
function newestFirst(
  a: { id: string; at: number | null },
  b: { id: string; at: number | null },
): number {
  if (a.at === b.at) return a.id.localeCompare(b.id)
  if (a.at === null) return 1
  if (b.at === null) return -1
  return b.at - a.at
}

/**
 * Home's Up Next shelf from the candidates (`UP_NEXT_CANDIDATES_SQL`): episodes in progress,
 * the one played last first, then the newest unplayed episode of each followed show, newest
 * first. No episode twice, no more than `limit`. An added file only counts while in
 * progress, and only one "new" episode per show.
 */
export function orderUpNextShelf(
  candidates: readonly StoredEpisode[],
  limit = UP_NEXT_LIMIT,
): ShelfEntry[] {
  const seen = new Set<string>()
  const resume: StoredEpisode[] = []
  const fresh = new Map<string, StoredEpisode>()
  for (const episode of candidates) {
    if (seen.has(episode.id) || episode.played || episode.archived) continue
    seen.add(episode.id)
    if (inProgress(episode)) {
      resume.push(episode)
    } else if (episode.showId !== LOCAL_SHOW_ID) {
      const best = fresh.get(episode.showId)
      if (
        !best ||
        newestFirst(
          { id: episode.id, at: episode.publishedAt },
          { id: best.id, at: best.publishedAt },
        ) < 0
      ) {
        fresh.set(episode.showId, episode)
      }
    }
  }
  resume.sort((a, b) =>
    newestFirst(
      { id: a.id, at: a.lastPlayedAt },
      { id: b.id, at: b.lastPlayedAt },
    ),
  )
  const added = [...fresh.values()].sort((a, b) =>
    newestFirst(
      { id: a.id, at: a.publishedAt },
      { id: b.id, at: b.publishedAt },
    ),
  )
  return [
    ...resume.map((episode) => ({ episode, kind: "resume" as const })),
    ...added.map((episode) => ({ episode, kind: "new" as const })),
  ].slice(0, limit)
}

/**
 * "Your Top Shows": the followed shows listened to most recently first, then the rest by
 * their newest episode (the show with none last), then by title. The Swift stats count time
 * only for the whole library, not per show, so recent plays are what ranks them.
 */
export function rankTopShows(
  shows: readonly Show[],
  lastPlayedAt: ReadonlyMap<string, number>,
  newestAt: ReadonlyMap<string, number | null>,
  limit = 12,
): Show[] {
  return shows
    .filter((show) => show.id !== LOCAL_SHOW_ID)
    .sort((a, b) => {
      const x = lastPlayedAt.get(a.id) ?? null
      const y = lastPlayedAt.get(b.id) ?? null
      if (x !== y) return x === null ? 1 : y === null ? -1 : y - x
      const n = newestAt.get(a.id) ?? null
      const m = newestAt.get(b.id) ?? null
      if (n !== m) return n === null ? 1 : m === null ? -1 : m - n
      return a.title.localeCompare(b.title) || a.id.localeCompare(b.id)
    })
    .slice(0, limit)
}
