// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { ArrowDownToLine, Check, CircleAlert, X } from "lucide-react-native"
import { ActivityIndicator, Pressable, View } from "react-native"
import { useCSSVariable } from "uniwind"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { downloadLook } from "@/modules/podcasts/downloads"
import { Podcasts } from "@/modules/podcasts/index"
import { type StoredEpisode } from "@/modules/podcasts/library"

import { ProgressRing } from "./PlayButton"
import { pressDownload, useDownload } from "./useDownloads"

interface Props {
  episode: Pick<StoredEpisode, "id" | "title" | "audioUrl" | "audioType">
  size?: number
  /** Also writes what the download is doing beside the button (the episode card). */
  showStatus?: boolean
}

/**
 * The download button: an arrow to download, a ring while downloading (tap to cancel), a
 * check mark when done (tap to delete) and an alert mark after a failure (tap to try
 * again). Nothing where the app can't download.
 */
export function DownloadButton({
  episode,
  size = 36,
  showStatus = false,
}: Props) {
  const info = useDownload(episode.id)
  const primary = useCSSVariable("--color-primary") as string
  if (Podcasts === null) return null
  const look = downloadLook(info, episode.title)
  const inner = Math.round(size / 2)
  return (
    <View className="flex-row items-center gap-2">
      {showStatus && look.status ? (
        <Text className="text-muted-foreground text-sm">{look.status}</Text>
      ) : null}
      <Pressable
        className="items-center justify-center rounded-full active:opacity-60"
        style={{ width: size, height: size }}
        accessibilityRole="button"
        accessibilityLabel={look.label}
        onPress={() => pressDownload(look.action, episode)}
      >
        {look.icon === "download" ? (
          <Icon
            as={ArrowDownToLine}
            size={inner + 2}
            className="text-muted-foreground"
          />
        ) : null}
        {look.icon === "waiting" ? (
          <ActivityIndicator accessibilityLabel="Waiting to download" />
        ) : null}
        {look.icon === "progress" ? (
          look.fraction === null ? (
            <ActivityIndicator accessibilityLabel="Downloading" />
          ) : (
            <>
              <ProgressRing
                fraction={look.fraction}
                size={size - 4}
                color={primary}
              />
              <Icon as={X} size={inner - 2} className="text-primary" />
            </>
          )
        ) : null}
        {look.icon === "done" ? (
          <View
            className="bg-primary items-center justify-center rounded-full"
            style={{ width: inner + 6, height: inner + 6 }}
          >
            <Icon
              as={Check}
              size={inner - 2}
              className="text-primary-foreground"
            />
          </View>
        ) : null}
        {look.icon === "failed" ? (
          <Icon
            as={CircleAlert}
            size={inner + 4}
            className="text-destructive"
          />
        ) : null}
      </Pressable>
    </View>
  )
}
