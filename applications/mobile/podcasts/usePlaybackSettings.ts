// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { useSyncExternalStore } from "react"
import { Alert } from "react-native"

import { readableError } from "@/modules/podcasts/nativeError"
import type { PlaybackSettings } from "@/modules/podcasts/playbackSettings"
import {
  changePlaybackSettings,
  getPlaybackSettings,
  subscribePlaybackSettings,
} from "@/modules/podcasts/playbackSettingsStore"

/** The listener's playback settings, read again when they change. */
export function usePlaybackSettings(): PlaybackSettings {
  return useSyncExternalStore(subscribePlaybackSettings, getPlaybackSettings)
}

/** Changes some settings; a failure to save shows a message and the old ones come back. */
export function updatePlaybackSettings(patch: Partial<PlaybackSettings>) {
  changePlaybackSettings(patch).catch((cause: unknown) =>
    Alert.alert("Couldn't save the setting", readableError(cause)),
  )
}
