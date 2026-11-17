// LOFI-FORK: the podcasts section's new-episode notifications (see FORK.md).
//
// The setting, kept in AsyncStorage so the background task can read it, and thin wrappers over
// the native module's notification functions. Not imported by any test, because the native
// module is not there; the rule is in newEpisodeNotice.ts.
import AsyncStorage from "@react-native-async-storage/async-storage"

import { Podcasts } from "./index"

const KEY = "podcasts.notifyNew"

/** Whether "Notify me about new episodes" is on. Off when never set or unreadable. */
export async function loadNotifyNew(): Promise<boolean> {
  try {
    return (await AsyncStorage.getItem(KEY)) === "1"
  } catch {
    return false
  }
}

export async function saveNotifyNew(on: boolean): Promise<void> {
  await AsyncStorage.setItem(KEY, on ? "1" : "0")
}

export type NotificationPermission = "granted" | "denied" | "undetermined"

export async function notificationPermission(): Promise<NotificationPermission> {
  return (await Podcasts?.notificationPermission()) ?? "denied"
}

/** Asks the listener (iOS shows its own question the first time). True when allowed. */
export async function requestNotificationPermission(): Promise<boolean> {
  return (await Podcasts?.requestNotificationPermission()) ?? false
}

export async function postNotification(
  id: string,
  title: string,
  body: string,
): Promise<void> {
  await Podcasts?.postNotification(id, title, body)
}
