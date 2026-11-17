// LOFI-FORK: the podcasts section's links (see FORK.md).
import { normalizeFeedUrl } from "./feedUrl"

/**
 * Whether the text typed into search is a link to follow, not words to search for: one web
 * address with an http or https scheme (a feed, or an Apple Podcasts link, which is one too).
 * The same reading `followLink` applies, so what passes here can be followed.
 */
export function isFollowLink(text: string): boolean {
  const trimmed = text.trim()
  if (!/^https?:\/\/\S+$/i.test(trimmed)) return false
  try {
    normalizeFeedUrl(trimmed)
    return true
  } catch {
    return false
  }
}
