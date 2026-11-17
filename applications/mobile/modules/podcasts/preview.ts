// LOFI-FORK: the podcasts section's show preview (see FORK.md).
//
// A preview reads a feed without saving it. The show and its episodes get temporary ids
// that no library row has, so the player can play them while saving no place for them.
import { type PodcastFeedData } from "./index"
import {
  type Show,
  type StoredEpisode,
  fetchedEpisode,
  sortEpisodes,
} from "./library"
import { DEFAULT_SHOW_SETTINGS } from "./showSettings"

const PREVIEW_PREFIX = "preview:"

/** True for the temporary id of a previewed show or episode. */
export function isPreviewId(id: string): boolean {
  return id.startsWith(PREVIEW_PREFIX)
}

export type Preview = { show: Show; episodes: StoredEpisode[] }

/** The feed as a show and episodes, newest first, none played and with no place kept. */
export function previewFromFeed(
  feedUrl: string,
  feed: PodcastFeedData,
): Preview {
  const showId = `${PREVIEW_PREFIX}${feedUrl}`
  const seen = new Set<string>()
  const episodes: StoredEpisode[] = []
  for (const raw of feed.episodes) {
    if (seen.has(raw.guid)) continue
    seen.add(raw.guid)
    episodes.push({
      ...fetchedEpisode(raw),
      id: `${showId}#${raw.guid}`,
      showId,
      positionSeconds: 0,
      played: false,
      lastPlayedAt: null,
      archived: false,
      starredAt: null,
    })
  }
  return {
    show: {
      id: showId,
      feedUrl,
      title: feed.title,
      author: feed.author ?? null,
      description: feed.description,
      imageUrl: feed.imageUrl ?? null,
      link: feed.link ?? null,
      language: feed.language ?? null,
      addedAt: 0,
      refreshedAt: 0,
      artworkColor: null,
      ownPosition: null,
      categories: feed.categories ?? [],
      settings: DEFAULT_SHOW_SETTINGS,
    },
    episodes: sortEpisodes(episodes),
  }
}

/** What a search result knows about its episode: the feed's guid and the audio address. */
export type EpisodeTarget = {
  guid?: string | null | undefined
  audioUrl?: string | null | undefined
}

/** An audio address without its scheme, query and trailing slash, in lower case. */
function audioKey(url: string): string {
  return url
    .trim()
    .toLowerCase()
    .replace(/^https?:\/\//, "")
    .replace(/[?#].*$/, "")
    .replace(/\/+$/, "")
}

/**
 * The place in the preview's list of the episode a search result meant: by the feed's guid,
 * or else by the audio address. -1 when the feed has no such episode, or none was named.
 */
export function findEpisodeIndex(
  episodes: Pick<StoredEpisode, "guid" | "audioUrl">[],
  target: EpisodeTarget,
): number {
  if (target.guid) {
    const byGuid = episodes.findIndex((e) => e.guid === target.guid)
    if (byGuid >= 0) return byGuid
  }
  if (target.audioUrl) {
    const wanted = audioKey(target.audioUrl)
    if (wanted !== "")
      return episodes.findIndex((e) => audioKey(e.audioUrl) === wanted)
  }
  return -1
}
