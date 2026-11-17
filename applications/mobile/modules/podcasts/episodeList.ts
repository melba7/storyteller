// LOFI-FORK: the podcasts section's show page list (see FORK.md).
//
// What the show page lists: archived episodes hidden unless asked for, sorted, and grouped by
// season when the show's view says so. The choice is the show's (columns on `shows`).
import { type StoredEpisode } from "./library"
import { type EpisodeSort } from "./showSettings"

export type EpisodeListItem =
  | { kind: "header"; key: string; title: string }
  | { kind: "episode"; key: string; episode: StoredEpisode }

/** Newest first for "newest", else by the key; episodes with no value go last. Stable. */
export function sortForView(
  episodes: readonly StoredEpisode[],
  sort: EpisodeSort,
): StoredEpisode[] {
  const value = (episode: StoredEpisode): number | null =>
    sort === "newest" || sort === "oldest"
      ? episode.publishedAt
      : episode.durationSeconds
  const descending = sort === "newest" || sort === "longest"
  return episodes
    .map((episode, index) => ({ episode, index }))
    .sort((a, b) => {
      const left = value(a.episode)
      const right = value(b.episode)
      if (left === right) return a.index - b.index
      if (left === null) return 1
      if (right === null) return -1
      return descending ? right - left : left - right
    })
    .map(({ episode }) => episode)
}

export function seasonTitle(season: number | null): string {
  return season === null ? "Other episodes" : `Season ${season}`
}

/**
 * The page's rows. `episodes` come in any order. Archived ones are left out unless
 * `showArchived`. With `groupBySeason` each season gets a header, the highest season first
 * (the lowest first for "oldest"), and episodes with no season come last; each group is
 * sorted the same way.
 */
export function arrangeEpisodes(
  episodes: readonly StoredEpisode[],
  view: { sort: EpisodeSort; groupBySeason: boolean; showArchived: boolean },
): EpisodeListItem[] {
  const shown = episodes.filter(
    (episode) => view.showArchived || !episode.archived,
  )
  const sorted = sortForView(shown, view.sort)
  const row = (episode: StoredEpisode): EpisodeListItem => ({
    kind: "episode",
    key: episode.id,
    episode,
  })
  if (!view.groupBySeason) return sorted.map(row)

  const bySeason = new Map<number | null, StoredEpisode[]>()
  for (const episode of sorted) {
    const group = bySeason.get(episode.season) ?? []
    group.push(episode)
    bySeason.set(episode.season, group)
  }
  const seasons = [...bySeason.keys()].filter((s): s is number => s !== null)
  seasons.sort((a, b) => (view.sort === "oldest" ? a - b : b - a))
  const order: (number | null)[] = bySeason.has(null)
    ? [...seasons, null]
    : seasons
  return order.flatMap((season) => [
    {
      kind: "header" as const,
      key: `season:${season ?? "none"}`,
      title: seasonTitle(season),
    },
    ...(bySeason.get(season) ?? []).map(row),
  ])
}

/** How many archived episodes the page is hiding, for the "Show archived" line. */
export function archivedCount(episodes: readonly StoredEpisode[]): number {
  return episodes.filter((episode) => episode.archived).length
}
