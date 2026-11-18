// LOFI-FORK: the podcasts section's ads (see FORK.md).
//
// The one quiet line in the player that says how ad finding is going for the episode that
// plays. Plain rules over what Swift reports; the texts of the ads and the transcript come
// from ads.ts and transcripts.ts.
import { adsStatus } from "./ads"
import type { AdsInfo, DownloadInfo, TranscriptInfo } from "./index"
import { isLocalEpisodeId } from "./localFiles"
import { isPreviewId } from "./preview"
import { transcriptStatus } from "./transcripts"

const READY = "Getting ready to find ads"

function cannot(reason: string): string {
  return reason === "" ? "Ads can't be found" : `Ads can't be found: ${reason}`
}

function percentOf(value: number | undefined): number | null {
  return value === undefined
    ? null
    : Math.max(0, Math.min(100, Math.floor(value)))
}

/**
 * What the player says about ad finding: empty while Skip ads is off or for an added file or
 * a preview. A plain stream (no download, or a failed one) is "Streaming without ad skipping",
 * because ads are found only in a file on the phone.
 */
export function playerAdLine(input: {
  episodeId: string
  skipAds: boolean
  download: DownloadInfo | undefined
  transcript?: TranscriptInfo | undefined
  ads?: AdsInfo | undefined
}): string {
  const { episodeId, skipAds, download, transcript, ads } = input
  if (!skipAds) return ""
  if (isLocalEpisodeId(episodeId) || isPreviewId(episodeId)) return ""
  if (download === undefined || download.state === "failed") {
    return "Streaming without ad skipping"
  }
  if (download.state !== "downloaded") return READY
  if (ads?.state === "unavailable") return cannot(ads.reason ?? "")
  if (ads?.state === "found" || ads?.state === "noAds") return adsStatus(ads)
  if (transcript?.state === "unsupported" || transcript?.state === "failed") {
    return cannot(transcriptStatus(transcript))
  }
  if (transcript?.state === "transcribing") {
    const percent = percentOf(transcript.percent)
    return percent === null
      ? "Finding ads"
      : `Finding ads, ${percent}% transcribed`
  }
  if (ads?.state === "finding") {
    const percent = percentOf(ads.percent)
    return percent === null ? "Finding ads" : `Finding ads, ${percent}%`
  }
  return READY
}

/**
 * The ads part of an episode's status line: nothing before the audio is on the phone. Before
 * the transcript is done only the reason and the results show, not "Waiting to find ads".
 */
export function adsToShow(
  downloaded: boolean,
  transcript: TranscriptInfo | undefined,
  ads: AdsInfo | undefined,
): AdsInfo | undefined {
  if (!downloaded || ads === undefined) return undefined
  if (transcript?.state === "done") return ads
  return ads.state === "waiting" || ads.state === "finding" ? undefined : ads
}
