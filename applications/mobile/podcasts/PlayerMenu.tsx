// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { useRouter } from "expo-router"
import { Ellipsis } from "lucide-react-native"
import { View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { type MenuAction, Menu } from "@/components/ui/menu"
import { setStarred } from "@/modules/podcasts/dbEpisodes"
import { lastTabSegments } from "@/modules/podcasts/lastTab"
import { formatTime } from "@/modules/podcasts/playbackRules"
import {
  markPlayed,
  player,
  usePlayer,
} from "@/modules/podcasts/playerInstance"
import { isPreviewId } from "@/modules/podcasts/preview"
import {
  episodeHref,
  previewHref,
  settingsHref,
  showHref,
} from "@/modules/podcasts/routes"
import { episodeShare, placeShare } from "@/modules/podcasts/share"

import { type PlayerPanel } from "./PlayerPages"
import { shareContent } from "./ShareButton"
import { chooseAndAddToPlaylist } from "./addToPlaylist"
import { addBookmarkHere } from "./bookmarkHere"
import { useEpisode } from "./hooks"
import { useSheet } from "./playerSheetContext"
import { chapterActions, useChapters } from "./useChapters"

/**
 * The "..." at the right of the title: Save, Share (the episode, or from this place), Go to
 * Episode and Show, Chapters (with the previous and next one), Notes, Add Bookmark and
 * Bookmarks, Add to Playlist, Mark as Played and Show settings.
 */
export function PlayerMenu({
  onPanel,
}: {
  onPanel: (panel: PlayerPanel) => void
}) {
  const sheet = useSheet()
  const router = useRouter()
  // The player is a modal, so its own segments name no tab: use the tab you were in.
  const segments = lastTabSegments()
  const view = usePlayer()
  const { episode, show } = view
  const id = episode?.id ?? ""
  const stored = useEpisode(id).data
  const chapters = useChapters(id)
  if (!episode) return null
  const preview = isPreviewId(id)
  const saved = (stored?.starredAt ?? null) !== null
  const played = stored?.played ?? false

  // Leave the player, then open the page in the tab you were in before the player (see lastTab).
  function leaveTo(href: Parameters<typeof router.push>[0]) {
    if (router.canGoBack()) router.back()
    router.push(href)
  }

  const places: MenuAction[] = []
  if (!preview) {
    places.push({
      id: "episode",
      title: "Go to Episode",
      image: "doc.text",
      onPress: () => leaveTo(episodeHref(segments, id)),
    })
  }
  if (show) {
    places.push({
      id: "show",
      title: "Go to Show",
      image: "square.stack",
      onPress: () =>
        leaveTo(
          preview
            ? previewHref(segments, show.feedUrl)
            : showHref(segments, show.id),
        ),
    })
  }

  const inside: MenuAction[] = [
    {
      id: "notes",
      title: "Notes",
      image: "text.alignleft",
      onPress: () => onPanel("notes"),
    },
  ]
  if (chapters.length > 0) {
    inside.unshift(
      {
        id: "chapters",
        title: "Chapters",
        image: "list.number",
        onPress: () => onPanel("chapters"),
      },
      {
        id: "previous",
        title: "Previous Chapter",
        image: "backward.end",
        onPress: () => chapterActions.previous(),
      },
      {
        id: "next",
        title: "Next Chapter",
        image: "forward.end",
        onPress: () => chapterActions.next(),
      },
    )
  }

  const keep: MenuAction[] = []
  if (!preview) {
    keep.push(
      {
        id: "bookmark",
        title: "Add Bookmark",
        image: "bookmark",
        onPress: addBookmarkHere,
      },
      {
        id: "bookmarks",
        title: "Bookmarks",
        image: "bookmark.fill",
        onPress: () => onPanel("bookmarks"),
      },
    )
  }
  keep.push({
    id: "playlist",
    title: "Add to Playlist",
    image: "text.badge.plus",
    onPress: () => void chooseAndAddToPlaylist(episode, show),
  })

  const actions: MenuAction[] = [
    ...(preview
      ? []
      : [
          {
            id: "save",
            title: saved ? "Unsave Episode" : "Save Episode",
            image: saved ? "bookmark.slash" : "plus.circle",
            onPress: () => {
              setStarred([id], !saved).catch((cause: unknown) =>
                console.warn("Couldn't change the episode's save", cause),
              )
            },
          } satisfies MenuAction,
        ]),
    {
      id: "share",
      title: "Share Episode",
      image: "square.and.arrow.up",
      onPress: () =>
        void shareContent(() => {
          const now = player.getView()
          return now.episode ? episodeShare(now.episode, now.show) : null
        }),
    },
    {
      id: "share-from",
      title: `Share from ${formatTime(view.position)}`,
      image: "clock.arrow.circlepath",
      onPress: () =>
        void shareContent(() => {
          const now = player.getView()
          return now.episode
            ? placeShare(now.episode, now.show, now.position)
            : null
        }),
    },
    { id: "places", title: "Go to", displayInline: true, subactions: places },
    {
      id: "inside",
      title: "In this episode",
      displayInline: true,
      subactions: inside,
    },
    { id: "keep", title: "Keep", displayInline: true, subactions: keep },
    ...(preview
      ? []
      : [
          {
            id: "played",
            title: played ? "Mark as Unplayed" : "Mark as Played",
            image: played ? "circle" : "checkmark.circle",
            onPress: () => {
              markPlayed([id], !played).catch((cause: unknown) =>
                console.warn(
                  "Couldn't change the episode's played mark",
                  cause,
                ),
              )
            },
          } satisfies MenuAction,
        ]),
    ...(show && !preview
      ? [
          {
            id: "settings",
            title: "Show Settings",
            image: "gearshape",
            onPress: () => leaveTo(settingsHref(segments, show.id)),
          } satisfies MenuAction,
        ]
      : []),
  ]

  return (
    <Menu actions={actions}>
      <View
        className="size-11 items-center justify-center"
        accessibilityRole="button"
        accessibilityLabel="More: save, share, go to the episode or show, chapters, notes, bookmarks, playlist"
      >
        <Icon as={Ellipsis} size={24} color={sheet.ink} />
      </View>
    </Menu>
  )
}
