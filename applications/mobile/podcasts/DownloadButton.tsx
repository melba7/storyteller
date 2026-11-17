// LOFI-FORK: the podcasts section's screens (see FORK.md).
import { ArrowDownToLine, Check, CircleAlert, X } from "lucide-react-native"
import { ActivityIndicator, Pressable, View } from "react-native"
import { useCSSVariable } from "uniwind"

import { Icon } from "@/components/ui/icon"
import { Text } from "@/components/ui/text"
import { withAds } from "@/modules/podcasts/ads"
import { downloadLook } from "@/modules/podcasts/downloads"
import { Podcasts } from "@/modules/podcasts/index"
import { type StoredEpisode } from "@/modules/podcasts/library"
import { isLocalEpisodeId } from "@/modules/podcasts/localFiles"
import { withTranscript } from "@/modules/podcasts/transcripts"

import { ProgressRing } from "./PlayButton"
import { useAdsInfo } from "./useAds"
import { pressDownload, useDownload } from "./useDownloads"
import { useTranscript } from "./useTranscripts"

interface Props {
  episode: Pick<
    StoredEpisode,
    "id" | "showId" | "title" | "audioUrl" | "audioType"
  >
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
  const transcript = useTranscript(episode.id)
  const ads = useAdsInfo(episode.id)
  const primary = useCSSVariable("--color-primary") as string
  // An added file's download is its only copy: no button, so it can't be deleted from here.
  if (Podcasts === null || isLocalEpisodeId(episode.id)) return null
  const look = downloadLook(info, episode.title)
  // The transcript only matters once the audio is on the phone.
  const downloaded = info?.state === "downloaded"
  const status = withAds(
    withTranscript(look.status, downloaded ? transcript : undefined),
    downloaded && transcript?.state === "done" ? ads : undefined,
  )
  const inner = Math.round(size / 2)
  return (
    <View className="flex-row items-center gap-2">
      {showStatus && status ? (
        <Text className="text-muted-foreground text-sm">{status}</Text>
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
