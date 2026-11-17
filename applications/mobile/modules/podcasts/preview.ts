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
    },
    episodes: sortEpisodes(episodes),
  }
}
