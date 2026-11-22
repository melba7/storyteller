// LOFI-FORK: the podcasts section's ad skipping results (see FORK.md).
//
// The native calls behind the results page, read through the rules in adResults.ts and
// teaching.ts. Where there is no native module there is nothing to show. Not imported by any
// test.
import { type AdResults, parseTally, resultsFor } from "./adResults"
import { listShows } from "./db"
import { Podcasts } from "./index"
import { type TeachingState, parseTeachingState } from "./teaching"

/** What the phone skipped, with the shows' titles from the library. */
export async function getAdResults(): Promise<AdResults> {
  const [text, shows] = await Promise.all([
    Podcasts?.getAdTally() ?? null,
    listShows(),
  ])
  return resultsFor(parseTally(text), shows)
}

/** What the Mac taught the phone. */
export async function getTeachingState(): Promise<TeachingState> {
  return parseTeachingState((await Podcasts?.getTeachingState()) ?? null)
}
