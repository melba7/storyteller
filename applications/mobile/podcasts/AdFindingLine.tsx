// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { useEffect, useState } from "react"

import { Text } from "@/components/ui/text"
import { playerAdLine } from "@/modules/podcasts/adLine"
import {
  getAdSkipSettings,
  onAdSkipSettingsChanged,
} from "@/modules/podcasts/adsNative"
import { skipAdsFor } from "@/modules/podcasts/downloads"
import { Podcasts } from "@/modules/podcasts/index"
import type { Show, StoredEpisode } from "@/modules/podcasts/library"
import { usePlayerValue } from "@/modules/podcasts/playerInstance"

import { useSheet } from "./playerSheetContext"
import { useAdsInfo } from "./useAds"
import { useDownload } from "./useDownloads"
import { useTranscript } from "./useTranscripts"

// The last value read, so the line is drawn right away when the player opens and does not
// push the artwork and controls down a moment later.
let lastMain = false

/** The Skip ads switch for this show, read again when the episode or the setting changes. */
function useSkipAds(show: Show | null, episodeId: string): boolean {
  const [main, setMain] = useState(lastMain)
  const [round, setRound] = useState(0)
  useEffect(() => onAdSkipSettingsChanged(() => setRound((r) => r + 1)), [])
  useEffect(() => {
    let live = true
    getAdSkipSettings().then(
      (value) => {
        lastMain = value.skipAds
        if (live) setMain(value.skipAds)
      },
      () => {},
    )
    return () => {
      live = false
    }
  }, [episodeId, round])
  return skipAdsFor(show?.settings.skipAds, main)
}

/**
 * One quiet line under the seek bar that says how ad finding is going for this episode, only
 * while Skip ads is on: "Finding ads, 40% transcribed", "3 ads found", the reason ads can't
 * be found, or that a plain stream can't be skipped.
 */
export function AdFindingLine({
  episode,
  show,
}: {
  episode: Pick<StoredEpisode, "id">
  show: Show | null
}) {
  const sheet = useSheet()
  const skipAds = useSkipAds(show, episode.id)
  const download = useDownload(episode.id)
  const transcript = useTranscript(episode.id)
  const ads = useAdsInfo(episode.id)
  const streamsPlain = usePlayerValue(
    (view) => view.episode?.id === episode.id && view.streamsPlain,
  )
  const checkingStart = usePlayerValue(
    (view) => view.episode?.id === episode.id && view.checkingStart,
  )
  if (Podcasts === null) return null
  const line = playerAdLine({
    episodeId: episode.id,
    skipAds,
    download,
    transcript,
    ads,
    streamsPlain,
    checkingStart,
  })
  if (line === "") return null
  return (
    <Text
      className="text-center text-xs"
      style={{ color: sheet.muted }}
      numberOfLines={1}
      accessibilityLabel={line}
    >
      {line}
    </Text>
  )
}
