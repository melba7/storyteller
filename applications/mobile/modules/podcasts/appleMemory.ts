// LOFI-FORK: the podcasts section's follow list from Apple Podcasts (see FORK.md).
//
// What the phone remembers about the Apple Podcasts list, in AsyncStorage: the shows already
// seen (so an unsubscribed one is not added again), the finished episodes already marked
// played, the ones the phone did not have yet, and when a show failed to subscribe. The rules
// are in applePodcasts.ts. Not imported by any test, because AsyncStorage is native.
import AsyncStorage from "@react-native-async-storage/async-storage"

import {
  parseFailures,
  parseSeen,
  settleArrival,
  withSeen,
} from "./applePodcasts"

export const SEEN_KEY = "podcasts.apple.seen"
export const APPLIED_KEY = "podcasts.apple.played"
export const PENDING_KEY = "podcasts.apple.pending"
export const FAILED_KEY = "podcasts.apple.failed"

export async function loadList(key: string): Promise<string[]> {
  return parseSeen(await AsyncStorage.getItem(key))
}

export async function saveList(key: string, list: readonly string[]) {
  await AsyncStorage.setItem(key, JSON.stringify(list))
}

export async function loadFailures(): Promise<Record<string, number>> {
  return parseFailures(await AsyncStorage.getItem(FAILED_KEY))
}

export async function saveFailures(failed: Record<string, number>) {
  await AsyncStorage.setItem(FAILED_KEY, JSON.stringify(failed))
}

/** An unsubscribed show goes on the seen list, so the sync does not add it again. */
export async function rememberUnsubscribed(feedUrl: string): Promise<void> {
  try {
    await saveList(SEEN_KEY, withSeen(await loadList(SEEN_KEY), feedUrl))
  } catch (cause) {
    console.warn("Couldn't remember an unsubscribed show", cause)
  }
}

/** Episodes of this show that arrived marked played: they are no longer pending but applied. */
export async function settleArrived(
  feedUrl: string,
  guids: readonly string[],
): Promise<void> {
  if (guids.length === 0) return
  try {
    const settled = settleArrival(
      await loadList(PENDING_KEY),
      await loadList(APPLIED_KEY),
      feedUrl,
      guids,
    )
    await saveList(PENDING_KEY, settled.pending)
    await saveList(APPLIED_KEY, settled.applied)
  } catch (cause) {
    console.warn("Couldn't keep the Apple Podcasts played list", cause)
  }
}
