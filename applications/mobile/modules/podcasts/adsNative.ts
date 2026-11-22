// LOFI-FORK: the podcasts section's ads (see FORK.md).
//
// Thin wrappers over the native module's ad functions. Not imported by any test, because the
// native module is not there; the rules are in ads.ts.
import { SKIP_NOTE_BACK_SECONDS, readAdSkipSettings } from "./ads"
import { type AdSkipSettings, type AdsInfo, Podcasts } from "./index"

export async function listAds(): Promise<AdsInfo[]> {
  return (await Podcasts?.listAds()) ?? []
}

/** An episode's saved ads as JSON text, or null. */
export async function getAds(episodeId: string): Promise<string | null> {
  return (await Podcasts?.getAds(episodeId)) ?? null
}

export async function getAdSkipSettings(): Promise<AdSkipSettings> {
  return readAdSkipSettings(await Podcasts?.getAdSkipSettings())
}

const settingsListeners = new Set<() => void>()

/** Calls `listener` after the Skip ads settings are saved; returns the way to stop. */
export function onAdSkipSettingsChanged(listener: () => void): () => void {
  settingsListeners.add(listener)
  return () => {
    settingsListeners.delete(listener)
  }
}

export async function setAdSkipSettings(
  settings: AdSkipSettings,
): Promise<void> {
  await Podcasts?.setAdSkipSettings(
    settings.skipAds,
    settings.skipOwnPlugs,
    settings.skipPromos,
    settings.skipCredits,
  )
  settingsListeners.forEach((listener) => listener())
}

/**
 * The Skip ad button. Jumps to the end of the ad the phone knows here, or ahead 30 seconds and
 * notes a missed ad. Null when nothing is loaded.
 */
export async function skipAdNow(): Promise<{
  to: number
  known: boolean
} | null> {
  return (await Podcasts?.skipAdNow()) ?? null
}

/** Undoes the skip that was just made. False when it is too late (or there is nothing). */
export async function undoAdSkip(): Promise<boolean> {
  return (await Podcasts?.undoAdSkip()) ?? false
}

/**
 * Goes back a few seconds after a skip that went too far. The player saves a trim when that
 * lands inside the ad that was just skipped, so the ad ends there from then on.
 */
export async function backAfterSkip(): Promise<void> {
  await Podcasts?.skipBy(-SKIP_NOTE_BACK_SECONDS)
}
