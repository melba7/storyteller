// LOFI-FORK: the podcasts section's ads (see FORK.md).
//
// Thin wrappers over the native module's ad functions. Not imported by any test, because the
// native module is not there; the rules are in ads.ts.
import { type AdsInfo, Podcasts } from "./index"

export async function listAds(): Promise<AdsInfo[]> {
  return (await Podcasts?.listAds()) ?? []
}

/** An episode's saved ads as JSON text, or null. */
export async function getAds(episodeId: string): Promise<string | null> {
  return (await Podcasts?.getAds(episodeId)) ?? null
}
