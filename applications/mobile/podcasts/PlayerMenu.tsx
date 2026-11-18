// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { useRouter } from "expo-router"
import { Ellipsis } from "lucide-react-native"
import { View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Menu } from "@/components/ui/menu"
import { setStarred } from "@/modules/podcasts/dbEpisodes"
import { lastTabSegments } from "@/modules/podcasts/lastTab"
import { formatTime } from "@/modules/podcasts/playbackRules"
import {
  markPlayed,
  player,
  usePlayer,
} from "@/modules/podcasts/playerInstance"
import { playerMenuActions } from "@/modules/podcasts/playerMenuActions"
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
 * The "..." at the right of the title. The actions are built in playerMenuActions, short enough
 * to never need scrolling.
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

  const actions = playerMenuActions({
    preview,
    saved,
    played,
    timeText: formatTime(view.position),
    hasChapters: chapters.length > 0,
    hasShow: show !== null && show !== undefined,
    on: {
      save: () => {
        setStarred([id], !saved).catch((cause: unknown) =>
          console.warn("Couldn't change the episode's save", cause),
        )
      },
      share: () =>
        void shareContent(() => {
          const now = player.getView()
          return now.episode ? episodeShare(now.episode, now.show) : null
        }),
      shareFrom: () =>
        void shareContent(() => {
          const now = player.getView()
          return now.episode
            ? placeShare(now.episode, now.show, now.position)
            : null
        }),
      playlist: () => void chooseAndAddToPlaylist(episode, show),
      episode: () => leaveTo(episodeHref(segments, id)),
      show: () => {
        if (!show) return
        leaveTo(
          preview
            ? previewHref(segments, show.feedUrl)
            : showHref(segments, show.id),
        )
      },
      allChapters: () => onPanel("chapters"),
      previousChapter: () => chapterActions.previous(),
      nextChapter: () => chapterActions.next(),
      notes: () => onPanel("notes"),
      addBookmark: addBookmarkHere,
      allBookmarks: () => onPanel("bookmarks"),
      played: () => {
        markPlayed([id], !played).catch((cause: unknown) =>
          console.warn("Couldn't change the episode's played mark", cause),
        )
      },
      settings: () => {
        if (show) leaveTo(settingsHref(segments, show.id))
      },
    },
  })

  return (
    <Menu actions={actions}>
      <View
        className="size-11 items-center justify-center"
        accessibilityRole="button"
        accessibilityLabel="More: save, share, playlist, go to the episode or show, chapters, notes, bookmarks, mark as played, show settings"
      >
        <Icon as={Ellipsis} size={24} color={sheet.ink} />
      </View>
    </Menu>
  )
}
