// LOFI-FORK: the podcasts section's links (see FORK.md).
import { normalizeFeedUrl } from "./feedUrl"

/**
 * Whether the text typed into search is a link to follow, not words to search for: one web
 * address in any spelling `normalizeFeedUrl` reads (https, http, feed://, itpc://, pcast://,
 * or no scheme at all), as a feed or an Apple Podcasts link. The same reading `followLink`
 * applies, so what passes here can be followed. Words with a space always search.
 */
export function isFollowLink(text: string): boolean {
  const trimmed = text.trim()
  if (trimmed === "" || /\s/.test(trimmed)) return false
  try {
    normalizeFeedUrl(trimmed)
    return true
  } catch {
    return false
  }
}
