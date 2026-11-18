// LOFI-FORK: the podcasts section's screens (see FORK.md).
import {
  Bookmark,
  Ellipsis,
  ListCheck,
  ListPlus,
  Share,
  type LucideIcon,
} from "lucide-react-native"
import { useState } from "react"
import { Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Menu } from "@/components/ui/menu"
import { Podcasts } from "@/modules/podcasts/index"
import { type Show, type StoredEpisode } from "@/modules/podcasts/library"
import { isLocalEpisodeId } from "@/modules/podcasts/localFiles"
import { actionGap } from "@/modules/podcasts/playerFrame"
import { isPreviewId } from "@/modules/podcasts/preview"
import { episodeShare } from "@/modules/podcasts/share"
import { isQueued, queuedLabel } from "@/modules/podcasts/upNext"

import { DownloadButton } from "./DownloadButton"
import { EpisodeMenu, starAction } from "./EpisodeMenu"
import { shareContent } from "./ShareButton"
import { addToUpNext, removeQueued, useUpNext } from "./useUpNext"

const SHAPE = "size-12 items-center justify-center rounded-full"
const FACE = `${SHAPE} bg-white/25`

/** One round glass-like button of the row. `on` fills the symbol. */
function Face({
  icon,
  label,
  on = false,
  onPress,
}: {
  icon: LucideIcon
  label: string
  on?: boolean
  onPress?: () => void
}) {
  return (
    <Pressable
      className={`${FACE} active:opacity-60`}
      accessibilityRole="button"
      accessibilityLabel={label}
      onPress={onPress}
    >
      <Icon
        as={icon}
        size={22}
        className="text-white"
        fill={on ? "#ffffff" : "none"}
      />
    </Pressable>
  )
}

/**
 * The row under the episode page's title, as round buttons: Save, Download, Up Next (a menu),
 * Share and "..." (the whole episode menu, which also holds Mark as Played, Add to Playlist,
 * Archive and an added file's Rename and Delete). They sit on the show's colour, so white.
 */
export function EpisodeActions({
  episode,
  show,
}: {
  episode: StoredEpisode
  show: Show | null
}) {
  const queue = useUpNext()
  const queued = isQueued(queue, episode.id)
  const star = starAction(episode)
  const library = !isPreviewId(episode.id)
  const hasDownload = Podcasts !== null && !isLocalEpisodeId(episode.id)
  // The round buttons are 48 pt: on a 320 pt screen five of them need a gap under 16.
  const [rowWidth, setRowWidth] = useState<number | null>(null)
  const count =
    2 + (library ? 1 : 0) + (hasDownload ? 1 : 0) + (Podcasts === null ? 0 : 1)
  return (
    <View
      className="w-full flex-row items-center justify-center"
      style={{ gap: actionGap(rowWidth, count) }}
      onLayout={(event) => setRowWidth(event.nativeEvent.layout.width)}
    >
      {library ? (
        <Face
          icon={Bookmark}
          on={episode.starredAt !== null}
          label={`${star.title} ${episode.title}`}
          onPress={star.onPress}
        />
      ) : null}
      {hasDownload ? (
        <View className={FACE}>
          <DownloadButton episode={episode} size={48} tone="onColor" />
        </View>
      ) : null}
      {Podcasts === null ? null : (
        <Menu
          actions={[
            {
              id: "next",
              title: "Play Next",
              onPress: () => addToUpNext(episode, show, "next"),
            },
            {
              id: "last",
              title: "Play Last",
              onPress: () => addToUpNext(episode, show, "last"),
            },
            ...(queued
              ? [
                  {
                    id: "remove",
                    title: "Remove from Up Next",
                    attributes: { destructive: true },
                    onPress: () => removeQueued(episode.id),
                  },
                ]
              : []),
          ]}
        >
          <Pressable
            className={queued ? `${SHAPE} bg-white/50` : FACE}
            accessibilityRole="button"
            accessibilityLabel={[
              `Up Next options for ${episode.title}`,
              queuedLabel(queue, episode.id),
            ]
              .filter((part) => part !== "")
              .join(". ")}
          >
            <Icon
              as={queued ? ListCheck : ListPlus}
              size={22}
              className="text-white"
            />
          </Pressable>
        </Menu>
      )}
      <Face
        icon={Share}
        label={`Share ${episode.title}`}
        onPress={() => void shareContent(() => episodeShare(episode, show))}
      />
      <EpisodeMenu episode={episode} show={show} here={{ episode: true }}>
        <View
          className={FACE}
          accessible
          accessibilityRole="button"
          accessibilityLabel={`More for ${episode.title}`}
        >
          <Icon as={Ellipsis} size={22} className="text-white" />
        </View>
      </EpisodeMenu>
    </View>
  )
}
