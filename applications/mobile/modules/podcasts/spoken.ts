// LOFI-FORK: the podcasts section's spoken-word search rules (see FORK.md).
//
// Joins what Swift found in the transcripts to the library's episodes and shows, and groups
// it by episode for the search screen. The searching itself is Swift (TranscriptSearch).
import { formatTime } from "./playbackRules"

export const SPOKEN_EMPTY_NOTE =
  "Episodes are searchable once they're downloaded and transcribed."

/** One place the words were said, as Swift reports it. */
export type SpokenFound = {
  episodeId: string
  seconds: number
  text: string
  before: string
  after: string
}

export type SpokenGroup<
  E extends { id: string; publishedAt: number | null },
  S,
> = {
  episode: E
  show: S | null
  hits: SpokenFound[]
}

/** "12:34", or "1:02:05" past an hour. */
export function spokenTime(seconds: number): string {
  return formatTime(seconds)
}

/**
 * The hits grouped by episode: newest episode first (undated last), each episode's hits in
 * the order Swift gave them. Hits of an episode that is not in `known` are left out.
 */
export function groupSpoken<
  E extends { id: string; publishedAt: number | null },
  S,
>(
  hits: readonly SpokenFound[],
  known: ReadonlyMap<string, { episode: E; show: S | null }>,
): SpokenGroup<E, S>[] {
  const groups = new Map<string, SpokenGroup<E, S>>()
  for (const found of hits) {
    const owner = known.get(found.episodeId)
    if (!owner) continue
    const group = groups.get(found.episodeId)
    if (group) group.hits.push(found)
    else groups.set(found.episodeId, { ...owner, hits: [found] })
  }
  return [...groups.values()].sort(
    (a, b) =>
      (b.episode.publishedAt ?? -Infinity) -
      (a.episode.publishedAt ?? -Infinity),
  )
}
