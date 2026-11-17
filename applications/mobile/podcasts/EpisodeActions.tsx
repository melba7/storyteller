// LOFI-FORK: the podcasts section's screens (see FORK.md).
import {
  CircleCheck,
  Ellipsis,
  ListPlus,
  type LucideIcon,
  Star,
} from "lucide-react-native"
import { type ReactElement } from "react"
import { Pressable, View } from "react-native"

import { Icon } from "@/components/ui/icon"
import { Menu } from "@/components/ui/menu"
import { Text } from "@/components/ui/text"
import { downloadLook } from "@/modules/podcasts/downloads"
import { Podcasts } from "@/modules/podcasts/index"
import { type Show, type StoredEpisode } from "@/modules/podcasts/library"
import { isLocalEpisodeId } from "@/modules/podcasts/localFiles"
import { episodeShare } from "@/modules/podcasts/share"
import { isQueued, queuedLabel } from "@/modules/podcasts/upNext"

import { DownloadButton } from "./DownloadButton"
import { archiveAction, playedAction, starAction } from "./EpisodeMenu"
import { shareContent } from "./ShareButton"
import { chooseAndAddToPlaylist } from "./addToPlaylist"
import { localFileActions } from "./localFileActions"
import { useDownload } from "./useDownloads"
import { addToUpNext, removeQueued, useUpNext } from "./useUpNext"

/** One slot of the strip: a 48 pt round button with a caption under it. */
function Slot({
  caption,
  children,
}: {
  caption: string
  children: ReactElement
}) {
  return (
    <View className="w-16 items-center gap-1">
      {children}
      <Text className="text-muted-foreground text-center text-xs">
        {caption}
      </Text>
    </View>
  )
}

/** The round face of a slot. `on` tints it with the primary colour. */
function Face({
  icon,
  label,
  on = false,
  fill = false,
  onPress,
}: {
  icon: LucideIcon
  label: string
  on?: boolean
  fill?: boolean
  onPress?: () => void
}) {
  return (
    <Pressable
      className={`size-12 items-center justify-center rounded-full active:opacity-60 ${on ? "bg-primary/15" : "bg-secondary"}`}
      accessibilityRole="button"
      accessibilityLabel={label}
      onPress={onPress}
    >
      <Icon
        as={icon}
        size={22}
        className={on ? "text-primary" : "text-foreground"}
        fill={fill ? "currentColor" : "none"}
      />
    </Pressable>
  )
}

/**
 * The five actions of the episode card: Up Next (a menu), Download, Played, Star and More
 * (a menu). The slots wrap onto a second line at large text sizes.
 */
export function EpisodeActions({
  episode,
  show,
}: {
  episode: StoredEpisode
  show: Show | null
}) {
  const queue = useUpNext()
  const download = useDownload(episode.id)
  const queued = isQueued(queue, episode.id)
  const star = starAction(episode)
  const played = playedAction(episode)
  const archive = archiveAction(episode)
  const downloadWord = downloadLook(download, episode.title).icon
  const downloadCaption =
    downloadWord === "done"
      ? "Downloaded"
      : downloadWord === "progress" || downloadWord === "waiting"
        ? "Downloading"
        : downloadWord === "failed"
          ? "Retry"
          : "Download"
  return (
    <View className="w-full flex-row flex-wrap justify-between gap-y-4">
      {Podcasts === null ? null : (
        <Slot caption="Up Next">
          <Menu
            actions={[
              {
                id: "next",
                title: "Play next",
                onPress: () => addToUpNext(episode, show, "next"),
              },
              {
                id: "last",
                title: "Play last",
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
              className={`size-12 items-center justify-center rounded-full ${queued ? "bg-primary/15" : "bg-secondary"}`}
              accessibilityRole="button"
              accessibilityLabel={[
                `Up Next options for ${episode.title}`,
                queuedLabel(queue, episode.id),
              ]
                .filter((part) => part !== "")
                .join(". ")}
            >
              <Icon
                as={ListPlus}
                size={22}
                className={queued ? "text-primary" : "text-foreground"}
              />
            </Pressable>
          </Menu>
        </Slot>
      )}
      {Podcasts === null || isLocalEpisodeId(episode.id) ? null : (
        <Slot caption={downloadCaption}>
          <View className="bg-secondary size-12 items-center justify-center rounded-full">
            <DownloadButton episode={episode} size={48} />
          </View>
        </Slot>
      )}
      <Slot caption="Played">
        <Face
          icon={CircleCheck}
          on={episode.played}
          label={`${played.title} ${episode.title}`}
          onPress={played.onPress}
        />
      </Slot>
      <Slot caption={episode.starredAt === null ? "Star" : "Starred"}>
        <Face
          icon={Star}
          on={episode.starredAt !== null}
          fill={episode.starredAt !== null}
          label={`${star.title} ${episode.title}`}
          onPress={star.onPress}
        />
      </Slot>
      <Slot caption="More">
        <Menu
          actions={[
            {
              id: "playlist",
              title: "Add to playlist",
              onPress: () => void chooseAndAddToPlaylist(episode, show),
            },
            archive,
            {
              id: "share",
              title: "Share",
              onPress: () =>
                void shareContent(() => episodeShare(episode, show)),
            },
            ...(isLocalEpisodeId(episode.id) ? localFileActions(episode) : []),
          ]}
        >
          <Pressable
            className="bg-secondary size-12 items-center justify-center rounded-full"
            accessibilityRole="button"
            accessibilityLabel={`More for ${episode.title}`}
          >
            <Icon as={Ellipsis} size={22} className="text-foreground" />
          </Pressable>
        </Menu>
      </Slot>
    </View>
  )
}
