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
  /** "onColor" draws everything in white, for a button on a coloured surface. */
  tone?: "default" | "onColor"
}

/**
 * What the download is doing, in words: the size or "Downloading 40%", then what the
 * transcript and the ad scan are doing once the audio is on the phone. Empty when there is
 * nothing to say, and for an added file.
 */
export function useDownloadStatus(episode: Props["episode"]): string {
  const info = useDownload(episode.id)
  const transcript = useTranscript(episode.id)
  const ads = useAdsInfo(episode.id)
  if (Podcasts === null || isLocalEpisodeId(episode.id)) return ""
  const look = downloadLook(info, episode.title)
  // The transcript only matters once the audio is on the phone.
  const downloaded = info?.state === "downloaded"
  return withAds(
    withTranscript(look.status, downloaded ? transcript : undefined),
    downloaded && transcript?.state === "done" ? ads : undefined,
  )
}

/** The status line on the episode card. */
export function DownloadStatusLine({ episode }: { episode: Props["episode"] }) {
  const status = useDownloadStatus(episode)
  return status ? (
    <Text className="text-muted-foreground text-sm">{status}</Text>
  ) : null
}

const WHITE = "#ffffff"

/**
 * The download button: an arrow to download, a ring while downloading (tap to cancel), a
 * check mark when done (tap to delete) and an alert mark after a failure (tap to try
 * again). Nothing where the app can't download.
 */
export function DownloadButton({
  episode,
  size = 36,
  tone = "default",
}: Props) {
  const info = useDownload(episode.id)
  const themePrimary = useCSSVariable("--color-primary") as string
  const onColor = tone === "onColor"
  const primary = onColor ? WHITE : themePrimary
  const spinner = onColor ? WHITE : undefined
  // An added file's download is its only copy: no button, so it can't be deleted from here.
  if (Podcasts === null || isLocalEpisodeId(episode.id)) return null
  const look = downloadLook(info, episode.title)
  const inner = Math.round(size / 2)
  return (
    <View className="flex-row items-center gap-2">
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
            className={onColor ? "text-white" : "text-muted-foreground"}
          />
        ) : null}
        {look.icon === "waiting" ? (
          <ActivityIndicator
            color={spinner}
            accessibilityLabel="Waiting to download"
          />
        ) : null}
        {look.icon === "progress" ? (
          look.fraction === null ? (
            <ActivityIndicator
              color={spinner}
              accessibilityLabel="Downloading"
            />
          ) : (
            <>
              <ProgressRing
                fraction={look.fraction}
                size={size - 4}
                color={primary}
              />
              <Icon
                as={X}
                size={inner - 2}
                className={onColor ? "text-white" : "text-primary"}
              />
            </>
          )
        ) : null}
        {look.icon === "done" ? (
          <View
            className={`items-center justify-center rounded-full ${onColor ? "border-2 border-white" : "bg-primary"}`}
            style={{ width: inner + 6, height: inner + 6 }}
          >
            <Icon
              as={Check}
              size={inner - 2}
              className={onColor ? "text-white" : "text-primary-foreground"}
            />
          </View>
        ) : null}
        {look.icon === "failed" ? (
          <Icon
            as={CircleAlert}
            size={inner + 4}
            className={onColor ? "text-white" : "text-destructive"}
          />
        ) : null}
      </Pressable>
    </View>
  )
}
