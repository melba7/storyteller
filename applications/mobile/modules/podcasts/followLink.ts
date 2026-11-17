// LOFI-FORK: the podcasts section's links (see FORK.md).
//
// Follows the show a pasted link points at: an RSS link directly, or an Apple Podcasts share
// link through Apple's free lookup. Not imported by any test, because the library database is
// native; the link reading is in directory.ts.
import { listEpisodes } from "./db"
import { subscribe } from "./dbFeeds"
import {
  lookupAppleEpisode,
  lookupFeedUrl,
  parseAppleLink,
  pickEpisode,
} from "./directory"
import { type Show } from "./library"

export type FollowedLink = {
  show: Show
  /** The episode an Apple link named, when the feed has it. */
  episodeId: string | null
}

/**
 * Subscribes to the show behind the link, or returns it when it is already followed. For an
 * Apple link with `?i=`, also finds that episode. Throws a message to read.
 */
export async function followLink(input: string): Promise<FollowedLink> {
  const apple = parseAppleLink(input)
  if (!apple) return { show: await subscribe(input), episodeId: null }
  const show = await subscribe(await lookupFeedUrl(apple.showId))
  if (!apple.episodeId) return { show, episodeId: null }
  const match = await lookupAppleEpisode(apple.showId, apple.episodeId)
  if (!match) return { show, episodeId: null }
  return { show, episodeId: pickEpisode(await listEpisodes(show.id), match) }
}
