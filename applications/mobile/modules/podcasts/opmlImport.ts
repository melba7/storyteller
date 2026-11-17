// LOFI-FORK: the podcasts section's OPML reading and writing (see FORK.md).
//
// Following the shows of an OPML file: the ones already followed are left alone, the rest are
// followed one after the other, with a progress line, and a summary of what happened. The
// follow itself is handed in, so the rules are tested without the database.
import { normalizeFeedUrl } from "./feedUrl"
import type { OpmlFeed } from "./opml"

export type ImportSummary = {
  added: number
  alreadyFollowed: number
  failed: { title: string; reason: string }[]
}

function reasonOf(cause: unknown): string {
  return cause instanceof Error ? cause.message : "It couldn't be followed."
}

/**
 * Follows each feed that is not followed yet. `followed` holds the addresses already in the
 * library (any spelling). Two outlines for the same feed count once. `onProgress` is called
 * before each follow with how many are done and how many there are to go through.
 */
export async function importFeeds(
  feeds: readonly OpmlFeed[],
  followed: readonly string[],
  follow: (feedUrl: string) => Promise<unknown>,
  onProgress: (done: number, total: number) => void = () => {},
): Promise<ImportSummary> {
  const known = new Set<string>()
  for (const url of followed) {
    try {
      known.add(normalizeFeedUrl(url))
    } catch {
      // A stored address that does not read cannot match anything.
    }
  }
  const summary: ImportSummary = { added: 0, alreadyFollowed: 0, failed: [] }
  let done = 0
  for (const feed of feeds) {
    onProgress(done, feeds.length)
    done += 1
    const name = feed.title || feed.feedUrl
    let url: string
    try {
      url = normalizeFeedUrl(feed.feedUrl)
    } catch (cause) {
      summary.failed.push({ title: name, reason: reasonOf(cause) })
      continue
    }
    if (known.has(url)) {
      summary.alreadyFollowed += 1
      continue
    }
    try {
      await follow(url)
      known.add(url)
      summary.added += 1
    } catch (cause) {
      summary.failed.push({ title: name, reason: reasonOf(cause) })
    }
  }
  onProgress(feeds.length, feeds.length)
  return summary
}

/** "Following 3 of 12" while it runs. */
export function progressLine(done: number, total: number): string {
  return `Following ${Math.min(done + 1, total)} of ${total}`
}

/** The summary in words: "2 added, 1 already followed, 1 failed". */
export function summaryLine(summary: ImportSummary): string {
  const parts = [`${summary.added} added`]
  if (summary.alreadyFollowed > 0) {
    parts.push(`${summary.alreadyFollowed} already followed`)
  }
  if (summary.failed.length > 0) parts.push(`${summary.failed.length} failed`)
  return parts.join(", ")
}
