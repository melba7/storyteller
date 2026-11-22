// LOFI-FORK: the podcasts section's player screen (see FORK.md).
import { Text } from "@/components/ui/text"
import { playerAdLine } from "@/modules/podcasts/adLine"
import { skippingAnyFor } from "@/modules/podcasts/downloads"
import { Podcasts } from "@/modules/podcasts/index"
import type { Show, StoredEpisode } from "@/modules/podcasts/library"
import { usePlayerValue } from "@/modules/podcasts/playerInstance"

import { useSheet } from "./playerSheetContext"
import { useMainAdSettings } from "./useAdSettings"
import { useAdsInfo } from "./useAds"
import { useDownload } from "./useDownloads"
import { useTranscript } from "./useTranscripts"

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
  const main = useMainAdSettings(episode.id)
  const skipAds = main !== null && skippingAnyFor(show?.settings, main)
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
