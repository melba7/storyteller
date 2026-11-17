// LOFI-FORK: the podcasts section's automatic downloads and clean-up (see FORK.md).
//
// The two settings and the time of the last refresh, kept in AsyncStorage so the background
// task can read them too. A failure to read gives the defaults; a failure to save is reported.
import AsyncStorage from "@react-native-async-storage/async-storage"

import {
  type AutomaticSettings,
  DEFAULT_SETTINGS,
  parseSettings,
  serializeSettings,
} from "./automatic"

const SETTINGS_KEY = "podcasts.automatic"
const LAST_RUN_KEY = "podcasts.automatic.lastRun"

export async function loadSettings(): Promise<AutomaticSettings> {
  try {
    return parseSettings(await AsyncStorage.getItem(SETTINGS_KEY))
  } catch {
    return DEFAULT_SETTINGS
  }
}

export async function saveSettings(settings: AutomaticSettings): Promise<void> {
  await AsyncStorage.setItem(SETTINGS_KEY, serializeSettings(settings))
}

/** When feeds were last refreshed by the app by itself, or null. */
export async function loadLastRun(): Promise<number | null> {
  try {
    const value = Number(await AsyncStorage.getItem(LAST_RUN_KEY))
    return Number.isFinite(value) && value > 0 ? value : null
  } catch {
    return null
  }
}

export async function saveLastRun(at: number): Promise<void> {
  try {
    await AsyncStorage.setItem(LAST_RUN_KEY, String(at))
  } catch {
    // The next opening refreshes again; nothing else depends on it.
  }
}
