// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { Bookmark, BookmarkCheck } from "lucide-react-native"
import { useEffect, useRef, useState } from "react"
import { AccessibilityInfo, Alert, Pressable } from "react-native"

import { Icon } from "@/components/ui/icon"
import { defaultBookmarkTitle } from "@/modules/podcasts/bookmarks"
import { addBookmark } from "@/modules/podcasts/dbBookmarks"
import { readableError } from "@/modules/podcasts/nativeError"
import { player } from "@/modules/podcasts/playerInstance"

import { done } from "./haptics"

/**
 * Bookmarks the place playing now, titled by its time ("Bookmark at 12:34"); the title can be
 * changed on the episode's card or in Profile's Bookmarks.
 */
export function BookmarkButton() {
  const [added, setAdded] = useState(false)
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  useEffect(
    () => () => {
      if (timer.current) clearTimeout(timer.current)
    },
    [],
  )
  return (
    <Pressable
      className="size-11 items-center justify-center rounded-full active:bg-white/15"
      accessibilityRole="button"
      accessibilityLabel="Add a bookmark here"
      onPress={() => {
        const { episode, position } = player.getView()
        if (!episode) return
        addBookmark(episode.id, position).then(
          () => {
            done()
            setAdded(true)
            if (timer.current) clearTimeout(timer.current)
            timer.current = setTimeout(() => setAdded(false), 2000)
            AccessibilityInfo.announceForAccessibility(
              `${defaultBookmarkTitle(position)} added`,
            )
          },
          (cause: unknown) =>
            Alert.alert("Couldn't add the bookmark", readableError(cause)),
        )
      }}
    >
      <Icon
        as={added ? BookmarkCheck : Bookmark}
        size={22}
        className="text-white"
      />
    </Pressable>
  )
}
