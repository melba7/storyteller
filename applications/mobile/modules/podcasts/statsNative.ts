// LOFI-FORK: the podcasts section's stats (see FORK.md).
//
// The native calls for the listening stats, which Swift counts. Where there is no native
// module the stats are empty. Not imported by any test.
import { Podcasts } from "./index"
import { readStats, type Stats } from "./stats"

export async function getStats(): Promise<Stats> {
  return readStats(await Podcasts?.getStats())
}

/** Clears every total and every day. */
export async function resetStats(): Promise<void> {
  await Podcasts?.resetStats()
}
