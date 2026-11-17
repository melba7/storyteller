// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { Bookmark, BookmarkCheck, ListPlus, Star } from "lucide-react-native"
import { useEffect, useRef, useState } from "react"
import { AccessibilityInfo, Alert, Pressable } from "react-native"

import { Icon } from "@/components/ui/icon"
import { defaultBookmarkTitle } from "@/modules/podcasts/bookmarks"
import { addBookmark } from "@/modules/podcasts/dbBookmarks"
import { setStarred } from "@/modules/podcasts/dbEpisodes"
import { readableError } from "@/modules/podcasts/nativeError"
import { player, usePlayerValue } from "@/modules/podcasts/playerInstance"
import { isPreviewId } from "@/modules/podcasts/preview"

import { chooseAndAddToPlaylist } from "./addToPlaylist"
import { useEpisode } from "./hooks"

/**
 * The player's buttons that work on the library: star, and (as they come) add to a playlist
 * and bookmark. Kept in one file so the player's own button row changes by one line.
 */
export function LibraryButtons() {
  const id = usePlayerValue((view) => view.episode?.id ?? "")
  if (id === "") return null
  return (
    <>
      {isPreviewId(id) ? null : <StarButton id={id} />}
      {isPreviewId(id) ? null : <BookmarkButton />}
      <PlaylistButton />
    </>
  )
}

/** Add what is playing to one of your own playlists, whether or not its show is followed. */
function PlaylistButton() {
  return (
    <Pressable
      className="size-11 items-center justify-center rounded-full bg-white/15 active:bg-white/25"
      accessibilityRole="button"
      accessibilityLabel="Add this episode to a playlist"
      onPress={() => {
        const { episode, show } = player.getView()
        if (episode) void chooseAndAddToPlaylist(episode, show)
      }}
    >
      <Icon as={ListPlus} size={22} className="text-white" />
    </Pressable>
  )
}

function StarButton({ id }: { id: string }) {
  const episode = useEpisode(id).data
  if (!episode) return null
  const starred = episode.starredAt !== null
  return (
    <Pressable
      className="size-11 items-center justify-center rounded-full bg-white/15 active:bg-white/25"
      accessibilityRole="button"
      accessibilityLabel={starred ? "Unstar this episode" : "Star this episode"}
      accessibilityState={{ selected: starred }}
      onPress={() => {
        setStarred([id], !starred).catch((cause: unknown) =>
          console.warn("Couldn't change the episode's star", cause),
        )
      }}
    >
      <Icon
        as={Star}
        size={22}
        className="text-white"
        fill={starred ? "#ffffff" : "none"}
      />
    </Pressable>
  )
}

/**
 * Bookmarks the place playing now, titled by its time ("Bookmark at 12:34"); the title can be
 * changed on the episode's card or in Profile's Bookmarks.
 */
function BookmarkButton() {
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
      className="size-11 items-center justify-center rounded-full bg-white/15 active:bg-white/25"
      accessibilityRole="button"
      accessibilityLabel="Add a bookmark here"
      onPress={() => {
        const { episode, position } = player.getView()
        if (!episode) return
        addBookmark(episode.id, position).then(
          () => {
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
