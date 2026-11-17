// LOFI-FORK: the podcasts section's new-episode notifications (see FORK.md).
//
// The rule for what to say after a refresh: one notice per show, however many episodes it
// gained. Posting is in notificationsNative.ts and newEpisodeNotify.ts.

/** One notification: `id` is the show's, so a later one for the same show replaces it. */
export type Notice = { id: string; title: string; body: string }

/**
 * The notices for the episodes a refresh added: one per show, in the order the shows first
 * appear. A show with one new episode names it; with several it says "3 new episodes".
 * `shows` and `titles` are the shows' and episodes' names by id; a missing name falls back
 * to plain words.
 */
export function noticesForNewEpisodes(
  added: readonly { id: string; showId: string }[],
  shows: ReadonlyMap<string, string>,
  titles: ReadonlyMap<string, string>,
): Notice[] {
  const byShow = new Map<string, string[]>()
  for (const episode of added) {
    const ids = byShow.get(episode.showId)
    if (ids) ids.push(episode.id)
    else byShow.set(episode.showId, [episode.id])
  }
  return [...byShow].map(([showId, ids]) => {
    const first = ids[0] ?? ""
    const single = titles.get(first)?.trim()
    return {
      id: showId,
      title: shows.get(showId)?.trim() || "New episode",
      body:
        ids.length === 1
          ? single || "A new episode is ready."
          : `${ids.length} new episodes`,
    }
  })
}
