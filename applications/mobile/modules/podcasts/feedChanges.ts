// LOFI-FORK: the podcasts section's feed refresh (see FORK.md).
//
// Pure rule for the refresh: did reading a feed again change anything the screens show? The
// refresh runs for every show on each app open, so a screen should read the library again only
// when this says yes. dbFeeds.ts cannot be imported by a test (it opens op-sqlite), so the rule
// lives here.
import type { PodcastFeedData } from "./index"
import type { Show } from "./library"
import { fundingFromJson, peopleFromJson, toJson } from "./people"

/**
 * True when the feed differs from the stored show, or when the refresh added or changed an
 * episode. The show is compared on the nine values that `readFeedAgain` (dbFeeds.ts) writes with
 * its `UPDATE shows` statement, each made the same way there. `refreshed_at` is left out: no
 * screen shows it. A new column in that statement needs a line here too.
 */
export function feedChanged(
  stored: Show,
  feed: PodcastFeedData,
  counts: { inserted: number; updated: number },
): boolean {
  if (counts.inserted > 0 || counts.updated > 0) return true
  return (
    stored.title !== feed.title ||
    stored.author !== (feed.author ?? null) ||
    stored.description !== feed.description ||
    stored.imageUrl !== (feed.imageUrl ?? null) ||
    stored.link !== (feed.link ?? null) ||
    stored.language !== (feed.language ?? null) ||
    JSON.stringify(stored.categories) !==
      JSON.stringify(feed.categories ?? []) ||
    toJson(stored.funding) !== toJson(fundingFromJson(toJson(feed.funding))) ||
    toJson(stored.people) !== toJson(peopleFromJson(toJson(feed.people)))
  )
}
