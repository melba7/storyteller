// LOFI-FORK: the podcasts section's player menu (see FORK.md).
import { type MenuAction } from "@/components/ui/menu"

/**
 * What the player's "..." menu needs, as plain values and callbacks. The menu is short on purpose:
 * iOS 26 would not scroll a long one inside the player's sheet, so the top level has at most 10
 * rows, and the rarer actions sit in submenus.
 */
export type PlayerMenuInput = {
  preview: boolean
  saved: boolean
  played: boolean
  /** The playback position as text, like "1:02". */
  timeText: string
  hasChapters: boolean
  hasShow: boolean
  on: {
    save: () => void
    share: () => void
    shareFrom: () => void
    playlist: () => void
    episode: () => void
    show: () => void
    allChapters: () => void
    previousChapter: () => void
    nextChapter: () => void
    notes: () => void
    addBookmark: () => void
    allBookmarks: () => void
    played: () => void
    settings: () => void
  }
}

/** Four sections with no title, which SwiftUI draws as plain separators. Empty ones are left out. */
export function playerMenuActions(input: PlayerMenuInput): MenuAction[] {
  const { preview, saved, played, on } = input

  const first: MenuAction[] = []
  if (!preview) {
    first.push({
      id: "save",
      title: saved ? "Unsave Episode" : "Save Episode",
      image: saved ? "bookmark.slash" : "plus.circle",
      onPress: on.save,
    })
  }
  first.push(
    {
      id: "share-menu",
      title: "Share",
      image: "square.and.arrow.up",
      subactions: [
        {
          id: "share",
          title: "Share Episode",
          image: "square.and.arrow.up",
          onPress: on.share,
        },
        {
          id: "share-from",
          title: `Share from ${input.timeText}`,
          image: "clock.arrow.circlepath",
          onPress: on.shareFrom,
        },
      ],
    },
    {
      id: "playlist",
      title: "Add to Playlist",
      image: "text.badge.plus",
      onPress: on.playlist,
    },
  )

  const places: MenuAction[] = []
  if (!preview) {
    places.push({
      id: "episode",
      title: "Go to Episode",
      image: "doc.text",
      onPress: on.episode,
    })
  }
  if (input.hasShow) {
    places.push({
      id: "show",
      title: "Go to Show",
      image: "square.stack",
      onPress: on.show,
    })
  }

  const inside: MenuAction[] = []
  if (input.hasChapters) {
    inside.push({
      id: "chapters-menu",
      title: "Chapters",
      image: "list.number",
      subactions: [
        {
          id: "chapters",
          title: "All Chapters",
          image: "list.number",
          onPress: on.allChapters,
        },
        {
          id: "previous",
          title: "Previous Chapter",
          image: "backward.end",
          onPress: on.previousChapter,
        },
        {
          id: "next",
          title: "Next Chapter",
          image: "forward.end",
          onPress: on.nextChapter,
        },
      ],
    })
  }
  inside.push({
    id: "notes",
    title: "Notes",
    image: "text.alignleft",
    onPress: on.notes,
  })
  if (!preview) {
    inside.push({
      id: "bookmarks-menu",
      title: "Bookmarks",
      image: "bookmark.fill",
      subactions: [
        {
          id: "bookmark",
          title: "Add Bookmark",
          image: "bookmark",
          onPress: on.addBookmark,
        },
        {
          id: "bookmarks",
          title: "All Bookmarks",
          image: "bookmark.fill",
          onPress: on.allBookmarks,
        },
      ],
    })
  }

  const last: MenuAction[] = []
  if (!preview) {
    last.push({
      id: "played",
      title: played ? "Mark as Unplayed" : "Mark as Played",
      image: played ? "circle" : "checkmark.circle",
      onPress: on.played,
    })
    if (input.hasShow) {
      last.push({
        id: "settings",
        title: "Show Settings",
        image: "gearshape",
        onPress: on.settings,
      })
    }
  }

  return [first, places, inside, last]
    .map((subactions, index) => ({
      id: `section-${index + 1}`,
      title: "",
      displayInline: true,
      subactions,
    }))
    .filter((section) => section.subactions.length > 0)
}
