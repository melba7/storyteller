// LOFI-FORK: the podcasts section's moved feeds (see FORK.md).
import { feedKey, findShowByFeed } from "./applePodcasts"
import { normalizeFeedUrl } from "./feedUrl"

/**
 * The address a show's feed has moved to, or null when it has not moved. `newFeedUrl` is the
 * feed's `itunes:new-feed-url`. A missing, empty, non-web or malformed value is no move, and
 * so is an address of the same feed under another spelling or one that another followed show
 * already has (the address is unique, so the show stays where it is).
 */
export function movedFeedUrl(
  show: { id: string; feedUrl: string },
  newFeedUrl: unknown,
  shows: readonly { id: string; feedUrl: string }[],
): string | null {
  if (typeof newFeedUrl !== "string") return null
  const text = newFeedUrl.trim()
  if (!/^https?:\/\//i.test(text)) return null
  let moved: string
  try {
    moved = normalizeFeedUrl(text)
  } catch {
    return null
  }
  if (feedKey(moved) === feedKey(show.feedUrl)) return null
  const other = findShowByFeed(shows, moved)
  return other && other.id !== show.id ? null : moved
}
