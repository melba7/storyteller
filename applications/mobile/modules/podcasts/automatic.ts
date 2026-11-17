// LOFI-FORK: the podcasts section's automatic downloads and clean-up (see FORK.md).
//
// Pure rules for what the app does by itself when feeds refresh: which new episodes to
// download, which played downloads to delete, how often to refresh while the app is open, and
// the two settings. Reading feeds and the native calls are in automaticRun.ts.
import type { FetchedEpisode } from "./library"
import { isLocalEpisodeId } from "./localFiles"
import { type AutoUpNext } from "./showSettings"

// MARK: Settings

export type AutomaticSettings = {
  /** Download each show's newest new episode by itself, on Wi-Fi. */
  downloadNew: boolean
  /** Delete a played download a day after it was played. */
  deletePlayed: boolean
}

export const DEFAULT_SETTINGS: AutomaticSettings = {
  downloadNew: true,
  deletePlayed: true,
}

/** The saved settings; a missing, broken or partial value falls back to the defaults. */
export function parseSettings(saved: string | null): AutomaticSettings {
  if (!saved) return DEFAULT_SETTINGS
  try {
    const value: unknown = JSON.parse(saved)
    if (typeof value !== "object" || value === null) return DEFAULT_SETTINGS
    const record = value as Record<string, unknown>
    return {
      downloadNew:
        typeof record["downloadNew"] === "boolean"
          ? record["downloadNew"]
          : DEFAULT_SETTINGS.downloadNew,
      deletePlayed:
        typeof record["deletePlayed"] === "boolean"
          ? record["deletePlayed"]
          : DEFAULT_SETTINGS.deletePlayed,
    }
  } catch {
    return DEFAULT_SETTINGS
  }
}

export function serializeSettings(settings: AutomaticSettings): string {
  return JSON.stringify({
    downloadNew: settings.downloadNew,
    deletePlayed: settings.deletePlayed,
  })
}

// MARK: New episodes

/** An episode a refresh added to the library. */
export type NewEpisode = {
  id: string
  showId: string
  publishedAt: number | null
  audioUrl: string
  audioType: string
}

/** The episodes a refresh inserted, with the ids they were saved under. */
export function newEpisodes(
  showId: string,
  inserted: readonly FetchedEpisode[],
  ids: readonly string[],
): NewEpisode[] {
  return inserted.flatMap((episode, index) => {
    const id = ids[index]
    return id === undefined
      ? []
      : [
          {
            id,
            showId,
            publishedAt: episode.publishedAt,
            audioUrl: episode.audioUrl,
            audioType: episode.audioType,
          },
        ]
  })
}

/**
 * Which of the episodes a refresh just added to download: the newest of each show, and
 * nothing when the setting is off. Only newly added episodes count, so an episode the
 * listener deleted (it is not new any more) is never fetched again. An undated episode is
 * older than any dated one. A show whose own switch is off (`downloads`, show id to value;
 * a show not in it counts as on) downloads nothing.
 */
export function episodesToDownload(
  added: readonly NewEpisode[],
  settings: AutomaticSettings,
  downloads: ReadonlyMap<string, boolean> = new Map(),
): NewEpisode[] {
  if (!settings.downloadNew) return []
  const newest = new Map<string, NewEpisode>()
  for (const episode of added) {
    if (downloads.get(episode.showId) === false) continue
    const best = newest.get(episode.showId)
    if (
      !best ||
      (episode.publishedAt ?? -Infinity) > (best.publishedAt ?? -Infinity)
    ) {
      newest.set(episode.showId, episode)
    }
  }
  return [...newest.values()]
}

/**
 * The new episodes to put in Up Next, in the order to add them, each with where it goes.
 * `modes` is show id to the show's setting (a show not in it is off). Adding to the top puts
 * each one first, so the newest goes in first and the oldest new episode ends up on top;
 * adding to the bottom goes oldest first, so the oldest ends up first of the new ones.
 */
export function episodesForUpNext(
  added: readonly NewEpisode[],
  modes: ReadonlyMap<string, AutoUpNext>,
): { episode: NewEpisode; place: "next" | "last" }[] {
  const byDate = (a: NewEpisode, b: NewEpisode) =>
    (a.publishedAt ?? -Infinity) === (b.publishedAt ?? -Infinity)
      ? 0
      : (a.publishedAt ?? -Infinity) < (b.publishedAt ?? -Infinity)
        ? -1
        : 1
  const oldestFirst = [...added].sort(byDate)
  const top = oldestFirst
    .filter((episode) => modes.get(episode.showId) === "top")
    .reverse()
    .map((episode) => ({ episode, place: "next" as const }))
  const bottom = oldestFirst
    .filter((episode) => modes.get(episode.showId) === "bottom")
    .map((episode) => ({ episode, place: "last" as const }))
  return [...top, ...bottom]
}

// MARK: Played downloads

export const DAY_MS = 24 * 60 * 60 * 1000

/** A downloaded episode, with what the library knows about listening to it. */
export type DownloadedEpisode = {
  id: string
  played: boolean
  /** Milliseconds since 1970, or null when it was never played. */
  lastPlayedAt: number | null
}

/**
 * Which downloads to delete: played ones whose last listen was more than a day ago. An
 * episode with no last-played time is kept, and so is the one loaded in the player.
 */
export function downloadsToDelete(
  episodes: readonly DownloadedEpisode[],
  now: number,
  loadedId: string | null,
  settings: AutomaticSettings,
): string[] {
  if (!settings.deletePlayed) return []
  return episodes
    .filter(
      (episode) =>
        !isLocalEpisodeId(episode.id) &&
        episode.played &&
        episode.id !== loadedId &&
        episode.lastPlayedAt !== null &&
        now - episode.lastPlayedAt > DAY_MS,
    )
    .map((episode) => episode.id)
}

// MARK: How often

/** While the app is open, feeds refresh when it comes to the front, at most this often. */
export const FOREGROUND_GAP_MS = 30 * 60 * 1000

/** Whether the last refresh was long enough ago. A never-run or future time counts as due. */
export function refreshDue(lastRunAt: number | null, now: number): boolean {
  if (lastRunAt === null || lastRunAt > now) return true
  return now - lastRunAt >= FOREGROUND_GAP_MS
}
