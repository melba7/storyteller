// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { Alert } from "react-native"

import {
  deleteLocalEpisode,
  renameLocalEpisode,
} from "@/modules/podcasts/dbLocalFiles"
import { type StoredEpisode } from "@/modules/podcasts/library"
import { cleanName } from "@/modules/podcasts/localFiles"
import { readableError } from "@/modules/podcasts/nativeError"

function report(title: string) {
  return (cause: unknown) => Alert.alert(title, readableError(cause))
}

/** The menu entries of an added file: rename it, or delete it from this phone. */
export function localFileActions(episode: StoredEpisode) {
  return [
    {
      id: "rename",
      title: "Rename",
      onPress: () =>
        Alert.prompt(
          "Rename file",
          undefined,
          (text) => {
            const name = cleanName(text)
            if (name) {
              renameLocalEpisode(episode.id, name).catch(
                report("Couldn't rename the file"),
              )
            }
          },
          "plain-text",
          episode.title,
        ),
    },
    {
      id: "delete-file",
      title: "Delete file",
      attributes: { destructive: true },
      onPress: () =>
        Alert.alert(
          `Delete ${episode.title}?`,
          "The file is deleted from this phone. The original in the Files app stays.",
          [
            { text: "Cancel", style: "cancel" },
            {
              text: "Delete",
              style: "destructive",
              onPress: () =>
                deleteLocalEpisode(episode.id).catch(
                  report("Couldn't delete the file"),
                ),
            },
          ],
        ),
    },
  ]
}
