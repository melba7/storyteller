// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { AccessibilityInfo, Alert } from "react-native"

import { defaultBookmarkTitle } from "@/modules/podcasts/bookmarks"
import { addBookmark } from "@/modules/podcasts/dbBookmarks"
import { readableError } from "@/modules/podcasts/nativeError"
import { player } from "@/modules/podcasts/playerInstance"

import { done } from "./haptics"

/**
 * Bookmarks the place playing now, titled by its time ("Bookmark at 12:34"); the title can be
 * changed in the player's Bookmarks or in Profile's Bookmarks.
 */
export function addBookmarkHere() {
  const { episode, position } = player.getView()
  if (!episode) return
  addBookmark(episode.id, position).then(
    () => {
      done()
      AccessibilityInfo.announceForAccessibility(
        `${defaultBookmarkTitle(position)} added`,
      )
    },
    (cause: unknown) =>
      Alert.alert("Couldn't add the bookmark", readableError(cause)),
  )
}
