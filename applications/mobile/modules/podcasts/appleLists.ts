// LOFI-FORK: the podcasts section's follow list from Apple Podcasts (see FORK.md).
import { serialByKey } from "./serialByKey"

const run = serialByKey()

/**
 * Runs a job that reads, changes and writes the applied and pending lists, one at a time, so a
 * refresh settling an arrived episode and the sync never overwrite each other's change.
 */
export function withAppleLists<T>(job: () => Promise<T>): Promise<T> {
  return run("apple-lists", job)
}
