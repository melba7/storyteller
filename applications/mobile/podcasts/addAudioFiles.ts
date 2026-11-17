// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Alert } from "react-native"

import { pickAndAddAudioFiles } from "@/modules/podcasts/dbLocalFiles"
import { readableError } from "@/modules/podcasts/nativeError"

/** Opens the Files app, adds the picked audio files and says what happened. */
export async function addAudioFiles(): Promise<void> {
  try {
    const summary = await pickAndAddAudioFiles()
    if (summary) Alert.alert("Your files", summary)
  } catch (cause) {
    Alert.alert("Couldn't add files", readableError(cause))
  }
}
