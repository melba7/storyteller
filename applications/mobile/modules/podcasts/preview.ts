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
import { fundingFromJson, peopleFromJson, toJson } from "./people"
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
      funding: fundingFromJson(toJson(feed.funding)),
      people: peopleFromJson(toJson(feed.people)),
      settings: DEFAULT_SHOW_SETTINGS,
    },
    episodes: sortEpisodes(episodes),
  }
}

/**
 * What a search result or chart knows about its episode: the feed's guid, the audio address
 * and, for the charts that have neither, the title.
 */
export type EpisodeTarget = {
  guid?: string | null | undefined
  audioUrl?: string | null | undefined
  title?: string | null | undefined
}

/** A title trimmed, with runs of spaces made one and in lower case. */
function titleKey(title: string): string {
  return title.trim().replace(/\s+/g, " ").toLowerCase()
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
 * else by the audio address, else by the title when exactly one episode has it. -1 when the
 * feed has no such episode, or none was named.
 */
export function findEpisodeIndex(
  episodes: (Pick<StoredEpisode, "guid" | "audioUrl"> & { title?: string })[],
  target: EpisodeTarget,
): number {
  if (target.guid) {
    const byGuid = episodes.findIndex((e) => e.guid === target.guid)
    if (byGuid >= 0) return byGuid
  }
  if (target.audioUrl) {
    const wanted = audioKey(target.audioUrl)
    const byAudio =
      wanted === ""
        ? -1
        : episodes.findIndex((e) => audioKey(e.audioUrl) === wanted)
    if (byAudio >= 0) return byAudio
  }
  const wanted = titleKey(target.title ?? "")
  if (wanted === "") return -1
  const matches = episodes.flatMap((e, index) =>
    titleKey(e.title ?? "") === wanted ? [index] : [],
  )
  return matches.length === 1 ? matches[0]! : -1
}

/**
 * The id of the library episode that a chart or search result meant, matched like
 * `findEpisodeIndex` does; null when the library has no such episode or none was named.
 */
export function matchEpisodeId(
  episodes: (Pick<StoredEpisode, "id" | "guid" | "audioUrl"> & {
    title?: string
  })[],
  target: EpisodeTarget,
): string | null {
  const index = findEpisodeIndex(episodes, target)
  return index < 0 ? null : (episodes[index]?.id ?? null)
}
