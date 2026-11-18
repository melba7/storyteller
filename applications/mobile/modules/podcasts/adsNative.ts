// LOFI-FORK: the podcasts section's ads (see FORK.md).
//
// Thin wrappers over the native module's ad functions. Not imported by any test, because the
// native module is not there; the rules are in ads.ts.
import { type AdSkipSettings, type AdsInfo, Podcasts } from "./index"

export async function listAds(): Promise<AdsInfo[]> {
  return (await Podcasts?.listAds()) ?? []
}

/** An episode's saved ads as JSON text, or null. */
export async function getAds(episodeId: string): Promise<string | null> {
  return (await Podcasts?.getAds(episodeId)) ?? null
}

export async function getAdSkipSettings(): Promise<AdSkipSettings> {
  return (
    (await Podcasts?.getAdSkipSettings()) ?? {
      skipAds: true,
      skipOwnPlugs: true,
    }
  )
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
  await Podcasts?.setAdSkipSettings(settings.skipAds, settings.skipOwnPlugs)
  settingsListeners.forEach((listener) => listener())
}

/** Undoes the skip that was just made. False when it is too late (or there is nothing). */
export async function undoAdSkip(): Promise<boolean> {
  return (await Podcasts?.undoAdSkip()) ?? false
}
