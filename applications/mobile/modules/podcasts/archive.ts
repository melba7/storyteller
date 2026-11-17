// LOFI-FORK: the podcasts section's archive rules (see FORK.md).
//
// Which episodes archive themselves, as plain functions. The app runs them with the other
// automatic work (automaticRun.ts). Archiving deletes the download; the episode that is
// loaded in the player and the ones in Up Next are never archived by these rules.
import { type StoredEpisode, sortEpisodes } from "./library"
import { type ShowSettings } from "./showSettings"

const DAY_MS = 24 * 60 * 60 * 1000

export type ArchiveContext = {
  /** Milliseconds since 1970. */
  now: number
  /** The episode loaded in the player, if any. */
  loadedId: string | null
  /** The ids in Up Next. */
  queuedIds: ReadonlySet<string>
}

/** How long after it was played an episode archives, in milliseconds (0: right away). */
function playedDelay(
  setting: ShowSettings["archiveAfterPlayed"],
): number | null {
  switch (setting) {
    case "never":
      return null
    case "now":
      return 0
    case "day":
      return DAY_MS
    case "week":
      return 7 * DAY_MS
  }
}

/**
 * The ids of the show's episodes to archive now. Three rules, each off by default:
 * - after playing: played episodes, once their delay has passed since the last listen (an
 *   episode with no listen time archives only "right away");
 * - after N days unplayed: episodes never started that came out that many days ago;
 * - keep the newest N: every episode past the N newest (archived ones do not count).
 * Archived episodes, the loaded episode and queued ones are left alone.
 */
export function episodesToArchive(
  episodes: readonly StoredEpisode[],
  settings: ShowSettings,
  context: ArchiveContext,
): string[] {
  const live = episodes.filter((episode) => !episode.archived)
  const chosen = new Set<string>()

  const delay = playedDelay(settings.archiveAfterPlayed)
  if (delay !== null) {
    for (const episode of live) {
      if (!episode.played) continue
      if (delay === 0) chosen.add(episode.id)
      else if (
        episode.lastPlayedAt !== null &&
        context.now - episode.lastPlayedAt >= delay
      ) {
        chosen.add(episode.id)
      }
    }
  }

  if (settings.archiveAfterDays !== null) {
    const age = settings.archiveAfterDays * DAY_MS
    for (const episode of live) {
      if (episode.played || episode.positionSeconds > 0) continue
      if (
        episode.publishedAt !== null &&
        context.now - episode.publishedAt >= age
      ) {
        chosen.add(episode.id)
      }
    }
  }

  if (settings.keepNewest !== null) {
    for (const episode of sortEpisodes([...live]).slice(settings.keepNewest)) {
      chosen.add(episode.id)
    }
  }

  return live
    .filter(
      (episode) =>
        chosen.has(episode.id) &&
        episode.id !== context.loadedId &&
        !context.queuedIds.has(episode.id),
    )
    .map((episode) => episode.id)
}

/** Whether any of the show's archive rules is on. */
export function archivesByItself(settings: ShowSettings): boolean {
  return (
    settings.archiveAfterPlayed !== "never" ||
    settings.archiveAfterDays !== null ||
    settings.keepNewest !== null
  )
}
